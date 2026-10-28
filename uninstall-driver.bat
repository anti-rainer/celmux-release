@echo off
rem Copyright (c) 2026 anti-rainer
rem SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
rem
rem Removes the per-machine QMI driver package and the self-signed certificate
rem this installation added to LocalMachine\TrustedPublisher and
rem LocalMachine\Root. Removing a machine-wide trust anchor needs an
rem administrator, so this asks for the one elevation prompt Windows requires
rem and waits for the elevated script before returning.
rem
rem Run from the driver folder; the NSIS uninstaller and uninstall.ps1 call it
rem before deleting files.

setlocal
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
set "SCRIPT=%~dp0uninstall-module-driver.ps1"
if not exist "%SCRIPT%" (
    echo uninstall-module-driver.ps1 is missing from this folder.
    exit /b 1
)

"%PS%" -NoProfile -ExecutionPolicy Bypass -Command ^
  "try { $args = @('-NoProfile','-ExecutionPolicy','Bypass','-File','%SCRIPT%'); $p = Start-Process -FilePath '%PS%' -Verb RunAs -WindowStyle Hidden -ArgumentList $args -Wait -PassThru; exit $p.ExitCode } catch { Write-Host 'Elevation was declined; the driver trust certificate was not removed.'; exit 1 }"
exit /b %errorlevel%
