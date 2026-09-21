# Copyright (c) 2026 anti-rainer
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
#
# Binds a module's QMI (RMNET) function to the WinUSB driver so the service can
# reach it. Run it once per machine, as an administrator.
#
# The function is found, not guessed. A module presents several interfaces and
# Windows classifies each one: the DM, NMEA and AT ports are `Ports`, the
# modem is `Modem`, the sound card is `MEDIA` - and the QMI/RMNET function is
# the vendor-specific one that no class driver claims (`USBDevice`). That is
# the interface this script binds, so a module family added later needs no
# table here; `-Interface` overrides the choice when a module exposes more than
# one such function.
#
# The INF that gets installed is generated from `celmux-qmi.inf` next to this
# script, with the discovered hardware id written into it, so one template
# covers every module instead of a list of product ids that rots.
#
# Windows refuses a third-party INF that carries no digital signature, and this
# package is not something a vendor signs for us. It therefore signs its own
# catalog with a certificate generated on this machine:
#
#   * a code-signing certificate "CN=Celmux QMI Driver" is created in the
#     current user's personal store with a non-exportable key - it only ever
#     signs this machine's own catalog - and its public part is added to this
#     machine's Trusted Root and Trusted Publishers stores;
#   * the module's QMI function is bound to the WinUSB driver Microsoft ships.
#     The package contains no driver binary of our own and touches nothing but
#     that one function.
#
# `uninstall-qmi-binding.ps1` removes both again. `-Preview` performs the
# discovery and writes the generated INF without changing anything, which needs
# no elevation.

[CmdletBinding()]
param(
    # Restrict discovery to one vendor, e.g. 0x2C7C. Empty means the known
    # module vendors (Quectel and Qualcomm).
    [string]$Vendor,
    # Bind one function number instead of the discovered one.
    [int]$Interface = -1,
    # Bind one function named by its hardware id, e.g.
    # USB\VID_2C7C&PID_0125&MI_04. Needed when the module's QMI function is
    # claimed by a vendor driver, so discovery cannot offer it, or when a
    # layout has to be pinned by hand. The id is the one Windows shows for the
    # function, and the vendor driver has to be detached from it first: a
    # function can only have one driver.
    [string]$HardwareId,
    # Report the plan and write the generated INF, but change nothing.
    [switch]$Preview,
    # Append everything this run prints to a file, so a caller that only sees
    # the exit code can show what happened.
    [string]$LogPath,
    [string]$CertificateSubject = 'CN=Celmux QMI Driver'
)

$ErrorActionPreference = 'Stop'

# The vendors a Qualcomm-based module reports as. A module from another vendor
# is bound by naming it: -Vendor 0x1234.
$moduleVendors = @('2C7C', '05C6')

function Test-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal($identity)).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )
}

if (-not $Preview -and -not (Test-Admin)) {
    throw 'Binding a driver package needs an administrator shell; re-run this script from one (or pass -Preview to see the plan).'
}

if ($LogPath) {
    Start-Transcript -Path $LogPath -Force | Out-Null
}

function Get-ModuleCandidates {
    param([string[]]$Vendors)
    $candidates = @()
    foreach ($device in (Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue |
            Where-Object { $_.InstanceId -like 'USB\VID_*&PID_*&MI_*' })) {
        $match = [regex]::Match($device.InstanceId, 'VID_([0-9A-Fa-f]{4})&PID_([0-9A-Fa-f]{4})&MI_([0-9]{2})')
        if (-not $match.Success) { continue }
        $vendor = $match.Groups[1].Value.ToUpperInvariant()
        if ($Vendors.Count -gt 0 -and $Vendors -notcontains $vendor) { continue }
        $candidates += [pscustomobject]@{
            VendorId     = $vendor
            ProductId    = $match.Groups[2].Value.ToUpperInvariant()
            Interface    = [int]$match.Groups[3].Value
            Class        = $device.Class
            FriendlyName = $device.FriendlyName
            InstanceId   = $device.InstanceId
            Status       = $device.Status
        }
    }
    $candidates
}

$hardwareIdPattern = '^USB\\VID_[0-9A-Fa-f]{4}&PID_[0-9A-Fa-f]{4}&MI_[0-9]{2}$'

