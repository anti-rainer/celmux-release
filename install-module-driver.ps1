# Copyright (c) 2026 anti-rainer
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
#
# Binds a module's QMI (RMNET) function to WinUSB so the service can reach it.
#
# Only the QMI function is bound here. The module's serial functions (diagnostic,
# NMEA, AT, modem) are left to the vendor's own driver package: Quectel's driver
# claims them and publishes them as COM ports, which is what the AT terminal
# needs. Binding them to the inbox usbser driver instead made every install wait
# out a fixed two-minute PnP timeout on the modem function - the reason this
# script no longer touches them.
#
# PnP classes and interface numbers cannot identify QMI: an unbound serial
# function and the diagnostic function can look just like RMNET. Automatic
# selection only matches the verified hardware IDs in celmux-module.inf. Other
# layouts require -HardwareId (or an unambiguous -Interface).
#
# Windows refuses a third-party INF that carries no digital signature, and this
# package is not something a vendor signs for us. It therefore signs its own
# catalog with a certificate generated on this machine:
#
#   * a code-signing certificate "CN=Celmux QMI Driver" is created in the
#     current user's personal store with a non-exportable key - it only ever
#     signs this machine's own catalogs - and its public part is added to this
#     machine's Trusted Root and Trusted Publishers stores;
#   * the QMI function is bound to the WinUSB driver Microsoft ships. The
#     package contains no driver binary of its own.
#
# `uninstall-module-driver.ps1` removes the binding again. `-Preview` performs
# the discovery and writes the generated INF without changing anything, which
# needs no elevation.

[CmdletBinding()]
param(
    # Restrict discovery to one vendor, e.g. 0x2C7C. Empty means the known
    # module vendors (Quectel, Qualcomm and Baiwang).
    [string]$Vendor,
    # Explicitly select one decimal function number (10 = MI_0a) as the QMI
    # function. If several modules match, use -HardwareId to name the model.
    [int]$Interface = -1,
    # Bind one function named by its hardware id, e.g.
    # USB\VID_2C7C&PID_0125&MI_04, as the QMI function. Needed when the
    # module's QMI function is claimed by a vendor driver, so discovery cannot
    # offer it, or when a layout has to be pinned by hand. The id is the one
    # Windows shows for the function, and the vendor driver has to be detached
    # from it first: a function can only have one driver.
    [string]$HardwareId,
    # Report the plan and write the generated INF, but change nothing.
    [switch]$Preview,
    # Append everything this run prints to a file, so a caller that only sees
    # the exit code can show what happened.
    [string]$LogPath,
    # One line per event, written as it happens.
    #
    # The installer runs elevated, and an elevated child's stdout does not come
    # back to the process that started it. A file does: the window host tails
    # this one while the script runs, which is how a step that is still going
    # (or one that never finished) becomes visible instead of a silent wait.
    [string]$ProgressPath,
    [string]$CertificateSubject = 'CN=Celmux QMI Driver'
)

$ErrorActionPreference = 'Stop'

# The vendors a Qualcomm-based module reports as. A module from another vendor
# is bound by naming it: -Vendor 0x1234.
$moduleVendors = @('2C7C', '05C6', '2CA3')

$restartRequired = $false

