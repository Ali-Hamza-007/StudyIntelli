<#
.SYNOPSIS
    StudyIntelli - one-click dev launcher (PowerShell).

.DESCRIPTION
    Automates every manual step from README.md:
      1. Uses the backend virtual environment (creates it + installs packages if missing)
      2. Makes sure PostgreSQL is reachable
      3. Runs makemigrations + migrate
      4. Starts Django on 0.0.0.0:8000 and WAITS until it really answers
      5. Sets up adb reverse tcp:8000 for every connected Android device
      6. Runs flutter run

.EXAMPLE
    .\run_app.ps1                    # full start
    .\run_app.ps1 -SkipMigrations    # faster start when the DB schema is unchanged
    .\run_app.ps1 -NoFlutter         # start/verify only the backend

.NOTES
    This file is intentionally ASCII-only so it parses identically in
    Windows PowerShell 5.1 and PowerShell 7, whatever encoding the editor saves it in.
#>
[CmdletBinding()]
param(
    [switch]$SkipMigrations,
    [switch]$NoFlutter
)

$ErrorActionPreference = 'Continue'

# ----------------------------------------------------------------------------
# Settings
# ----------------------------------------------------------------------------
$Port        = 8000
$Root        = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$BackendDir  = Join-Path $Root 'backend'
$FrontendDir = Join-Path $Root 'frontend'
$HealthUrl   = "http://127.0.0.1:$Port/"
$CrashFlag   = Join-Path $env:TEMP 'studyintelli_django_exit.txt'

# Same packages as README step 3
$RequiredPackages = @(
    'django', 'djangorestframework', 'psycopg2-binary', 'python-dotenv',
    'PyMuPDF', 'groq', 'djangorestframework-simplejwt', 'django-cors-headers'
)
$ImportCheck = "import importlib.util as u, sys; need = ['django','rest_framework','rest_framework_simplejwt','corsheaders','dotenv','groq','psycopg2']; ok = all(u.find_spec(m) for m in need) and (u.find_spec('fitz') or u.find_spec('pymupdf')); sys.exit(0 if ok else 1)"

# ----------------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------------
function Write-Step([string]$Tag, [string]$Message) { Write-Host "`n[$Tag] $Message" -ForegroundColor Cyan }
function Write-Ok([string]$Message)    { Write-Host "  [OK] $Message" -ForegroundColor Green }
function Write-Warn2([string]$Message) { Write-Host "  [!!] $Message" -ForegroundColor Yellow }
function Write-Err([string]$Message)   { Write-Host "  [XX] $Message" -ForegroundColor Red }

# True if something answers HTTP on the URL (any status code, 404 included).
function Test-HttpAlive([string]$Url, [int]$TimeoutMs = 3000) {
    try {
        $req = [System.Net.HttpWebRequest]::Create($Url)
        $req.Timeout = $TimeoutMs
        $req.Proxy   = $null
        $resp = $req.GetResponse()
        $resp.Close()
        return $true
    } catch [System.Net.WebException] {
        if ($_.Exception.Response) { $_.Exception.Response.Close(); return $true }
        return $false
    } catch {
        return $false
    }
}

# True if a TCP connection to host:port succeeds.
function Test-TcpPort([string]$HostName, [int]$PortNumber, [int]$TimeoutMs = 1500) {
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $iar = $client.BeginConnect($HostName, $PortNumber, $null, $null)
        if ($iar.AsyncWaitHandle.WaitOne($TimeoutMs) -and $client.Connected) { return $true }
        return $false
    } catch {
        return $false
    } finally {
        $client.Close()
    }
}

# Reads KEY=value from a .env file.
function Get-DotEnvValue([string]$File, [string]$Key, [string]$Default) {
    if (Test-Path -LiteralPath $File) {
        $line = Get-Content -LiteralPath $File |
                Where-Object { $_ -match "^\s*$Key\s*=" } |
                Select-Object -First 1
        if ($line) {
            $value = ($line -split '=', 2)[1].Trim().Trim('"').Trim("'")
            if ($value) { return $value }
        }
    }
    return $Default
}