if ($HardwareId) {
    # One function named by the operator. Discovery is skipped on purpose: this
    # form exists exactly for the functions discovery cannot offer, and it also
    # makes a run reproducible when several modules are attached.
    if ($HardwareId -notmatch $hardwareIdPattern) {
        throw "HardwareId must look like USB\VID_2C7C&PID_0125&MI_04 (got '$HardwareId')."
    }
    $HardwareId = $HardwareId.ToUpperInvariant()
    $parts = [regex]::Match($HardwareId, 'VID_([0-9A-F]{4})&PID_([0-9A-F]{4})&MI_([0-9]{2})')
    $chosen = [pscustomobject]@{
        VendorId     = $parts.Groups[1].Value
        ProductId    = $parts.Groups[2].Value
        Interface    = [int]$parts.Groups[3].Value
        Class        = 'named on the command line'
        FriendlyName = $HardwareId
    }
    $present = Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue |
        Where-Object { $_.InstanceId -like "$HardwareId*" }
    if (-not $present) {
        Write-Warning "No present device matches $HardwareId. The package is still installed, and Windows binds it to the function as soon as it appears."
    }
} else {
    $vendors = if ($Vendor) { @(($Vendor -replace '^0x', '').ToUpperInvariant()) } else { $moduleVendors }
    $interfaces = Get-ModuleCandidates -Vendors $vendors
    if ($interfaces.Count -eq 0) {
        throw "No module function was found for vendor(s) $($vendors -join ', '). Plug the module in and run this again."
    }

    # Windows classifies everything the vendor's own drivers claim. What is left
    # is a vendor-specific function, and the one that answers QMI is the RMNET
    # data function - never the serial ports, the modem or the sound card.
    $claimed = @('Ports', 'Modem', 'MEDIA', 'MEDIA ', 'Net', 'Image', 'SmartCardReader', 'AudioEndpoint')
    $candidates = @($interfaces) | Where-Object { $claimed -notcontains $_.Class }
    if ($candidates.Count -eq 0) {
        $report = ($interfaces | ForEach-Object {
                "  USB\VID_{0}&PID_{1}&MI_{2:d2}  {3}  {4}" -f
                    $_.VendorId, $_.ProductId, $_.Interface, $_.Class, $_.FriendlyName
            }) -join "`n"
        throw ("Every interface of this module is claimed by a driver, so discovery has no function to offer:`n" +
            $report + "`n" +
            "If the QMI/RMNET function is one of them, the vendor driver has to be detached from that one function first " +
            "(Device Manager -> that interface -> Uninstall device), because a function can only have one driver. " +
            "Then run this script again, or pass -HardwareId 'USB\VID_....&PID_....&MI_..' to bind it directly.")
    }

    $serial = $interfaces | Where-Object { $_.Class -eq 'Ports' } | Measure-Object -Property Interface -Maximum
    $chosen = $null
    if ($Interface -ge 0) {
        $chosen = $candidates | Where-Object { $_.Interface -eq $Interface } | Select-Object -First 1
        if (-not $chosen) {
            throw "Interface $Interface is not a vendor-specific function of this module."
        }
    } elseif (@($candidates).Count -eq 1) {
        $chosen = @($candidates)[0]
    } else {
        # More than one vendor function: the RMNET function follows the serial
        # ones in every layout seen so far, so the last one is the best guess -
        # and a wrong guess is reversible with the uninstall script.
        $ranked = $candidates | Sort-Object Interface -Descending
        $chosen = $ranked[0]
        Write-Host "This module exposes $(@($candidates).Count) vendor-specific functions; choosing MI_$('{0:d2}' -f $chosen.Interface)."
        foreach ($candidate in $ranked) {
            Write-Host ("  MI_{0:d2} {1} {2}" -f $candidate.Interface, $candidate.Class, $candidate.FriendlyName)
        }
        Write-Host 'Pass -Interface NN to bind another one.'
    }
    if ($serial.Count -gt 0 -and $chosen.Interface -le $serial.Maximum) {
        Write-Host "Note: the serial functions reach MI_$('{0:d2}' -f $serial.Maximum) and the chosen function does not follow them." -ForegroundColor Yellow
    }
}

$boundHardwareId = 'USB\VID_{0}&PID_{1}&MI_{2:d2}' -f $chosen.VendorId, $chosen.ProductId, $chosen.Interface
Write-Host "Module function: $boundHardwareId ($($chosen.Class))"

$packageDir = $PSScriptRoot
$template = Join-Path $packageDir 'celmux-qmi.inf'
if (-not (Test-Path -LiteralPath $template)) {
    throw "driver template not found next to this script: $template"
}

