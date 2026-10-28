# Copyright (c) 2026 anti-rainer
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
#
# Removes the binding installed by install-module-driver.ps1: the module's QMI
# function returns to whatever driver Windows would pick for it on its own.
#
# Only the QMI half is touched. The module's serial functions belong to the
# vendor's driver package (Quectel), which this project neither installs nor
# removes.
#
# What to remove is read from the packages themselves. The install script
# discovers the QMI function, writes that hardware id into the INF it signs, and
# Windows keeps its own copy of that INF under %windir%\INF - so the package, not
# a table in this file, is what says which function to hand back. Every Celmux
# package is handled, because binding a second module installs a second one.

#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    # Device instance patterns to remove, as wildcards, e.g.
    # 'USB\VID_2C7C&PID_0125&MI_04*'. Empty means "ask the installed INFs".
    [string[]]$InstanceFilter = @(),
    # Also remove the device nodes, not just the driver package.
    #
    # Off by default: a removed node makes the next install start the function
    # from scratch, while a node that is merely unbound re-binds in under a
    # second. Set it when a node has to be detached before a vendor driver can
    # claim it.
    [switch]$RemoveNodes,
    # One published name (oem42.inf) instead of every Celmux package.
    [string]$PublishedName,
    # Append everything this run prints to a file, so a caller that only sees
    # the exit code can show what happened. The client always passes one.
    [string]$LogPath,
    # One line per event, written as it happens; the window host tails it while
    # the elevated script runs, since an elevated child's stdout does not come
    # back to the process that started it.
    [string]$ProgressPath,
    [string]$CertificateSubject = 'CN=Celmux QMI Driver'
)

$ErrorActionPreference = 'Stop'

$restartRequired = $false

# Same step markers as the installer: the window host streams them into the
# runtime log while the script runs, so a slow or failed run names its step.
$script:stepStarted = @{}
$script:progressFile = $ProgressPath
function Write-Progress-Line {
    param([string]$Line)
    if (-not $script:progressFile) { return }
    try {
        # UTF-8 explicitly: the window host reads this file as UTF-8, and
        # pnputil prints in the console code page.
        $stream = [IO.File]::AppendText($script:progressFile)
        try {
            $bytes = [Text.Encoding]::UTF8.GetBytes($Line + "`r`n")
            $stream.BaseStream.Write($bytes, 0, $bytes.Length)
            $stream.Flush()
        } finally { $stream.Dispose() }
    } catch {
        # A missing progress file must never fail the uninstall itself.
    }
}
function Write-Step {
    param([string]$Name)
    $script:stepStarted[$Name] = Get-Date
    Write-Host "[celmux-step] begin $Name"
    Write-Progress-Line "[celmux-step] begin $Name"
}
function Complete-Step {
    param([string]$Name)
    $started = $script:stepStarted[$Name]
    if (-not $started) { return }
    $elapsed = ((Get-Date) - $started).TotalSeconds
    $script:stepStarted.Remove($Name)
    $text = ("[celmux-step] end {0} {1:N2}s" -f $Name, $elapsed)
    Write-Host $text
    Write-Progress-Line $text
}