# ---- Step reporting ---------------------------------------------------------
#
# Every step writes one line in a fixed shape:
#
#   [celmux-step] begin <name>
#   [celmux-step] end   <name> <seconds>s
#
# The window host reads this stream while the script runs, so the log page
# shows which step is in progress and which one a slow or failed run stopped
# in. The prefix is deliberately unlikely to occur in pnputil's own output.
$script:stepStarted = @{}
$script:progressFile = $ProgressPath
# pnputil writes in the console's OEM code page (936 on a Chinese Windows).
# Matching the console to it is what keeps its output readable when captured
# through a pipe; UTF-8 here would turn every Chinese line into mojibake.
try {
    [Console]::OutputEncoding = [Text.Encoding]::GetEncoding(
        [System.Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage)
} catch { }
function Write-Progress-Line {
    param([string]$Line)
    if (-not $script:progressFile) { return }
    try {
        # UTF-8 explicitly: pnputil prints in the console code page, and the
        # window host reads this file as UTF-8.
        $stream = [IO.File]::AppendText($script:progressFile)
        try {
            $bytes = [Text.Encoding]::UTF8.GetBytes($Line + "`r`n")
            $stream.BaseStream.Write($bytes, 0, $bytes.Length)
            $stream.Flush()
        } finally { $stream.Dispose() }
    } catch {
        # A missing progress file must never fail the install itself.
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
# cannot start waits out a fixed ~120s, which is what made an install look hung.
# A timed-out operation is reported and returns; the caller verifies the result
# from the device tree, which is the authority either way.
# pnputil writes in the console's OEM code page, which a captured pipe turns
# into mojibake whatever the reading side does. Telling cmd to switch the
# console to UTF-8 first is the one arrangement where the bytes, the pipe and
# the reader all agree; the output is then decoded as UTF-8 below.
function Invoke-PnpUtil {
    param([string[]]$Arguments, [string]$Operation, [int]$TimeoutSeconds = 60)
    Write-Step $Operation
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
    # Read the raw stream through a UTF-8 reader: the console above is UTF-8,
    # and PowerShell 5.1 would otherwise decode with the OEM code page.
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
        # pnputil's own words are the evidence behind a failed step, so they
        # travel with the step lines instead of only into the transcript.
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

function Test-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal($identity)).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )
}

Write-Step 'check administrator rights'
if (-not $Preview -and -not (Test-Admin)) {
    throw 'Binding a driver package needs an administrator shell; re-run this script from one (or pass -Preview to see the plan).'
}
Complete-Step 'check administrator rights'

if ($LogPath) {
    Start-Transcript -Path $LogPath -Force | Out-Null
}

function Get-ModuleCandidates {
    param([string[]]$Vendors)
    $candidates = @()
    # One query for every function, with the driver state attached: the Win32
    # PnP provider answers in a single round trip, while Get-PnpDeviceProperty
    # costs a separate WMI query per device and per key.
    foreach ($device in (Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue |
            Where-Object { $_.PNPDeviceID -like 'USB\VID_*&PID_*&MI_*' })) {
        $match = [regex]::Match($device.PNPDeviceID, 'VID_([0-9A-Fa-f]{4})&PID_([0-9A-Fa-f]{4})&MI_([0-9A-Fa-f]{2})')
        if (-not $match.Success) { continue }
        $vendor = $match.Groups[1].Value.ToUpperInvariant()
        if ($Vendors.Count -gt 0 -and $Vendors -notcontains $vendor) { continue }
        $candidates += [pscustomobject]@{
            VendorId     = $vendor
            ProductId    = $match.Groups[2].Value.ToUpperInvariant()
            Interface    = [Convert]::ToInt32($match.Groups[3].Value, 16)
            Class        = $device.PNPClass
            FriendlyName = $device.Name
            InstanceId   = $device.PNPDeviceID
            Status       = $device.Status
            # ConfigManagerErrorCode is DEVPKEY_Device_ProblemCode and Service is
            # DEVPKEY_Device_Service; both come with the entity itself.
            Service      = "$($device.Service)"
            ProblemCode  = $device.ConfigManagerErrorCode
        }
    }
    $candidates
}

# Whether any of the named functions is in the device tree right now.
function Test-AnyPresent {
    param([string[]]$HardwareIds)
    if (-not $HardwareIds -or $HardwareIds.Count -eq 0) { return $false }
    foreach ($device in (Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue)) {
        $id = $device.PNPDeviceID
        if (-not $id) { continue }
        foreach ($wanted in $HardwareIds) {
            if ($id -like "$wanted*") { return $true }
        }
    }
    return $false
}

# Ask Windows to rescan and give the QMI function a moment to appear.
#
# An uninstall removes the device node, and the module's functions only come
# back once Windows rescans. Deciding "the QMI function is not present" from a
# tree that is one rescan behind is what once made this installer bind nothing
# and still report success, so the decision is only taken after a rescan.
function Invoke-DeviceRescan {
    param([string[]]$HardwareIds, [int]$TimeoutSeconds = 4)
    Invoke-PnpUtil -Arguments @('/scan-devices') -Operation 'rescan devices' -TimeoutSeconds 15
    if (-not $HardwareIds -or $HardwareIds.Count -eq 0) { return }
    if (Test-AnyPresent -HardwareIds $HardwareIds) { return }
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 500
        if (Test-AnyPresent -HardwareIds $HardwareIds) { return }
    }
}

