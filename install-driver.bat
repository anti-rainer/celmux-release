@echo off
rem Copyright (c) 2026 anti-rainer
rem SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
rem
rem Bind a module's QMI function to the WinUSB driver Windows already ships, so
rem the service reaches the module the way Linux reaches /dev/cdc-wdm*.
rem
rem The driver package sits in `driver\` next to this file: the INF template and
rem `install-qmi-binding.ps1`, which finds the module's QMI function and signs
rem its own catalog with a certificate generated on this machine. One folder is
rem therefore enough - nothing has to be downloaded, and no Windows SDK tool is
rem needed.
rem
rem Binding a driver package needs an administrator, so this asks for the one
rem elevation prompt Windows requires and continues in that window. The same
rem step is `celmux --install-qmi-binding`, and `driver\uninstall-qmi-binding.ps1`
rem undoes it.

setlocal
cd /d "%~dp0"

set "CELMUX_BINDING=%~dp0driver\install-qmi-binding.ps1"
if not exist "%CELMUX_BINDING%" (
    echo driver\install-qmi-binding.ps1 is missing from this folder.
    echo Run install.ps1 here again to fetch the driver package.
    pause
    exit /b 1
)

rem Continue in an elevated window unless this one already is one. The check is
rem the same one the binding script makes, so declining the prompt is reported
rem by that script rather than twice.
rem The arguments are carried over, so install-driver.bat -Preview previews in
rem the elevated window instead of installing for real.
set "CELMUX_ELEVATE="
if not "%~1"=="" set "CELMUX_ELEVATE=-ArgumentList '%*'"

powershell -NoProfile -ExecutionPolicy Bypass -Command "if (([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { exit 0 } else { exit 1 }"
if errorlevel 1 (
    echo Binding a module's QMI function to WinUSB needs administrator rights.
    echo Windows asks for them now; accept the prompt to continue.
    powershell -NoProfile -ExecutionPolicy Bypass -Command "try { Start-Process -Verb RunAs -FilePath '%~f0' %CELMUX_ELEVATE% -ErrorAction Stop } catch { Write-Host 'Elevation was declined; nothing was installed.' }"
    exit /b
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%CELMUX_BINDING%" %*
set "CELMUX_RESULT=%errorlevel%"
if not "%CELMUX_RESULT%"=="0" (
    echo.
    echo The binding did not finish; the lines above say why.
) else (
    echo.
    echo The QMI function is bound to WinUSB. Start the service with start.bat.
)
pause
exit /b %CELMUX_RESULT%
