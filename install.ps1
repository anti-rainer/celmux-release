# Celmux Windows service installer.
#
# Run this inside the folder that should hold the service. That folder becomes
# the run root: the service reads and writes `config`, `data` and `logs`
# relative to it, and the control scripts start it from there.
#
#   curl.exe -fsSL -o install.ps1 https://raw.githubusercontent.com/anti-rainer/celmux/beta/packaging/desktop/windows/install.ps1
#   powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1
#
# Parameters:
#   -Url <uri>    Where to download the service from. Defaults to the Windows
#                 asset of the newest release.
#   -From <path>  Install an executable that is already on this machine.
#   -RepoBase <uri>
#                 Where the root scripts and the driver package are fetched
#                 from. Defaults to the public release repository.
#   -Force        Replace an existing bin\celmux.exe.
#
# Nothing here registers a system service or an auto-start entry: the three
# control scripts are the whole interface, and scheduling is the operator's.

[CmdletBinding()]
param(
    [string]$Url = 'https://github.com/anti-rainer/celmux-release/releases/latest/download/celmux_windows_amd64.exe',
    [string]$From,
    [string]$RepoBase = 'https://raw.githubusercontent.com/anti-rainer/celmux-release/main',
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

# Windows PowerShell 5.1 still negotiates TLS 1.0 by default, which GitHub
# refuses; PowerShell 7 already does the right thing and ignores this.
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
} catch {
    # No such knob on this host; the download below will report its own error.
}

function Get-RemoteFile($uri, $target) {
    # The same accelerator the Linux installer uses: a direct GitHub fetch is
    # slow or unreachable from some networks, and the proxy only ever sees the
    # public release repository.
    $proxy = if ($env:CELMUX_GITHUB_ACCELERATOR -ne $null) { $env:CELMUX_GITHUB_ACCELERATOR } else { 'https://v6.gh-proxy.org' }
    try {
        Invoke-WebRequest -Uri $uri -OutFile $target -UseBasicParsing
        return
    } catch {
        $first = $_
    }
    if ($proxy) {
        try {
            Invoke-WebRequest -Uri ("{0}/{1}" -f $proxy.TrimEnd('/'), $uri) -OutFile $target -UseBasicParsing
            return
        } catch {
            throw "download failed (direct: $($first.Exception.Message); accelerated: $($_.Exception.Message))"
        }
    }
    throw $first
}

function Write-Step($message) {
    Write-Host "==> $message"
}

function New-Directory($path) {
    if (-not (Test-Path -LiteralPath $path)) {
        New-Item -ItemType Directory -Path $path | Out-Null
    }
}

function Write-Ascii($path, $lines) {
    # Control scripts are read by cmd.exe, which is happiest with plain ASCII
    # and CRLF, whatever this shell's defaults are.
    $text = ($lines -join "`r`n") + "`r`n"
    [System.IO.File]::WriteAllText($path, $text, [System.Text.Encoding]::ASCII)
}

function Set-Crlf($path) {
    # A file that came from a repository is stored with the line endings that
    # repository keeps, which for our sources is LF. cmd.exe reads a control
    # script line by line and wants CRLF, so the fetched one is rewritten.
    $text = [System.IO.File]::ReadAllText($path)
    $text = ($text -replace "`r`n", "`n") -replace "`n", "`r`n"
    [System.IO.File]::WriteAllText($path, $text, [System.Text.Encoding]::ASCII)
}

$root = (Get-Location).Path
$binary = Join-Path $root 'bin\celmux.exe'

Write-Step "Install folder: $root"
foreach ($folder in 'bin', 'config', 'data', 'logs', 'driver') {
    New-Directory (Join-Path $root $folder)
}
Write-Step 'Created bin, config, data, logs and driver'

if ((Test-Path -LiteralPath $binary) -and -not $Force) {
    Write-Step "Keeping the installed $binary (pass -Force to replace it)"
} elseif ($From) {
    if (-not (Test-Path -LiteralPath $From)) {
        throw "No such file: $From"
    }
    Copy-Item -LiteralPath $From -Destination $binary -Force
    Write-Step "Installed $binary from $From"
} else {
    Write-Step "Downloading $Url"
    try {
        Get-RemoteFile $Url $binary
    } catch {
        throw "Download failed: $($_.Exception.Message)`nPass -From <path> to install a local executable instead."
    }
    Write-Step "Installed $binary"
}

# A release page that answered with HTML, or a failed partial write, must not
# look like an installed service. Every Windows executable starts with MZ.
$stream = [System.IO.File]::OpenRead($binary)
try {
    $header = New-Object byte[] 2
    $read = $stream.Read($header, 0, 2)
} finally {
    $stream.Close()
}
if ($read -ne 2 -or $header[0] -ne 0x4D -or $header[1] -ne 0x5A) {
    throw "$binary is not a Windows executable; nothing was installed"
}
$size = [Math]::Round((Get-Item -LiteralPath $binary).Length / 1MB, 1)
Write-Step "Executable looks valid ($size MB)"