# The packages this project installed, read from the INF copies Windows keeps.
#
# Get-WindowsDriver asks DISM for the whole driver store, which takes seconds on
# this machine; the published INFs under %windir%\INF carry the same facts in
# about a tenth of a second. Only packages whose catalog is one of ours count.
function Get-CelmuxPackages {
    $packages = @()
    $infDirectory = Join-Path $env:windir 'INF'
    foreach ($file in (Get-ChildItem -LiteralPath $infDirectory -Filter 'oem*.inf' -ErrorAction SilentlyContinue)) {
        $text = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction SilentlyContinue
        if (-not $text) { continue }
        if ($text -notmatch '(?im)^\s*CatalogFile\s*=\s*celmux-(\w+)\.cat') { continue }
        $part = $Matches[1].ToLowerInvariant()
        $version = [datetime]::MinValue
        $stamp = [regex]::Match($text, '(?im)^\s*DriverVer\s*=\s*([^,\r\n]+)')
        if ($stamp.Success) { [void][datetime]::TryParse($stamp.Groups[1].Value.Trim(), [ref]$version) }
        $packages += [pscustomobject]@{
            Published   = $file.Name
            Part        = $part
            Version     = $version
            HardwareIds = @([regex]::Matches($text, 'USB\\VID_[0-9A-Fa-f]{4}&PID_[0-9A-Fa-f]{4}&MI_[0-9A-Fa-f]{2}') |
                ForEach-Object { $_.Value.ToUpperInvariant() } | Sort-Object -Unique)
        }
    }
    $packages
}

# Every install stamps a fresh DriverVer, so each run that binds publishes a new
# package. The older copies are dead weight - they only make the store slower to
# enumerate - and go once a newer package covers the same function.
function Remove-SupersededPackages {
    param($Packages)
    $groups = @($Packages | Group-Object {
            $ids = if ($_.HardwareIds.Count -gt 0) { $_.HardwareIds -join ',' } else { '' }
            "$($_.Part)|$ids"
        })
    foreach ($group in $groups) {
        $ordered = @($group.Group | Sort-Object Version -Descending)
        if ($ordered.Count -lt 2) { continue }
        foreach ($old in ($ordered | Select-Object -Skip 1)) {
            try {
                Invoke-PnpUtil -Arguments @('/delete-driver', $old.Published, '/uninstall') -Operation "Removing the superseded package $($old.Published)" -TimeoutSeconds 20
            } catch {
                Write-Warning "The superseded package $($old.Published) was left in place: $($_.Exception.Message)"
            }
        }
    }
}

$hardwareIdPattern = '^USB\\VID_[0-9A-Fa-f]{4}&PID_[0-9A-Fa-f]{4}&MI_[0-9A-Fa-f]{2}$'
$packageDir = $PSScriptRoot
$qmiTemplate = Join-Path $packageDir 'celmux-module.inf'
if (-not (Test-Path -LiteralPath $qmiTemplate)) {
    throw "driver template not found next to this script: $qmiTemplate"
}
$templateText = Get-Content -LiteralPath $qmiTemplate -Raw
# Only model entries count; comments or installed/generated INF packages are
# not evidence that a function has been verified as QMI.
$verifiedHardwareIds = @([regex]::Matches($templateText,
        '(?im)^\s*%DeviceName%\s*=\s*CelmuxQmi_Install\s*,\s*(USB\\VID_[0-9A-F]{4}&PID_[0-9A-F]{4}&MI_[0-9A-F]{2})\s*$') |
    ForEach-Object { $_.Groups[1].Value.ToUpperInvariant() } | Sort-Object -Unique)

