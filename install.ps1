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
#
# The downloaded executable is verified against the digest GitHub records for
# that release asset, fetched from the API rather than from the download
# channel, before anything is installed. A missing or mismatched digest aborts
# and deletes the file; pass -Sha256 for a custom mirror. -From files are
# trusted because they were already on this machine.

[CmdletBinding()]
param(
    [string]$Url = 'https://github.com/anti-rainer/celmux-release/releases/latest/download/celmux_win_amd64.exe',
    [string]$From,
    [string]$RepoBase = '',
    [string]$Sha256,
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
    # Direct only. A third-party accelerator sits on the same trust path as
    # the bytes it serves, so it cannot be used for anything this installer
    # executes or trusts.
    Invoke-WebRequest -Uri $uri -OutFile $target -UseBasicParsing
}

function Write-Step($message) {
    Write-Host "==> $message"
}

function Get-ReleaseHash($uri) {
    # The digest is read from GitHub's API, a different endpoint from the
    # asset download. A mirror or proxy that rewrites the binary cannot
    # rewrite the digest it is checked against.
    $name = ($uri -split '/')[-1]
    if (-not $name) {
        return $null
    }
    $tag = $null
    if ($uri -match '/releases/latest/download/') {
        $tag = 'latest'
    } elseif ($uri -match '/releases/download/([^/]+)/') {
        $tag = $Matches[1]
    }
    if (-not $tag) {
        return $null
    }
    try {
        $release = Invoke-RestMethod -UseBasicParsing `
            -Uri ("https://api.github.com/repos/anti-rainer/celmux-release/releases/{0}" -f $tag) `
            -Headers @{ 'User-Agent' = 'celmux-installer'; 'Accept' = 'application/vnd.github+json' }
        foreach ($asset in $release.assets) {
            if ($asset.name -eq $name -and $asset.digest) {
                return ($asset.digest -replace '^sha256:', '').ToLowerInvariant()
            }
        }
    } catch {
        return $null
    }
    return $null
}

function Get-ReleaseTag {
    try {
        return (Invoke-RestMethod -UseBasicParsing `
            -Uri 'https://api.github.com/repos/anti-rainer/celmux-release/releases/latest' `
            -Headers @{ 'User-Agent' = 'celmux-installer'; 'Accept' = 'application/vnd.github+json' }).tag_name
    } catch {
        return $null
    }
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
$configFile = Join-Path $root 'config\celmux.yaml'
$configWasPresent = Test-Path -LiteralPath $configFile

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

# The executable is checked against the release's own checksum before it is
# ever run. A mismatch is fatal: the file that arrived is not the file the
# release published, and no later step can make that safe. A release that
# carries no checksum at all (an older one, or a mirror that only mirrors the
# asset) is a warning, because refusing to install would leave the operator
# with no way forward; -From files are never checked, they are already local.
if (-not $From) {
    $name = ($Url -split '/')[-1]
    Write-Step "Verifying the SHA-256 of $name"
    $expected = if ($Sha256) { $Sha256.ToLowerInvariant() } else { Get-ReleaseHash $Url }
    if (-not $expected) {
        Remove-Item -LiteralPath $binary -Force -ErrorAction SilentlyContinue
        throw "无法从 GitHub API 取得 $name 的 SHA-256；拒绝安装未校验的可执行文件（自定义镜像请传 -Sha256）。"
    }
    $actual = (Get-FileHash -LiteralPath $binary -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $expected) {
        Remove-Item -LiteralPath $binary -Force -ErrorAction SilentlyContinue
        throw "校验失败：$name 的 SHA-256 是 $actual，发布的是 $expected。文件已删除，未安装任何东西。"
    }
    Write-Step "SHA-256 verified ($actual)"
}

# Driver scripts are fetched from the release tag, not from a moving branch.
# The tag is resolved from the same API response; an explicit -RepoBase still
# wins for a mirrored deployment.
if (-not $RepoBase) {
    $releaseTag = Get-ReleaseTag
    if ($releaseTag) {
        $RepoBase = "https://raw.githubusercontent.com/anti-rainer/celmux-release/$releaseTag"
    } else {
        throw '无法确定发布版本 tag；拒绝从可变分支下载驱动脚本（可用 -RepoBase 指定）。'
    }
}

if (-not $configWasPresent) {
    # Also seed older release binaries with the same admin/admin credentials.
    # The single-quoted YAML literal keeps bcrypt's dollar signs intact.
    Write-Ascii $configFile @(
        'server:',
        '  port: 0.0.0.0:7575',
        'web:',
        '  username: admin',
        '  password: ''$2b$12$yD2JAmRjpSiPRjdLAEdpMuRvrvfmTqDcOcyToUAJjgLWcwMGAoz4q''',
        'devices: []'
    )
}

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
    '"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -Command "$root = $env:CELMUX_ROOT; $exe = Join-Path $root ''bin\celmux.exe''; $mine = { Get-Process -Name celmux -ErrorAction SilentlyContinue | Where-Object { $_.Path -ieq $exe } }; $running = & $mine; if ($running) { $running | Wait-Process -Timeout 5 -ErrorAction SilentlyContinue; $running = & $mine; if ($running) { Write-Host (''celmux is already running, pid '' + $running[0].Id); exit 0 } }; $p = Start-Process -FilePath $exe -WorkingDirectory $root -WindowStyle Hidden -PassThru; Write-Host (''celmux started, pid '' + $p.Id); Write-Host ''Web interface: https://127.0.0.1:7575''"'
)
Write-Ascii (Join-Path $root 'start.bat') $startLines