# Finds a real Python 3.10+ (ignores the Microsoft Store stub).
function Get-SystemPython {
    $launcher = Get-Command py -ErrorAction SilentlyContinue
    if ($launcher) {
        & $launcher.Source -3 -c "import sys; sys.exit(0 if sys.version_info >= (3,10) else 1)" 2>$null
        if ($LASTEXITCODE -eq 0) { return @{ Exe = $launcher.Source; Prefix = @('-3') } }
    }
    $python = Get-Command python -ErrorAction SilentlyContinue
    if ($python) {
        & $python.Source -c "import sys; sys.exit(0 if sys.version_info >= (3,10) else 1)" 2>$null
        if ($LASTEXITCODE -eq 0) { return @{ Exe = $python.Source; Prefix = @() } }
    }
    return $null
}

# Finds the venv's python.exe (so no Activate.ps1 / execution policy is needed).
function Get-VenvPython {
    foreach ($name in @('venv', '.venv', 'env')) {
        foreach ($base in @($BackendDir, $Root)) {
            $candidate = Join-Path $base "$name\Scripts\python.exe"
            if (Test-Path -LiteralPath $candidate) { return $candidate }
        }
    }
    return $null
}

function Find-Adb {
    $cmd = Get-Command adb -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    foreach ($sdk in @($env:ANDROID_HOME, $env:ANDROID_SDK_ROOT, (Join-Path $env:LOCALAPPDATA 'Android\Sdk'))) {
        if ($sdk) {
            $candidate = Join-Path $sdk 'platform-tools\adb.exe'
            if (Test-Path -LiteralPath $candidate) { return $candidate }
        }
    }
    return $null
}

# ----------------------------------------------------------------------------
# 0. Sanity checks
# ----------------------------------------------------------------------------
Write-Host '=== StudyIntelli dev launcher ===' -ForegroundColor White

if (-not (Test-Path -LiteralPath (Join-Path $BackendDir 'manage.py'))) {
    Write-Err "backend\manage.py not found. Put run_app.ps1 in the folder that contains 'backend' and 'frontend'."
    Write-Err "Looked in: $BackendDir"
    exit 1
}
if (-not (Test-Path -LiteralPath (Join-Path $BackendDir '.env'))) {
    Write-Warn2 'backend\.env is missing - database and GROQ settings will not load (see README step 4).'
}

# ----------------------------------------------------------------------------
# 1. Python virtual environment + packages
# ----------------------------------------------------------------------------
Write-Step '1/6' 'Checking Python virtual environment...'

$VenvPy = Get-VenvPython
if (-not $VenvPy) {
    Write-Warn2 'No virtual environment found - creating backend\venv ...'
    $sys = Get-SystemPython
    if (-not $sys) {
        Write-Err 'Python 3.10+ was not found. Install it from python.org (tick "Add python.exe to PATH") and re-run.'
        exit 1
    }
    $venvArgs = @($sys.Prefix) + @('-m', 'venv', (Join-Path $BackendDir 'venv'))
    & $sys.Exe @venvArgs
    $VenvPy = Get-VenvPython
    if (-not $VenvPy) { Write-Err 'Could not create the virtual environment.'; exit 1 }
}
Write-Ok "Using $VenvPy"

& $VenvPy -c $ImportCheck 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Warn2 'Backend packages are missing in this environment - installing (first run only)...'

    $requirements = Join-Path $BackendDir 'requirements.txt'
    if (Test-Path -LiteralPath $requirements) {
        & $VenvPy -m pip install --disable-pip-version-check -r $requirements
        & $VenvPy -c $ImportCheck 2>$null
    }
    if ($LASTEXITCODE -ne 0) {
        & $VenvPy -m pip install --disable-pip-version-check @RequiredPackages
        & $VenvPy -c $ImportCheck 2>$null
    }
    if ($LASTEXITCODE -ne 0) {
        Write-Err 'Package installation failed. Run the pip command from README step 3 manually and read the error.'
        exit 1
    }
    Write-Ok 'Packages installed'
} else {
    Write-Ok 'All backend packages present'
}

# ----------------------------------------------------------------------------
# 2. PostgreSQL reachable?
# ----------------------------------------------------------------------------
Write-Step '2/6' 'Checking PostgreSQL...'