# The catalog is generated per machine because it is signed by a certificate
# generated per machine, so the repository keeps only the template and the
# tools work in a staging directory.
$stage = Join-Path $env:TEMP ('celmux-qmi-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $stage -Force | Out-Null
$inf = Join-Path $stage 'celmux-qmi.inf'
$text = Get-Content -LiteralPath $template -Raw
if ($text -notmatch 'USB\\VID_[0-9A-Fa-f]{4}&PID_[0-9A-Fa-f]{4}&MI_[0-9]{2}') {
    throw "the driver template carries no hardware id to replace: $template"
}
$text -replace 'USB\\VID_[0-9A-Fa-f]{4}&PID_[0-9A-Fa-f]{4}&MI_[0-9]{2}', $boundHardwareId |
    Set-Content -LiteralPath $inf -Encoding Ascii

# Windows will not replace a package that reports the same version as the one
# already installed, and binding a second module writes a second hardware id
# into a second package. Each run therefore carries its own version, built from
# the date plus the minute so it only ever moves forward.
$now = (Get-Date).ToUniversalTime()
$build = [int](New-TimeSpan -Start ([datetime]'2024-01-01') -End $now).TotalDays % 60000
$driverVersion = '{0:MM/dd/yyyy},1.0.{1}.{2}' -f $now, $build, ($now.Hour * 60 + $now.Minute)
$text = Get-Content -LiteralPath $inf -Raw
$rewritten = $text -replace 'DriverVer\s*=\s*\d{2}/\d{2}/\d{4},[0-9.]+', "DriverVer   = $driverVersion"
if ($rewritten -eq $text) {
    throw "the driver template carries no DriverVer to stamp: $template"
}
$rewritten | Set-Content -LiteralPath $inf -Encoding Ascii
Write-Host "Staged the driver package in $stage"

if ($Preview) {
    Write-Host "Preview: nothing was signed, trusted or installed. The generated INF binds:"
    Select-String -LiteralPath $inf -Pattern $boundHardwareId.Replace('\', '\\') | ForEach-Object { "  $($_.Line.Trim())" }
    if ($LogPath) { Stop-Transcript | Out-Null }
    exit 0
}

Write-Host "Preparing the signing certificate $CertificateSubject ..."
$certificate = Get-ChildItem Cert:\CurrentUser\My |
    Where-Object { $_.Subject -eq $CertificateSubject } |
    Select-Object -First 1
if (-not $certificate) {
    # The key only ever signs this machine's own catalog, so it is created
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
            Write-Warning ("现有的 Celmux 签名证书（{0}）私钥是可导出的，来自旧版本脚本。要让这台机器改用不可导出的证书：先运行 uninstall-qmi-binding.ps1，再重新绑定一次。" -f $certificate.Thumbprint)
        }
    } catch {
        # Not exportable, or not an RSA key: nothing to report.
    }
}

$publicCert = Join-Path $stage 'celmux-qmi.cer'
Export-Certificate -Cert $certificate -FilePath $publicCert -Force | Out-Null
foreach ($store in 'Cert:\LocalMachine\TrustedPublisher', 'Cert:\LocalMachine\Root') {
    $trusted = Get-ChildItem $store | Where-Object { $_.Thumbprint -eq $certificate.Thumbprint }
    if (-not $trusted) {
        Import-Certificate -FilePath $publicCert -CertStoreLocation $store | Out-Null
        Write-Host "  trusted in $store"
    }
}

# The catalog comes from the Windows catalog APIs rather than the SDK's
# makecat/signtool pair, so this runs on a machine with no development tools.
$catalog = Join-Path $stage 'celmux-qmi.cat'
Write-Host 'Generating the catalog ...'
New-FileCatalog -Path $stage -CatalogFilePath $catalog -CatalogVersion 2 | Out-Null
if (-not (Test-Path -LiteralPath $catalog)) {
    throw "the catalog was not produced at $catalog"
}

Write-Host 'Signing the catalog ...'
$signature = Set-AuthenticodeSignature `
    -FilePath $catalog `
    -Certificate $certificate `
    -HashAlgorithm SHA256
if ($signature.Status -ne 'Valid') {
    throw "the catalog signature is not valid: $($signature.Status) $($signature.StatusMessage)"
}
Write-Host "  signed by $($signature.SignerCertificate.Subject)"

Write-Host 'Adding the driver package ...'
& pnputil.exe /add-driver $inf /install 2>&1 | ForEach-Object { Write-Host "  $_" }

Write-Host 'Rescanning devices ...'
& pnputil.exe /scan-devices 2>&1 | ForEach-Object { Write-Host "  $_" }

$device = Get-PnpDevice -PresentOnly | Where-Object { $_.InstanceId -like "USB\VID_$($chosen.VendorId)&PID_$($chosen.ProductId)&MI_$('{0:d2}' -f $chosen.Interface)*" }
if (-not $device) {
    Write-Warning "The bound function ($boundHardwareId) is not present any more; plug the module in and run this again."
    if ($LogPath) { Stop-Transcript | Out-Null }
    exit 0
}
foreach ($entry in $device) {
    $problem = (Get-PnpDeviceProperty -InstanceId $entry.InstanceId -KeyName 'DEVPKEY_Device_ProblemCode').Data
    $bound = (Get-PnpDeviceProperty -InstanceId $entry.InstanceId -KeyName 'DEVPKEY_Device_DriverInfPath').Data
    Write-Host ("{0}: status={1} problem={2} driver={3}" -f $entry.InstanceId, $entry.Status, $problem, $bound)
    if ($problem -ne 0) {
        Write-Warning 'The function is still not usable; check that the package was accepted above.'
    }
}
Write-Host "The QMI function $boundHardwareId is bound to WinUSB; the service can claim it now."
if ($LogPath) { Stop-Transcript | Out-Null }
