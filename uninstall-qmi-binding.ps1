# Copyright (c) 2026 anti-rainer
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
#
# Removes the WinUSB binding installed by install-qmi-binding.ps1 and returns
# the module's QMI function to the vendor's own driver arrangement.
#
# What to remove is read from the packages themselves. The install script
# discovers a module's QMI function, writes that hardware id into the INF it
# signs, and Windows keeps its own copy of that INF under %windir%\INF - so the
# package, not a table in this file, is what says which function to hand back.
# Every Celmux package is handled, because binding a second module installs a
# second one.

#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    # Device instance patterns to remove, as wildcards, e.g.
    # 'USB\VID_2C7C&PID_0125&MI_04*'. Empty means "ask the installed INFs".
    [string[]]$InstanceFilter = @(),
    # One published name (oem42.inf) instead of every Celmux package.
    [string]$PublishedName,
    # Append everything this run prints to a file, so a caller that only sees
    # the exit code can show what happened. The client always passes one.
    [string]$LogPath,
    [string]$CertificateSubject = 'CN=Celmux QMI Driver'
)

$ErrorActionPreference = 'Stop'

$restartRequired = $false

function Invoke-PnpUtil {
    param([string[]]$Arguments, [string]$Operation)
    # Native stderr is diagnostic output; the exit code decides whether the
    # operation succeeded, including on Windows PowerShell 5.1.
    $previousErrorAction = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        # Native processes update the global automatic variable; do not shadow it.
        $global:LASTEXITCODE = $null
        $output = & pnputil.exe @Arguments 2>&1
        $exitCode = $global:LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorAction
    }
    $output | ForEach-Object { Write-Host "  $_" }
    if ($null -eq $exitCode) {
        throw "$Operation could not run pnputil.exe. Check that Windows PnPUtil is available."
    }
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
    $packages = @(Get-WindowsDriver -Online -ErrorAction SilentlyContinue |
        Where-Object { $_.OriginalFileName -like '*celmux-qmi.inf' } |
        Select-Object -ExpandProperty Driver |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ } |
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

if ($InstanceFilter.Count -gt 0) {
    foreach ($device in (Get-PnpDevice -PresentOnly)) {
        $matched = $InstanceFilter | Where-Object { $device.InstanceId -like $_ } | Select-Object -First 1
        if (-not $matched) { continue }
        Write-Host "Removing the device node of $($device.InstanceId) ..."
        Invoke-PnpUtil -Arguments @('/remove-device', $device.InstanceId) -Operation 'Removing the device node'
    }
}

foreach ($package in $packages) {
    Write-Host "Deleting driver package $package ..."
    Invoke-PnpUtil -Arguments @('/delete-driver', $package, '/uninstall') -Operation "Deleting driver package $package"
}

Invoke-PnpUtil -Arguments @('/scan-devices') -Operation 'Rescanning devices'

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