$startLines = @(
    '@echo off',
    'rem Start the Celmux service from this folder.',
    'setlocal',
    'cd /d "%~dp0"',
    'if not exist "bin\celmux.exe" (',
    '  echo bin\celmux.exe is missing: run install.ps1 first.',
    '  exit /b 1',
    ')',
    'if not exist "logs" mkdir "logs"',
    'set "CELMUX_ROOT=%~dp0"',
    'rem Start it detached: this works from a double click and from a scheduled',
    'rem task, neither of which has a console for "start /min" to attach to.',
    'rem The process list is the .NET one, which never reports an instance that',
    'rem already exited, and it is matched by path so another install is ignored.',
    'rem A restart calls this right after a stop, so an instance still tearing',
    'rem down is waited out instead of being mistaken for a live one.',
    'powershell -NoProfile -ExecutionPolicy Bypass -Command "$root = $env:CELMUX_ROOT; $exe = Join-Path $root ''bin\celmux.exe''; $mine = { Get-Process -Name celmux -ErrorAction SilentlyContinue | Where-Object { $_.Path -ieq $exe } }; $running = & $mine; if ($running) { $running | Wait-Process -Timeout 5 -ErrorAction SilentlyContinue; $running = & $mine; if ($running) { Write-Host (''celmux is already running, pid '' + $running[0].Id); exit 0 } }; $p = Start-Process -FilePath $exe -WorkingDirectory $root -WindowStyle Hidden -PassThru; Write-Host (''celmux started, pid '' + $p.Id); Write-Host ''Web interface: https://127.0.0.1:7575''"'
)
Write-Ascii (Join-Path $root 'start.bat') $startLines

$stopLines = @(
    '@echo off',
    'rem Stop the Celmux service that this folder started.',
    'setlocal',
    'set "CELMUX_EXE=%~dp0bin\celmux.exe"',
    'rem Match on the executable path, so an install in another folder is left alone.',
    'powershell -NoProfile -ExecutionPolicy Bypass -Command "$t = $env:CELMUX_EXE; $p = Get-Process -Name celmux -ErrorAction SilentlyContinue | Where-Object { $_.Path -ieq $t }; if (-not $p) { Write-Host ''celmux is not running from this folder''; exit 0 }; $p | ForEach-Object { Stop-Process -Id $_.Id -Force; Write-Host (''stopped celmux pid '' + $_.Id) }"'
)
Write-Ascii (Join-Path $root 'stop.bat') $stopLines

$restartLines = @(
    '@echo off',
    'rem Restart the Celmux service of this folder.',
    'setlocal',
    'set "CELMUX_EXE=%~dp0bin\celmux.exe"',
    'call "%~dp0stop.bat"',
    'rem A stopped instance can stay in the process list for a few seconds while',
    'rem Windows tears down its USB handles, so the wait is on the process and',
    'rem not on the clock.',
    'powershell -NoProfile -ExecutionPolicy Bypass -Command "$t = $env:CELMUX_EXE; for ($i = 0; $i -lt 40; $i++) { $p = Get-Process -Name celmux -ErrorAction SilentlyContinue | Where-Object { $_.Path -ieq $t }; if (-not $p) { exit 0 }; Start-Sleep -Milliseconds 500 }; Write-Host ''the previous instance did not exit; not starting a second one''; exit 1"',
    'if errorlevel 1 exit /b 1',
    'call "%~dp0start.bat"'
)
Write-Ascii (Join-Path $root 'restart.bat') $restartLines

Write-Step 'Wrote start.bat, stop.bat and restart.bat'

# The QMI binding lives with the service, because binding a module's QMI
# function to WinUSB needs one elevated run and the operator should not have to
# find the script in a repository. The package is the INF template plus the two
# scripts that install and remove the binding; `install-driver.bat` in the root
# starts an elevated run of the installer. The service offers the same step as
# `celmux --install-qmi-binding`, which looks for the script here.
$driverDir = Join-Path $root 'driver'
foreach ($file in 'install-qmi-binding.ps1', 'uninstall-qmi-binding.ps1', 'celmux-qmi.inf') {
    $target = Join-Path $driverDir $file
    if ((Test-Path -LiteralPath $target) -and -not $Force) {
        continue
    }
    try {
        Get-RemoteFile "$RepoBase/$file" $target
    } catch {
        Write-Warning "could not fetch $file from ${RepoBase} - $($_.Exception.Message)"
        continue
    }
}

$driverBat = Join-Path $root 'install-driver.bat'
if ((-not (Test-Path -LiteralPath $driverBat)) -or $Force) {
    try {
        Get-RemoteFile "$RepoBase/install-driver.bat" $driverBat
        Set-Crlf $driverBat
    } catch {
        Write-Warning "could not fetch install-driver.bat from ${RepoBase} - $($_.Exception.Message)"
    }
}
Write-Step "Driver package in $driverDir (bind a module with install-driver.bat)"

Write-Host ''
Write-Host 'Next:'
Write-Host '  start.bat      start the service (the interface is https://127.0.0.1:7575)'
Write-Host '  stop.bat       stop the service started from this folder'
Write-Host '  restart.bat    stop, wait, start again'
Write-Host ''
Write-Host 'A module whose QMI function is not bound to WinUSB yet needs one'
Write-Host 'elevated run:  double-click install-driver.bat, which asks for it'
Write-Host 'The service reports the same step as:  celmux --install-qmi-binding'
Write-Host ''
Write-Host 'The first start creates config\celmux.yaml with a generated web password.'
Write-Host 'Open the interface with the password from that file, or change it there.'
