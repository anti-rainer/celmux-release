@echo off
rem Copyright (c) 2026 anti-rainer
rem SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
rem
rem Binds the module's QMI (RMNET) function to the WinUSB driver Windows already
rem ships, so the service can reach it. One script, one elevation prompt.
rem
rem The module's serial functions are left to the vendor's driver package
rem (Quectel), which publishes them as COM ports. Binding them here made every
rem install wait out a two-minute PnP timeout on the modem function.
rem
rem The driver package sits in `driver\` next to this file: the INF template
rem and `install-module-driver.ps1`, which finds the module's function and
rem signs its own catalog with a certificate generated on this machine. One
rem folder is therefore enough - nothing has to be downloaded, and no Windows
rem SDK tool is needed.
rem
rem Binding a driver package needs an administrator, so this asks for the one
rem elevation prompt Windows requires and continues in that window. The same
rem step is `celmux --install-module-driver`, and
rem `driver\uninstall-module-driver.ps1` undoes it.

setlocal
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
cd /d "%~dp0"

set "CELMUX_BINDING=%~dp0driver\install-module-driver.ps1"
if not exist "%CELMUX_BINDING%" (
    echo driver\install-module-driver.ps1 is missing from this folder.
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

"%PS%" -NoProfile -ExecutionPolicy Bypass -Command "if (([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { exit 0 } else { exit 1 }"
if errorlevel 1 (
    echo Binding the module's USB functions needs administrator rights.
    echo Windows asks for them now; accept the prompt to continue.
    "%PS%" -NoProfile -ExecutionPolicy Bypass -Command "try { Start-Process -Verb RunAs -FilePath '%~f0' %CELMUX_ELEVATE% -ErrorAction Stop } catch { Write-Host 'Elevation was declined; nothing was installed.' }"
    exit /b
)

"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%CELMUX_BINDING%" %*
set "CELMUX_RESULT=%errorlevel%"
if not "%CELMUX_RESULT%"=="0" (
    echo.
    echo The binding did not finish; the lines above say why.
) else (
    echo.
    echo The module's QMI function is bound to WinUSB. Start the service with
    echo start.bat. Install the vendor's driver package if you also want the
    echo module's AT and diagnostic COM ports.
)
pause
exit /b %CELMUX_RESULT%