$stopLines = @(
    '@echo off',
    'rem Stop the Celmux service that this folder started.',
    'setlocal',
    'set "CELMUX_EXE=%~dp0bin\celmux.exe"',
    'rem Match on the executable path, so an install in another folder is left alone.',
    '"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -Command "$t = $env:CELMUX_EXE; $p = Get-Process -Name celmux -ErrorAction SilentlyContinue | Where-Object { $_.Path -ieq $t }; if (-not $p) { Write-Host ''celmux is not running from this folder''; exit 0 }; $p | ForEach-Object { Stop-Process -Id $_.Id -Force; Write-Host (''stopped celmux pid '' + $_.Id) }"'
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
    '"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -Command "$t = $env:CELMUX_EXE; for ($i = 0; $i -lt 40; $i++) { $p = Get-Process -Name celmux -ErrorAction SilentlyContinue | Where-Object { $_.Path -ieq $t }; if (-not $p) { exit 0 }; Start-Sleep -Milliseconds 500 }; Write-Host ''the previous instance did not exit; not starting a second one''; exit 1"',
    'if errorlevel 1 exit /b 1',
    'call "%~dp0start.bat"'
)
Write-Ascii (Join-Path $root 'restart.bat') $restartLines

Write-Step 'Wrote start.bat, stop.bat and restart.bat'

# The module driver lives with the service, because binding a module's USB
# functions needs one elevated run and the operator should not have to find
# the script in a repository. The package is the two INF templates plus the two
# scripts that install and remove the binding; `install-driver.bat` in the root
# starts an elevated run of the installer. The service offers the same step as
# `celmux --install-module-driver`, which looks for the script here.
$driverDir = Join-Path $root 'driver'
foreach ($file in 'install-module-driver.ps1', 'uninstall-module-driver.ps1', 'uninstall-driver.bat', 'celmux-module.inf') {
    $target = Join-Path $driverDir $file
    # Fetched every run, not only when missing: the binding scripts and the
    # service binary speak about the same hardware, and a stale copy in the
    # install directory would bind a function this build cannot use.
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
if ($configWasPresent) {
    Write-Host 'Existing config\celmux.yaml and login credentials were kept.'
} else {
    Write-Host 'Initial login: admin/admin. config\celmux.yaml stores the bcrypt hash.'
}