# Run one pnputil operation, with a deadline.
#
# pnputil has no timeout of its own. An operation that touches a device Windows
# cannot start waits out a fixed ~120s, which makes an uninstall look hung. A
# timed-out operation is reported and the script continues: what is left behind
# is reported from the device tree at the end.
function Invoke-PnpUtil {
    param([string[]]$Arguments, [string]$Operation, [int]$TimeoutSeconds = 60)
    Write-Step $Operation
    # pnputil writes in the console's OEM code page, which a captured pipe turns
    # into mojibake whatever the reading side does. Telling cmd to switch the
    # console to UTF-8 first is the one arrangement where the bytes, the pipe
    # and the reader all agree; the output is then decoded as UTF-8 below.
    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = "$env:ComSpec"
    $quoted = ($Arguments | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' '
    $info.Arguments = "/c chcp 65001 >nul & pnputil.exe $quoted"
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $info
    [void]$process.Start()
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $stdoutReader = New-Object System.IO.StreamReader($process.StandardOutput.BaseStream, $utf8)
    $stderrReader = New-Object System.IO.StreamReader($process.StandardError.BaseStream, $utf8)
    $stdoutTask = $stdoutReader.ReadToEndAsync()
    $stderrTask = $stderrReader.ReadToEndAsync()
    $exited = $process.WaitForExit($TimeoutSeconds * 1000)
    if (-not $exited) {
        try { $process.Kill() } catch { }
        [void]$process.WaitForExit(5000)
        Write-Warning "$Operation did not finish within ${TimeoutSeconds}s and was stopped."
    }
    $decoded = $stdoutTask.Result + "`n" + $stderrTask.Result
    foreach ($line in ($decoded -split "`r?`n")) {
        if (-not $line.Trim()) { continue }
        Write-Host "  $line"
        Write-Progress-Line "[celmux-output] $line"
    }
    $exitCode = if ($exited) { $process.ExitCode } else { $null }
    $process.Dispose()
    Complete-Step $Operation
    if (-not $exited) { return }
    if ($exitCode -eq 3010) {
        $script:restartRequired = $true
        Write-Host "$Operation requires a Windows restart (pnputil exit code 3010)."
    } elseif ($exitCode -ne 0) {
        throw "$Operation failed (pnputil exit code $exitCode). Check the PnPUtil output above; the driver operation did not complete."
    }
}

if ($LogPath) {
    Start-Transcript -Path $LogPath -Force | Out-Null
}

try {

$packages = @()
if ($PublishedName) {
    $packages = @($PublishedName.Trim())
} else {
    # Read the published INFs instead of asking DISM for the whole driver store:
    # Get-WindowsDriver takes several seconds on a machine with a large store,
    # and the INF copies Windows keeps under %windir%\INF say the same thing.
    # Only packages whose catalog is one of ours count.
    $infDirectory = Join-Path $env:windir 'INF'
    $packages = @(Get-ChildItem -LiteralPath $infDirectory -Filter 'oem*.inf' -ErrorAction SilentlyContinue |
        Where-Object {
            $text = Get-Content -LiteralPath $_.FullName -Raw -ErrorAction SilentlyContinue
            $text -and $text -match '(?im)^\s*CatalogFile\s*=\s*celmux-\w+\.cat'
        } |
        ForEach-Object { $_.Name } |
        Select-Object -Unique)
}
if ($packages.Count -eq 0) {
    Write-Warning 'The Celmux QMI driver package is not installed.'
    exit 0
}
Write-Host "Celmux driver packages: $($packages -join ', ')"

if ($InstanceFilter.Count -eq 0) {
    $patterns = @()
    foreach ($package in $packages) {
        $installedInf = Join-Path $env:windir ('INF\' + $package)
        if (-not (Test-Path -LiteralPath $installedInf)) { continue }
        $patterns += @([regex]::Matches(
                (Get-Content -LiteralPath $installedInf -Raw),
                'USB\\VID_[0-9A-Fa-f]{4}&PID_[0-9A-Fa-f]{4}&MI_[0-9A-Fa-f]{2}'
            ) | ForEach-Object { $_.Value + '*' })
    }
    $InstanceFilter = @($patterns | Select-Object -Unique)
    if ($InstanceFilter.Count -gt 0) {
        Write-Host "The packages bind: $($InstanceFilter -join ', ')"
    } else {
        Write-Warning "Could not read the bound hardware ids from the installed INFs; only the driver packages will be removed. Pass -InstanceFilter 'USB\VID_....*' to remove a device node as well."
    }
}

# The device nodes are deliberately NOT removed.
#
# `/remove-device` looks like a clean uninstall, but it makes the next install
# expensive: Windows has to create the function again and start it from scratch,
# and binding a removed serial function that way took two minutes on this
# machine. Deleting the driver package alone leaves the node in place; the next
# install re-binds it in well under a second.
#
# `-RemoveNodes` keeps the old behaviour for the case it is actually for: a node
# whose driver has to be detached before a vendor driver can take over.

if ($RemoveNodes -and $InstanceFilter.Count -gt 0) {
    # One query for the whole tree: Get-PnpDevice costs a WMI round trip per
    # property read, and this only needs the instance ids.
    foreach ($device in (Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue)) {
        $instanceId = $device.PNPDeviceID
        if (-not $instanceId) { continue }
        $matched = $InstanceFilter | Where-Object { $instanceId -like $_ } | Select-Object -First 1
        if (-not $matched) { continue }
        Write-Host "Removing the device node of $instanceId ..."
        Invoke-PnpUtil -Arguments @('/remove-device', $instanceId) -Operation 'Removing the device node'
    }
} elseif ($InstanceFilter.Count -gt 0) {
    Write-Host "Keeping the device nodes in place: $($InstanceFilter -join ', ')"
}

foreach ($package in $packages) {
    Write-Host "Deleting driver package $package ..."
    Invoke-PnpUtil -Arguments @('/delete-driver', $package, '/uninstall') -Operation "Deleting driver package $package"
}

Invoke-PnpUtil -Arguments @('/scan-devices') -Operation 'rescan devices' -TimeoutSeconds 15

# The certificate this package created is only useful to it, so it goes too.
$certificates = Get-ChildItem Cert:\CurrentUser\My |
    Where-Object { $_.Subject -eq $CertificateSubject }
foreach ($certificate in $certificates) {
    foreach ($store in 'Cert:\LocalMachine\TrustedPublisher', 'Cert:\LocalMachine\Root') {
        Get-ChildItem $store |
            Where-Object { $_.Thumbprint -eq $certificate.Thumbprint } |
            Remove-Item -Force
    }
    Remove-Item -LiteralPath ("Cert:\CurrentUser\My\" + $certificate.Thumbprint) -Force
    Write-Host "Removed signing certificate $($certificate.Thumbprint)"
}

if ($restartRequired) {
    Write-Host 'The Celmux driver package was removed; restart Windows to finish removing it and restore the previous driver.'
} else {
    Write-Host 'Done: Windows will bind the module again with whatever driver it used before.'
}

} finally {
    if ($LogPath) {
        Stop-Transcript | Out-Null
    }
}