$EnvFile = Join-Path $BackendDir '.env'
$DbHost  = Get-DotEnvValue $EnvFile 'DB_HOST' '127.0.0.1'
$DbPort  = [int](Get-DotEnvValue $EnvFile 'DB_PORT' '5432')

if (-not (Test-TcpPort $DbHost $DbPort)) {
    Write-Warn2 "Nothing is listening on ${DbHost}:${DbPort} - trying to start the PostgreSQL service..."
    if ($DbHost -in @('127.0.0.1', 'localhost', '::1')) {
        $svc = Get-Service -Name 'postgresql*' -ErrorAction SilentlyContinue |
               Where-Object { $_.Status -ne 'Running' } | Select-Object -First 1
        if ($svc) {
            try {
                Start-Service -InputObject $svc -ErrorAction Stop
                $until = (Get-Date).AddSeconds(20)
                while ((Get-Date) -lt $until -and -not (Test-TcpPort $DbHost $DbPort)) { Start-Sleep -Seconds 1 }
            } catch {
                Write-Warn2 "Could not start service '$($svc.Name)' (open PowerShell as Administrator once, or start it from services.msc)."
            }
        }
    }
}
if (Test-TcpPort $DbHost $DbPort) {
    Write-Ok "PostgreSQL reachable on ${DbHost}:${DbPort}"
} else {
    Write-Err "PostgreSQL is NOT reachable on ${DbHost}:${DbPort}. Start the PostgreSQL service, check DB_HOST/DB_PORT in backend\.env, then re-run."
    exit 1
}

# ----------------------------------------------------------------------------
# 3. Migrations (README step 5)
# ----------------------------------------------------------------------------
Write-Step '3/6' 'Applying database migrations...'

if ($SkipMigrations) {
    Write-Warn2 'Skipped (-SkipMigrations)'
} else {
    Push-Location $BackendDir
    try {
        & $VenvPy manage.py makemigrations --noinput
        $makeCode = $LASTEXITCODE
        & $VenvPy manage.py migrate --noinput
        $migrateCode = $LASTEXITCODE
    } finally {
        Pop-Location
    }
    if ($makeCode -ne 0 -or $migrateCode -ne 0) {
        Write-Err 'Migrations failed (read the error above - usually wrong DB_NAME / DB_USER / DB_PASSWORD in backend\.env, or the database does not exist).'
        exit 1
    }
    Write-Ok 'Database is up to date'
}

# ----------------------------------------------------------------------------
# 4. Django backend (start + wait until it really answers)
# ----------------------------------------------------------------------------
Write-Step '4/6' "Starting Django backend on port $Port..."

$backendReady = $false

# Is something already bound to the port?
$listener = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
if ($listener) {
    $owner = Get-Process -Id $listener.OwningProcess -ErrorAction SilentlyContinue
    $ownerName = if ($owner) { $owner.ProcessName } else { 'unknown' }

    if ((Test-HttpAlive $HealthUrl) -and $ownerName -like 'python*') {
        Write-Ok "Django is already running and answering (PID $($listener.OwningProcess))"
        $backendReady = $true
    } else {
        Write-Warn2 "Port $Port is held by '$ownerName' (PID $($listener.OwningProcess)) but it is not a healthy Django server."
        $answer = 'y'
        if ($ownerName -notlike 'python*') {
            $answer = Read-Host "  Stop '$ownerName' so Django can use port $Port? [y/N]"
        }
        if ($answer -match '^(y|yes)$') {
            & taskkill.exe /PID $listener.OwningProcess /T /F 2>&1 | Out-Null
            Start-Sleep -Seconds 2
        } else {
            Write-Err "Port $Port is busy. Free it and re-run."
            exit 1
        }
    }
}

