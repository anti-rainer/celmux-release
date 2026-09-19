# Copyright (c) 2026 anti-rainer
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
#
# Removes the WinUSB binding installed by install-qmi-binding.ps1 and returns
# the module's QMI function to the vendor's own driver arrangement.

#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [string]$InstanceFilter = 'USB\VID_2C7C*&MI_04*',
    [string]$PublishedName,
    [string]$CertificateSubject = 'CN=Celmux QMI Driver'
)

$ErrorActionPreference = 'Stop'

if (-not $PublishedName) {
    $PublishedName = (Get-WindowsDriver -Online |
        Where-Object { $_.OriginalFileName -like '*celmux-qmi.inf' } |
        Select-Object -First 1 -ExpandProperty Driver).Trim()
}
if (-not $PublishedName) {
    Write-Warning 'The Celmux QMI driver package is not installed.'
    exit 0
}

foreach ($device in (Get-PnpDevice -PresentOnly | Where-Object { $_.InstanceId -like $InstanceFilter })) {
    Write-Host "Removing the device node of $($device.InstanceId) ..."
    & pnputil.exe /remove-device $device.InstanceId | ForEach-Object { Write-Host "  $_" }
}

Write-Host "Deleting driver package $PublishedName ..."
& pnputil.exe /delete-driver $PublishedName /uninstall | ForEach-Object { Write-Host "  $_" }

& pnputil.exe /scan-devices | ForEach-Object { Write-Host "  $_" }

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

Write-Host 'Done: Windows will bind the module again with whatever driver it used before.'