if ($HardwareId) {
    # One function named by the operator. Discovery is skipped on purpose: this
    # form exists exactly for the functions discovery cannot offer, and it also
    # makes a run reproducible when several modules are attached.
    if ($HardwareId -notmatch $hardwareIdPattern) {
        throw "HardwareId must look like USB\VID_2C7C&PID_0125&MI_04 (got '$HardwareId')."
    }
    $HardwareId = $HardwareId.ToUpperInvariant()
    $parts = [regex]::Match($HardwareId, 'VID_([0-9A-F]{4})&PID_([0-9A-F]{4})&MI_([0-9A-Fa-f]{2})')
    $chosen = [pscustomobject]@{
        VendorId     = $parts.Groups[1].Value
        ProductId    = $parts.Groups[2].Value
        Interface    = [Convert]::ToInt32($parts.Groups[3].Value, 16)
        Class        = 'named on the command line'
        FriendlyName = $HardwareId
    }
    $present = Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue |
        Where-Object { $_.PNPDeviceID -like "$HardwareId*" } |
        Select-Object -First 1
    if (-not $present) {
        Write-Warning "No present device matches $HardwareId. Connect the module before installation can verify its WinUSB binding."
    }
} else {
    $vendors = if ($Vendor) { @(($Vendor -replace '^0x', '').ToUpperInvariant()) } else { $moduleVendors }
    Write-Step 'discover module functions'
    # The device tree may be one rescan behind - right after an uninstall the
    # module's functions are gone until Windows rescans - so settle it before
    # deciding which functions exist.
    $interfaces = @(Get-ModuleCandidates -Vendors $vendors)
    # A rescan needs administrator rights, and `-Preview` deliberately runs
    # without them; it reports what the tree shows right now instead.
    if ($interfaces.Count -eq 0 -and -not $Preview) {
        Invoke-DeviceRescan -HardwareIds @($verifiedHardwareIds)
        $interfaces = @(Get-ModuleCandidates -Vendors $vendors)
    }
    Complete-Step 'discover module functions'
    if ($interfaces.Count -eq 0) {
        throw "No module function was found for vendor(s) $($vendors -join ', '). Plug the module in and run this again."
    }

    $report = ($interfaces | Sort-Object VendorId, ProductId, Interface | ForEach-Object {
            "  USB\VID_{0}&PID_{1}&MI_{2:x2}  class={3} status={4} {5}" -f
                $_.VendorId, $_.ProductId, $_.Interface, $_.Class, $_.Status, $_.FriendlyName
        }) -join "`n"
    if ($Interface -ge 0) {
        $selected = @($interfaces | Where-Object { $_.Interface -eq $Interface })
        if ($selected.Count -ne 1) {
            throw ("Interface $Interface matches $($selected.Count) present functions; selection must be unambiguous.`n" +
                $report + "`nPass -HardwareId 'USB\VID_....&PID_....&MI_..' for the confirmed QMI function.")
        }
        $chosen = $selected[0]
    } else {
        # A missing QMI child must not redirect installation to a serial/DM
        # function, even if it is the only candidate or already uses WinUSB.
        $verified = @($interfaces | Where-Object {
                $candidateId = 'USB\VID_{0}&PID_{1}&MI_{2:X2}' -f $_.VendorId, $_.ProductId, $_.Interface
                $verifiedHardwareIds -contains $candidateId
            })
        # Multiple instances of one verified model share the binding and are
        # safe; different verified hardware IDs require an explicit choice.
        $verifiedGroups = @($verified | Group-Object VendorId, ProductId, Interface)
        if ($verifiedGroups.Count -gt 1) {
            throw ("Cannot select one verified QMI hardware ID (matched $($verifiedGroups.Count)).`n" +
                $report + "`nConfirm its USB descriptors (interrupt IN plus bulk IN/OUT), then pass " +
                "-HardwareId 'USB\VID_....&PID_....&MI_..'. If the confirmed function is missing, restore/reconnect it first; " +
                "do not bind another function in its place.")
        }
        if ($verifiedGroups.Count -eq 1) {
            $chosen = $verifiedGroups[0].Group[0]
        } else {
            # The verified QMI function is not on the wire at all - most often
            # because the module re-enumerated into a USB layout without one
            # (a usbcfg fallback after a reset or a power cycle). Nothing is
            # bound in that case: the data function is never guessed from what
            # happens to be present, and the operator is told what to do.
            throw ('None of the verified QMI hardware IDs is present; the module is enumerated ' +
                'without its QMI function. Restore the QMI layout (e.g. AT+QCFG="usbcfg" over ' +
                'the module`s AT port), replug, and run this installer again.' + "`n" + $report)
        }
    }
}

$boundHardwareId = 'USB\VID_{0}&PID_{1}&MI_{2:x2}' -f $chosen.VendorId, $chosen.ProductId, $chosen.Interface
# A function already served by WinUSB is bound: adding the package again would
# publish a duplicate of the same binding, and every extra package slows the
# store down. Only an unbound or failing function needs the INF.
$alreadyBound = ([string]$chosen.Service -eq 'WinUSB') -and ($null -ne $chosen.ProblemCode) -and ($chosen.ProblemCode -eq 0)
if ($alreadyBound) {
    Write-Host "Module QMI function: $boundHardwareId (already bound to WinUSB)"
} else {
    Write-Host "Module QMI function: $boundHardwareId ($($chosen.Class))"
}