if (-not $backendReady) {
    Remove-Item -LiteralPath $CrashFlag -Force -ErrorAction SilentlyContinue

    # Child window command. Uses the venv python directly: no activation, no execution-policy problems.
    $pyEsc   = $VenvPy.Replace("'", "''")
    $dirEsc  = $BackendDir.Replace("'", "''")
    $flagEsc = $CrashFlag.Replace("'", "''")
    $childCommand = @"
`$Host.UI.RawUI.WindowTitle = 'StudyIntelli - Django backend'
`$env:PYTHONUNBUFFERED = '1'
Set-Location -LiteralPath '$dirEsc'
& '$pyEsc' manage.py runserver 0.0.0.0:$Port
`$code = `$LASTEXITCODE
Set-Content -LiteralPath '$flagEsc' -Value `$code
Write-Host ''
Write-Host "Django stopped (exit code `$code)." -ForegroundColor Red
"@
    $encoded = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($childCommand))

    Start-Process -FilePath 'powershell.exe' `
        -ArgumentList @('-NoExit', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $encoded) `
        -WorkingDirectory $BackendDir | Out-Null

    Write-Host '  Waiting for Django to answer' -NoNewline
    $deadline = (Get-Date).AddSeconds(60)
    while ((Get-Date) -lt $deadline) {
        if (Test-Path -LiteralPath $CrashFlag) { break }      # Django exited
        if (Test-HttpAlive $HealthUrl) { $backendReady = $true; break }
        Write-Host '.' -NoNewline
        Start-Sleep -Seconds 1
    }
    Write-Host ''

    if ($backendReady) {
        Write-Ok "Django is up at http://127.0.0.1:$Port"
    } elseif (Test-Path -LiteralPath $CrashFlag) {
        Write-Err 'Django crashed on startup. Read the error in the "StudyIntelli - Django backend" window.'
    } else {
        Write-Err 'Django did not answer within 60 seconds. Check the "StudyIntelli - Django backend" window.'
    }
}

if (-not $backendReady) {
    $go = Read-Host '  Backend is NOT running. Launch Flutter anyway? [y/N]'
    if ($go -notmatch '^(y|yes)$') { exit 1 }
}

if ($NoFlutter) {
    Write-Host "`nBackend check finished (-NoFlutter given, not starting the app)." -ForegroundColor Green
    exit 0
}

# ----------------------------------------------------------------------------
# 5. ADB reverse port forwarding (right before Flutter, so it is fresh)
# ----------------------------------------------------------------------------
Write-Step '5/6' 'Setting up ADB reverse port forwarding...'

$Adb = Find-Adb
if (-not $Adb) {
    Write-Warn2 'adb.exe not found (PATH, ANDROID_HOME, ANDROID_SDK_ROOT, %LOCALAPPDATA%\Android\Sdk). Skipping.'
} else {
    & $Adb start-server 2>&1 | Out-Null
    $devices = @(
        & $Adb devices 2>$null | ForEach-Object {
            if ($_ -match '^(\S+)\s+(\S+)\s*$') { [pscustomobject]@{ Serial = $Matches[1]; State = $Matches[2] } }
        }
    )
    $ready = @($devices | Where-Object { $_.State -eq 'device' })

    foreach ($d in ($devices | Where-Object { $_.State -ne 'device' })) {
        Write-Warn2 "Device $($d.Serial) is '$($d.State)' (unlock the phone and accept the USB debugging prompt)."
    }

    if ($ready.Count -eq 0) {
        Write-Warn2 'No ready Android device. (An emulator can use http://10.0.2.2:8000 instead of adb reverse.)'
    } else {
        foreach ($d in $ready) {
            & $Adb -s $d.Serial reverse "tcp:$Port" "tcp:$Port" 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-Ok "$($d.Serial): adb reverse tcp:$Port -> tcp:$Port"
            } else {
                Write-Warn2 "$($d.Serial): adb reverse failed"
            }
        }
    }
}

# ----------------------------------------------------------------------------
# 6. Flutter
# ----------------------------------------------------------------------------
Write-Step '6/6' 'Launching Flutter app...'

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    Write-Err 'flutter was not found on PATH. Add <flutter-sdk>\bin to PATH and re-run.'
    exit 1
}
if (-not (Test-Path -LiteralPath $FrontendDir)) {
    Write-Err "Frontend folder not found: $FrontendDir"
    exit 1
}

Push-Location $FrontendDir
try {
    flutter run
} finally {
    Pop-Location
}

Write-Host "`nFlutter has exited. The Django window is still running - close it (or press Ctrl+C there) to stop the backend." -ForegroundColor DarkGray