# ---- Stage and sign the INF. ------------------------------------------------
# The catalog is generated per machine because it is signed by a certificate
# generated per machine, so the repository keeps only the template and the tools
# work in a staging directory.
$stage = Join-Path $env:TEMP ('celmux-driver-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
trap {
    if ($stage) { Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue }
    throw
}
New-Item -ItemType Directory -Path $stage -Force | Out-Null

# Windows will not replace a package that reports the same version as the one
# already installed, and binding a second module writes a second hardware id
# into a second package. Each run therefore carries its own version, built from
# the date plus the minute so it only ever moves forward.
$now = (Get-Date).ToUniversalTime()
$build = [int](New-TimeSpan -Start ([datetime]'2024-01-01') -End $now).TotalDays % 60000
$driverVersion = '{0:MM/dd/yyyy},1.0.{1}.{2}' -f $now, $build, ($now.Hour * 60 + $now.Minute)

function Write-StagedInf {
    param([string]$Text, [string]$Name, [string]$Directory)
    $rewritten = $Text -replace 'DriverVer\s*=\s*\d{2}/\d{2}/\d{4},[0-9.]+', "DriverVer   = $driverVersion"
    if ($rewritten -eq $Text) {
        throw "the driver template carries no DriverVer to stamp: $Name"
    }
    New-Item -ItemType Directory -Path $Directory -Force | Out-Null
    $rewritten | Set-Content -LiteralPath (Join-Path $Directory $Name) -Encoding Ascii
}

$qmiDir = $null
$qmiNeeded = -not $alreadyBound
if ($qmiNeeded) {
    $qmiDir = Join-Path $stage 'module'
    $qmiText = $templateText
    if ($qmiText -notmatch 'USB\\VID_[0-9A-Fa-f]{4}&PID_[0-9A-Fa-f]{4}&MI_[0-9A-Fa-f]{2}') {
        throw "the driver template carries no hardware id to replace: $qmiTemplate"
    }
    $qmiText = $qmiText -replace 'USB\\VID_[0-9A-Fa-f]{4}&PID_[0-9A-Fa-f]{4}&MI_[0-9A-Fa-f]{2}', $boundHardwareId
    Write-StagedInf -Name 'celmux-module.inf' -Text $qmiText -Directory $qmiDir
}
Write-Host "Staged the driver package in $stage"

if ($Preview) {
    Write-Host 'Preview: nothing was signed, trusted or installed. The generated INF binds:'
    Get-ChildItem -LiteralPath $stage -Recurse -Filter *.inf | ForEach-Object {
        Write-Host "  $($_.FullName):"
        Select-String -LiteralPath $_.FullName -Pattern 'CelmuxQmi_Install, ' | ForEach-Object { "    $($_.Line.Trim())" }
    }
    if ($LogPath) { Stop-Transcript | Out-Null }
    exit 0
}

Write-Step 'prepare signing certificate'
Write-Host "Preparing the signing certificate $CertificateSubject ..."
$certificate = Get-ChildItem Cert:\CurrentUser\My |
    Where-Object { $_.Subject -eq $CertificateSubject } |
    Select-Object -First 1
if (-not $certificate) {
    # The key only ever signs this machine's own catalogs, so it is created
    # non-exportable: an exportable key would let any process running as this
    # user copy it and sign a driver package Windows on this machine accepts.
    $certificate = New-SelfSignedCertificate `
        -Type CodeSigningCert `
        -Subject $CertificateSubject `
        -CertStoreLocation Cert:\CurrentUser\My `
        -KeyUsage DigitalSignature `
        -KeyExportPolicy NonExportable `
        -NotAfter (Get-Date).AddYears(10)
    Write-Host "  created $($certificate.Thumbprint) (private key not exportable)"
} else {
    Write-Host "  reusing $($certificate.Thumbprint)"
    # An earlier version of this script created an exportable key. Say so
    # instead of silently keeping it: replacing it means unbinding and binding
    # again, which is the operator's call.
    try {
        $existingKey = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($certificate)
        if ($existingKey) {
            $null = $existingKey.ExportParameters($true)
            Write-Warning ("现有的 Celmux 签名证书（{0}）私钥是可导出的，来自旧版本脚本。要让这台机器改用不可导出的证书：先运行 uninstall-module-driver.ps1，再重新绑定一次。" -f $certificate.Thumbprint)
        }
    } catch {
        # Not exportable, or not an RSA key: nothing to report.
    }
}

$publicCert = Join-Path $stage 'celmux-driver.cer'
Export-Certificate -Cert $certificate -FilePath $publicCert -Force | Out-Null
Write-Step 'trust the signing certificate'
foreach ($store in 'Cert:\LocalMachine\TrustedPublisher', 'Cert:\LocalMachine\Root') {
    $trusted = Get-ChildItem $store | Where-Object { $_.Thumbprint -eq $certificate.Thumbprint }
    if (-not $trusted) {
        Import-Certificate -FilePath $publicCert -CertStoreLocation $store | Out-Null
        Write-Host "  trusted in $store"
    }
}
Complete-Step 'prepare signing certificate'
Complete-Step 'trust the signing certificate'

# The catalog comes from the Windows catalog APIs rather than the SDK's
# makecat/signtool pair, so this runs on a machine with no development tools.
if ($qmiNeeded) {
    $inf = Join-Path $qmiDir 'celmux-module.inf'
    Write-Step 'sign celmux-module.inf'
    Write-Host 'Generating the catalog ...'
    $catalogPath = Join-Path $qmiDir 'celmux-module.cat'
    New-FileCatalog -Path $inf -CatalogFilePath $catalogPath -CatalogVersion 2 | Out-Null
    if (-not (Test-Path -LiteralPath $catalogPath)) {
        throw "the catalog was not produced at $catalogPath"
    }
    Write-Host 'Signing the catalog ...'
    $signature = Set-AuthenticodeSignature `
        -FilePath $catalogPath `
        -Certificate $certificate `
        -HashAlgorithm SHA256
    if ($signature.Status -ne 'Valid') {
        throw "the catalog signature is not valid: $($signature.Status) $($signature.StatusMessage)"
    }
    Write-Host "  signed by $($signature.SignerCertificate.Subject)"
    Complete-Step 'sign celmux-module.inf'
    Write-Host 'Adding the driver package ...'
    Invoke-PnpUtil -Arguments @('/add-driver', $inf, '/install') -Operation 'bind the QMI function to WinUSB'
}

Write-Host 'Rescanning devices ...'
Invoke-PnpUtil -Arguments @('/scan-devices') -Operation 'rescan devices' -TimeoutSeconds 15

# Every run that binds publishes a package with a fresh DriverVer; the older
# copies are dead weight and go now that a newer one covers the same function.
Write-Step 'remove superseded packages'
Remove-SupersededPackages -Packages (Get-CelmuxPackages)
Complete-Step 'remove superseded packages'

$restartHint = if ($restartRequired) { ' Windows requested a restart; restart Windows and run this script again to verify the binding.' } else { '' }

# ---- Verify the QMI binding. ------------------------------------------------
Write-Step 'verify the binding'
$device = @(Get-CimInstance Win32_PnPEntity -ErrorAction Stop |
    Where-Object { $_.PNPDeviceID -like "$boundHardwareId*" })
if ($device.Count -eq 0) {
    throw "Cannot verify the WinUSB binding: the function ($boundHardwareId) is not present. Connect the module and run this script again.$restartHint"
}
$bindingFailures = @()
foreach ($entry in $device) {
    Write-Host ("{0}: status={1} service={2} problem={3}" -f $entry.PNPDeviceID, $entry.Status, $entry.Service, $entry.ConfigManagerErrorCode)
    if ($entry.Service -ne 'WinUSB' -or $null -eq $entry.ConfigManagerErrorCode -or $entry.ConfigManagerErrorCode -ne 0) {
        $bindingFailures += "$($entry.PNPDeviceID): Service='$($entry.Service)', ProblemCode='$($entry.ConfigManagerErrorCode)'"
    }
}
if ($bindingFailures.Count -gt 0) {
    throw ("The QMI function is not usable: the binding must report Service=WinUSB and ProblemCode=0. " +
        ($bindingFailures -join '; ') + ". Check the PnPUtil output and the function in Device Manager.$restartHint")
}
Write-Host "The QMI function $boundHardwareId is bound to WinUSB; the service can claim it now."
if ($alreadyBound) {
    Write-Host 'Nothing needed binding: the QMI function was already on WinUSB.'
}
if ($restartRequired) {
    Write-Host 'The binding is verified, but Windows also requested a restart to finish the driver operation.'
}
Complete-Step 'verify the binding'
if ($stage) { Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue }
Write-Host 'Done.'
if ($LogPath) { Stop-Transcript | Out-Null }
