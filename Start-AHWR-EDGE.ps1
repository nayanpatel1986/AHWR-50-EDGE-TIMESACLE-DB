$ErrorActionPreference = 'Stop'
# AHWR-150 EDGE launcher — TimescaleDB edition.
#
# PostgreSQL + TimescaleDB runs in one of two modes (PG_MODE in settings.env):
#   bundled  runtime\pgsql is initialised in data\pgdata and started/stopped by
#            these scripts (portable folder, the default when runtime\pgsql exists)
#   service  an installed PostgreSQL 18 Windows service with TimescaleDB, as in
#            the Edge Installation Guide; this script only connects to it
#
# After Install-AHWR-EDGE-Services.ps1 everything runs as Windows services that
# start at boot and restart on failure; this script then only applies schema
# upgrades, starts any stopped service and opens the dashboard.
$Root = $PSScriptRoot
$RunDir = Join-Path $Root 'run'
$DataDir = Join-Path $Root 'data'
$LogDir = Join-Path $Root 'logs'
$SettingsFile = Join-Path $Root 'settings.env'
$Node = Join-Path $Root 'runtime\node\node.exe'
$Python = Join-Path $Root 'runtime\python\python.exe'
$Telegraf = Join-Path $Root 'runtime\telegraf\telegraf.exe'
$PgBin = Join-Path $Root 'runtime\pgsql\bin'
$Backend = Join-Path $Root 'app\backend\server.js'
$Collector = Join-Path $Root 'app\collector.py'
$SqlDir = Join-Path $Root 'app\sql'
$PgData = Join-Path $DataDir 'pgdata'
$ServiceMode = ($env:AHWR_PORTABLE -ne '1') -and [bool](Get-Service 'AHWR-Backend' -ErrorAction SilentlyContinue)
$RigIdPattern = '^[A-Za-z0-9_.\-]{1,64}$'

# A desktop shortcut starts unelevated. Ask for UAC only when stopped Windows
# services actually need to be started; a running dashboard opens normally.
if ($ServiceMode) {
    $serviceNames = @('AHWR-PostgreSQL', 'AHWR-Telegraf', 'AHWR-Backend', 'AHWR-BOP-Collector')
    $stopped = @($serviceNames | ForEach-Object { Get-Service $_ -ErrorAction SilentlyContinue } | Where-Object { $_.Status -ne 'Running' })
    if ($stopped.Count) {
        $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
        if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            Write-Host 'Administrator approval is needed to start AHWR-EDGE services.' -ForegroundColor Cyan
            $arguments = @('-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $PSCommandPath))
            try {
                $elevated = Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -Verb RunAs -Wait -PassThru
                exit $elevated.ExitCode
            } catch {
                throw "Administrator approval was cancelled or failed: $($_.Exception.Message)"
            }
        }
    }
}

foreach ($path in @($Node, $Python, $Telegraf, $Backend, $Collector, (Join-Path $SqlDir '01-roles.sql'), (Join-Path $SqlDir '02-schema.sql'))) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Missing runtime/application file: $path`nInstall the matching runtime folder before starting." }
}
foreach ($dir in @($RunDir, $DataDir, $LogDir, (Join-Path $DataDir 'app'))) {
    $null = New-Item -ItemType Directory -Force -Path $dir
}

function New-Secret {
    # RandomNumberGenerator::Fill does not exist in Windows PowerShell 5.1 (.NET Framework).
    $bytes = New-Object byte[] 32
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
    -join ($bytes | ForEach-Object { $_.ToString('x2') })
}

function Read-SecretText([string]$Prompt) {
    $secure = Read-Host $Prompt -AsSecureString
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try { [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
}

function Read-RigId {
    while ($true) {
        $value = Read-Host 'Rig device id (DEVICE_ID, exactly as registered at the CMF)'
        if ($value -match $RigIdPattern) { return $value }
        Write-Host 'Use 1-64 letters, digits, dot, underscore or hyphen.' -ForegroundColor Yellow
    }
}

function Get-SettingKeys {
    if (-not (Test-Path -LiteralPath $SettingsFile)) { return @() }
    Get-Content -LiteralPath $SettingsFile | ForEach-Object {
        $line = $_.TrimStart([char]0xFEFF)
        if ($line -match '^\s*([^#=]+)=') { $matches[1].Trim() }
    }
}

# --- First run, or upgrade of an InfluxDB-edition settings.env -----------------
if (-not (Test-Path -LiteralPath $SettingsFile)) {
    if ($env:AHWR_SIMPLE_START -eq '1') {
        Write-Host 'First-time local setup: admin / Admin@123. Change the password after sign-in.' -ForegroundColor Cyan
        $admin = 'admin'
        $adminPassword = 'Admin@123'
        $opcUrl = 'opc.tcp://localhost:49320'
        $opcUser = ''
        $opcPassword = ''
    } else {
        Write-Host 'First-time setup: choose credentials for this computer.' -ForegroundColor Cyan
        $admin = Read-Host 'Local AHWR admin username'
        if ([string]::IsNullOrWhiteSpace($admin)) { $admin = 'admin' }
        $adminPassword = Read-SecretText 'Local AHWR admin password (minimum 8 characters)'
        if ($adminPassword.Length -lt 8) { throw 'Admin password must be at least 8 characters.' }
        $opcUrl = Read-Host 'KEPServerEX endpoint [opc.tcp://localhost:49320]'
        if ([string]::IsNullOrWhiteSpace($opcUrl)) { $opcUrl = 'opc.tcp://localhost:49320' }
        $opcUser = Read-Host 'KEPServerEX OPC UA username (leave blank if anonymous)'
        $opcPassword = ''
        if (-not [string]::IsNullOrWhiteSpace($opcUser)) { $opcPassword = Read-SecretText 'KEPServerEX OPC UA password' }
    }
    $settings = @(
        "ADMIN_USERNAME=$admin",
        "ADMIN_PASSWORD=$adminPassword",
        "JWT_SECRET=$(New-Secret)",
        'PORT=8080',
        'DATA_SOURCE=plc',
        'AUTH_MODE=local',
        "KEPWARE_OPCUA_URL=$opcUrl",
        "KEPWARE_OPCUA_USERNAME=$opcUser",
        "KEPWARE_OPCUA_PASSWORD=$opcPassword",
        'KEPWARE_SECURITY_MODE=None',
        'KEPWARE_SECURITY_POLICY=None',
        'BOP_RECONNECT_INITIAL_SECONDS=2',
        'BOP_RECONNECT_MAX_SECONDS=60',
        'SYNC_ENABLED=false',
        'ETP_ENABLED=false'
    )
    Set-Content -LiteralPath $SettingsFile -Value $settings -Encoding UTF8
    Write-Host 'Created settings.env. It contains local service credentials; do not share it.' -ForegroundColor Yellow
}

$existingKeys = @(Get-SettingKeys)
$additions = @()
if ($existingKeys -notcontains 'DEVICE_ID') {
    if ($env:AHWR_SIMPLE_START -eq '1') {
        $computer = ($env:COMPUTERNAME -replace '[^A-Za-z0-9._-]', '-').Trim('-')
        if (-not $computer) { $computer = 'LOCAL' }
        $additions += "DEVICE_ID=AHWR-50-$computer"
    } else { $additions += "DEVICE_ID=$(Read-RigId)" }
}
if ($existingKeys -notcontains 'PG_MODE') { $additions += "PG_MODE=$(if (Test-Path -LiteralPath (Join-Path $PgBin 'pg_ctl.exe')) { 'bundled' } else { 'service' })" }
if ($existingKeys -notcontains 'PGHOST') { $additions += 'PGHOST=127.0.0.1' }
if ($existingKeys -notcontains 'PGPORT') { $additions += 'PGPORT=5432' }
if ($existingKeys -notcontains 'PGDATABASE') { $additions += 'PGDATABASE=ahwr_edge' }
if ($existingKeys -notcontains 'PGUSER') { $additions += 'PGUSER=ahwr_app' }
if ($existingKeys -notcontains 'PGPASSWORD') { $additions += "PGPASSWORD=$(New-Secret)" }
if ($existingKeys -notcontains 'TELEGRAF_DB_PASSWORD') { $additions += "TELEGRAF_DB_PASSWORD=$(New-Secret)" }
if ($existingKeys -notcontains 'PG_SUPERUSER_PASSWORD') { $additions += "PG_SUPERUSER_PASSWORD=$(New-Secret)" }
if ($additions.Count) {
    Add-Content -LiteralPath $SettingsFile -Value (@('', '# TimescaleDB historian (added by Start-AHWR-EDGE.ps1)') + $additions) -Encoding UTF8
    Write-Host "Added $($additions.Count) TimescaleDB setting(s) to settings.env." -ForegroundColor Yellow
}

Get-Content -LiteralPath $SettingsFile | ForEach-Object {
    $line = $_.TrimStart([char]0xFEFF)
    if ($line -match '^\s*([^#=]+)=(.*)$') {
        $key = $matches[1].Trim()
        if ($key -ne 'PATH') { [Environment]::SetEnvironmentVariable($key, $matches[2], 'Process') }
    }
}
if ($env:DEVICE_ID -notmatch $RigIdPattern) { throw "DEVICE_ID '$($env:DEVICE_ID)' in settings.env is not valid (1-64 letters, digits, . _ -)." }

# Keep transferred/offline installs portable: runtime paths follow this folder.
if ($env:NODE_EXTRA_CA_CERTS -and [IO.Path]::GetFileName($env:NODE_EXTRA_CA_CERTS) -ieq 'crmf-ca.crt') {
    $bundledCrmfCa = Join-Path $Root 'certs\crmf-ca.crt'
    if (Test-Path -LiteralPath $bundledCrmfCa) {
        if ((Get-FileHash -LiteralPath $bundledCrmfCa -Algorithm SHA256).Hash -ne '22CA02671CA6909FB7680AE222F832CC5A9C307330EC86DBB921F98E1AC14149') {
            throw 'The bundled CRMF public CA does not match the verified certificate.'
        }
        $env:NODE_EXTRA_CA_CERTS = $bundledCrmfCa
    }
}
$env:DATA_DIR = Join-Path $DataDir 'app'
$env:FRONTEND_DIST_DIR = Join-Path $Root 'app\frontend\dist'
$env:TELEGRAF_CONFIG_PATH = Join-Path $Root 'app\telegraf\telegraf.d\plc.conf'
$env:BOP_CONFIG_PATH = Join-Path $DataDir 'app\bop_config.json'
$env:TELEGRAF_LISTENER_URL = 'http://127.0.0.1:8186'
$env:STOP_FILE = Join-Path $RunDir 'backend.stop'
# Telegraf 1.32+ keeps retrying a PLC that is unreachable at start (older releases
# exit); the backend then adds startup_error_behavior = "retry" to plc.conf.
if (-not $env:TELEGRAF_STARTUP_RETRY) {
    $env:TELEGRAF_STARTUP_RETRY = 'false'
    if (((& $Telegraf --version) -join ' ') -match 'Telegraf v?(\d+)\.(\d+)' -and ([int]$matches[1] -gt 1 -or [int]$matches[2] -ge 32)) { $env:TELEGRAF_STARTUP_RETRY = 'true' }
}
if (-not $env:PGHOST) { $env:PGHOST = '127.0.0.1' }
if (-not $env:PGPORT) { $env:PGPORT = '5432' }
if (-not $env:PGDATABASE) { $env:PGDATABASE = 'ahwr_edge' }
if (-not $env:PGUSER) { $env:PGUSER = 'ahwr_app' }
$AppPassword = $env:PGPASSWORD

function Test-Port([int]$Port) {
    try {
        $client = New-Object Net.Sockets.TcpClient
        $task = $client.ConnectAsync('127.0.0.1', $Port)
        $connected = $task.Wait(500) -and $client.Connected
        $client.Dispose()
        return $connected
    } catch { return $false }
}

function Start-ManagedProcess([string]$Name, [string]$File, [string]$Arguments, [string]$WorkingDirectory) {
    $pidFile = Join-Path $RunDir "$Name.pid"
    if (Test-Path -LiteralPath $pidFile) {
        $existingId = 0
        $existingProcess = $null
        if ([int]::TryParse((Get-Content -LiteralPath $pidFile -Raw), [ref]$existingId)) {
            $existingProcess = Get-CimInstance Win32_Process -Filter "ProcessId=$existingId" -ErrorAction SilentlyContinue
        }
        $existingPath = if ($existingProcess) { [string]$existingProcess.ExecutablePath } else { '' }
        if (-not $existingPath) {
            $fallback = Get-Process -Id $existingId -ErrorAction SilentlyContinue
            if ($fallback) { try { $existingPath = [string]$fallback.Path } catch {} }
        }
        if ($existingPath -and $existingPath.StartsWith($Root, [StringComparison]::OrdinalIgnoreCase)) {
            Write-Host "$Name is already running (PID $existingId)."
            return
        }
        Remove-Item -LiteralPath $pidFile -Force
    }
    $out = Join-Path $LogDir "$Name.log"
    $err = Join-Path $LogDir "$Name.err.log"
    $proc = Start-Process -FilePath $File -ArgumentList $Arguments -WorkingDirectory $WorkingDirectory -WindowStyle Hidden -RedirectStandardOutput $out -RedirectStandardError $err -PassThru
    Set-Content -LiteralPath $pidFile -Value $proc.Id -Encoding ASCII
    Write-Host "Started $Name (PID $($proc.Id))."
}

function Assert-PortAvailableOrManaged([int]$Port, [string]$Name) {
    if (-not (Test-Port $Port)) { return }
    $pidFile = Join-Path $RunDir "$Name.pid"
    $managedId = 0
    if ((Test-Path -LiteralPath $pidFile) -and [int]::TryParse((Get-Content -LiteralPath $pidFile -Raw), [ref]$managedId)) {
        $managedProcess = Get-CimInstance Win32_Process -Filter "ProcessId=$managedId" -ErrorAction SilentlyContinue
        $managedPath = if ($managedProcess) { [string]$managedProcess.ExecutablePath } else { '' }
        if (-not $managedPath) {
            $fallback = Get-Process -Id $managedId -ErrorAction SilentlyContinue
            if ($fallback) { try { $managedPath = [string]$fallback.Path } catch {} }
        }
        if ($managedPath -and $managedPath.StartsWith($Root, [StringComparison]::OrdinalIgnoreCase)) { return }
    }
    throw "Port $Port is already in use by an unmanaged process. Stop that service and start AHWR-EDGE again."
}

function Start-AhwrService([string]$Name) {
    $svc = Get-Service $Name -ErrorAction SilentlyContinue
    if (-not $svc) { return }
    if ($svc.Status -eq 'Running') { Write-Host "Service $Name is running."; return }
    try { Start-Service $Name -ErrorAction Stop } catch { throw "Service $Name is $($svc.Status) and could not be started ($($_.Exception.Message)). Start it from services.msc or run Start-AHWR-EDGE.bat as Administrator, and review logs\$Name.log." }
    Write-Host "Started service $Name."
}

function Find-Psql {
    $bundled = Join-Path $PgBin 'psql.exe'
    if (Test-Path -LiteralPath $bundled) { return $bundled }
    $installed = Get-ChildItem 'C:\Program Files\PostgreSQL\*\bin\psql.exe' -ErrorAction SilentlyContinue | Sort-Object FullName -Descending | Select-Object -First 1
    if ($installed) { return $installed.FullName }
    return $null
}

# Apply app\sql (idempotent) as the postgres superuser.
function Invoke-Schema([string]$Psql) {
    $env:PGPASSWORD = $env:PG_SUPERUSER_PASSWORD
    try {
        & $Psql -X -q -h $env:PGHOST -p $env:PGPORT -U postgres -d postgres -v ON_ERROR_STOP=1 `
            -v "tg_pw=$($env:TELEGRAF_DB_PASSWORD)" -v "app_pw=$AppPassword" -f (Join-Path $SqlDir '01-roles.sql') | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'app\sql\01-roles.sql failed; see the messages above.' }
        & $Psql -X -q -h $env:PGHOST -p $env:PGPORT -U postgres -d $env:PGDATABASE -v ON_ERROR_STOP=1 -f (Join-Path $SqlDir '02-schema.sql') | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'app\sql\02-schema.sql failed; see the messages above.' }
    } finally {
        $env:PGPASSWORD = $AppPassword
    }
    Write-Host 'TimescaleDB roles and schema are up to date.'
}

# --- PostgreSQL + TimescaleDB -------------------------------------------------
function Get-InitdbVersionResult([string]$InitDbPath) {
    $oldPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(& $InitDbPath --version 2>&1)
        $code = $LASTEXITCODE
    } finally { $ErrorActionPreference = $oldPreference }
    [pscustomobject]@{ Code = $code; Output = (@($output | ForEach-Object { [string]$_ }) -join ' ').Trim() }
}

function Ensure-PostgresRuntime([string]$InitDbPath) {
    $probe = Get-InitdbVersionResult $InitDbPath
    if ($probe.Code -eq 0) { return }
    if ($probe.Code -ne -1073741515) {
        throw "PostgreSQL initdb cannot load (exit $($probe.Code)): $($probe.Output)"
    }

    # 0xC0000135 means Windows could not load a required DLL. The offline
    # package includes Microsoft's signed x64 VC++ runtime for this case.
    $redist = Join-Path $Root 'runtime\vc_redist.x64.exe'
    if (-not (Test-Path -LiteralPath $redist)) {
        throw "PostgreSQL needs the Microsoft Visual C++ x64 runtime, but $redist is missing. Extract the complete AHWR-150-EDGE ZIP again."
    }
    $expectedHash = '843068991DAAA1F73AD9F6239BCE4D0F6A07A51F18C37EA2A867E9BECA71295C'
    if ((Get-FileHash -LiteralPath $redist -Algorithm SHA256).Hash -ne $expectedHash) {
        throw 'The bundled Microsoft Visual C++ runtime did not pass its SHA256 check. Extract the complete AHWR-150-EDGE ZIP again.'
    }
    Write-Host 'Installing the required Microsoft Visual C++ x64 runtime (one-time Windows approval may appear)...' -ForegroundColor Cyan
    try {
        $installed = Start-Process -FilePath $redist -ArgumentList @('/install', '/quiet', '/norestart') -Verb RunAs -WindowStyle Hidden -Wait -PassThru
    } catch {
        throw "The Microsoft Visual C++ runtime installation was cancelled or failed: $($_.Exception.Message)"
    }
    $probe = Get-InitdbVersionResult $InitDbPath
    if ($probe.Code -ne 0) {
        $restart = if ($installed.ExitCode -eq 3010) { ' Restart Windows, then run Start-AHWR-EDGE.bat again.' } else { '' }
        throw "PostgreSQL still cannot load after the Microsoft Visual C++ runtime installer (installer exit $($installed.ExitCode), initdb exit $($probe.Code)).$restart"
    }
    Write-Host "PostgreSQL runtime ready: $($probe.Output)" -ForegroundColor Green
}

$pgPort = [int]$env:PGPORT
if ($env:PG_MODE -eq 'bundled') {
    $PgCtl = Join-Path $PgBin 'pg_ctl.exe'
    $InitDb = Join-Path $PgBin 'initdb.exe'
    if (-not (Test-Path -LiteralPath $PgCtl)) { throw "PG_MODE=bundled but $PgCtl is missing. Copy the PostgreSQL + TimescaleDB runtime to runtime\pgsql, or set PG_MODE=service." }
    Ensure-PostgresRuntime $InitDb
    if (-not (Test-Path -LiteralPath (Join-Path $PgData 'PG_VERSION'))) {
        Write-Host 'Initialising the local PostgreSQL + TimescaleDB cluster...' -ForegroundColor Cyan
        $pwFile = Join-Path $RunDir 'pg-init.tmp'
        Set-Content -LiteralPath $pwFile -Value $env:PG_SUPERUSER_PASSWORD -Encoding ASCII -NoNewline
        try {
            $oldPreference = $ErrorActionPreference
            $ErrorActionPreference = 'Continue'
            try {
                $initOutput = @(& $InitDb -D $PgData -U postgres -E UTF8 --locale=C --auth=scram-sha-256 "--pwfile=$pwFile" 2>&1)
                $initCode = $LASTEXITCODE
            } finally { $ErrorActionPreference = $oldPreference }
            $initLines = @($initOutput | ForEach-Object { [string]$_ })
            Set-Content -LiteralPath (Join-Path $LogDir 'initdb.log') -Value $initLines -Encoding UTF8
            if ($initCode -ne 0) {
                $detail = (@($initLines | Select-Object -Last 3) -join ' ').Trim()
                throw "initdb failed (exit $initCode): $detail. See logs\initdb.log."
            }
        } finally { Remove-Item -LiteralPath $pwFile -Force -ErrorAction SilentlyContinue }
        Add-Content -LiteralPath (Join-Path $PgData 'postgresql.conf') -Encoding ASCII -Value @(
            '',
            '# AHWR-50 EDGE (TimescaleDB historian)',
            "listen_addresses = '127.0.0.1'",
            "port = $pgPort",
            "shared_preload_libraries = 'timescaledb'",
            'timescaledb.telemetry_level = off',
            'timescaledb.max_background_workers = 2',
            'max_worker_processes = 8',
            'shared_buffers = 256MB',
            'effective_cache_size = 1GB',
            'maintenance_work_mem = 64MB',
            'max_wal_size = 1GB',
            'checkpoint_timeout = 15min',
            'wal_compression = on'
        )
    }
    & $PgCtl status -D $PgData | Out-Null
    if ($ServiceMode -and (Get-Service 'AHWR-PostgreSQL' -ErrorAction SilentlyContinue)) {
        Start-AhwrService 'AHWR-PostgreSQL'
        $ready = $false
        for ($i = 0; $i -lt 60; $i++) { if (Test-Port $pgPort) { $ready = $true; break }; Start-Sleep -Seconds 1 }
        if (-not $ready) { throw "PostgreSQL is not reachable on 127.0.0.1:$pgPort. Review data\pgdata\log." }
    } elseif ($LASTEXITCODE -ne 0) {
        Assert-PortAvailableOrManaged $pgPort 'postgresql'
        if ($env:AHWR_PORTABLE -eq '1') {
            Start-ManagedProcess 'postgresql' (Join-Path $PgBin 'postgres.exe') "-D `"$PgData`"" $Root
            $ready = $false
            $pgIsReady = Join-Path $PgBin 'pg_isready.exe'
            for ($i = 0; $i -lt 120; $i++) {
                & $pgIsReady -h 127.0.0.1 -p $pgPort -q
                if ($LASTEXITCODE -eq 0) { $ready = $true; break }
                Start-Sleep -Seconds 1
            }
            if (-not $ready) { throw 'PostgreSQL did not start. Review logs\postgresql.err.log.' }
        } else {
            & $PgCtl start -D $PgData -l (Join-Path $LogDir 'postgresql.log') -w -t 120 | Out-Null
            if ($LASTEXITCODE -ne 0) { throw 'PostgreSQL did not start. Review logs\postgresql.log.' }
        }
        Write-Host 'Started PostgreSQL + TimescaleDB.'
    } else {
        Write-Host 'PostgreSQL is already running.'
    }
    if ($env:AHWR_PORTABLE -eq '1') {
        $pgIsReady = Join-Path $PgBin 'pg_isready.exe'
        $ready = $false
        for ($i = 0; $i -lt 120; $i++) {
            & $pgIsReady -h 127.0.0.1 -p $pgPort -q
            if ($LASTEXITCODE -eq 0) { $ready = $true; break }
            Start-Sleep -Seconds 1
        }
        if (-not $ready) { throw 'PostgreSQL is not ready. Review logs\postgresql.err.log.' }
    }
    Invoke-Schema (Join-Path $PgBin 'psql.exe')
} else {
    $ready = $false
    for ($i = 0; $i -lt 60; $i++) { if (Test-Port $pgPort) { $ready = $true; break }; Start-Sleep -Seconds 1 }
    if (-not $ready) { throw "PostgreSQL is not reachable on 127.0.0.1:$pgPort. Start the PostgreSQL service (see the Edge Installation Guide) or set PG_MODE=bundled." }
    $psql = Find-Psql
    if ($psql -and $env:PG_SUPERUSER_PASSWORD) {
        Invoke-Schema $psql
    } else {
        Write-Host 'Service mode: apply app\sql\01-roles.sql and 02-schema.sql as postgres if not done yet (see docs\timescaledb.md).' -ForegroundColor Yellow
    }
}

# --- Telegraf, backend, BOP collector ------------------------------------------
$appPort = if ($env:PORT) { [int]$env:PORT } else { 8080 }
$scheme = if ($env:TLS_CERT_FILE -and $env:TLS_KEY_FILE) { 'https' } else { 'http' }
$probeHost = if ($env:HOST -and $env:HOST -notin @('0.0.0.0', '::')) { $env:HOST } else { '127.0.0.1' }
if ($ServiceMode) {
    $stamp = Join-Path $RunDir 'services.installed'
    if ((Test-Path -LiteralPath $stamp) -and (Get-Item -LiteralPath $SettingsFile).LastWriteTime -gt (Get-Item -LiteralPath $stamp).LastWriteTime) {
        Write-Host 'settings.env changed since the services were installed: restart AHWR-Backend and AHWR-BOP-Collector (or re-run Install-AHWR-EDGE-Services.ps1) to apply it.' -ForegroundColor Yellow
    }
    foreach ($name in @('AHWR-Telegraf', 'AHWR-Backend', 'AHWR-BOP-Collector')) { Start-AhwrService $name }
} else {
    Assert-PortAvailableOrManaged 8888 'telegraf'
    Assert-PortAvailableOrManaged 8186 'telegraf'
    Assert-PortAvailableOrManaged $appPort 'backend'
    Start-ManagedProcess 'backend' $Node "`"$Backend`"" (Join-Path $Root 'app\backend')
}

# Readiness probe of this PC's own backend (its certificate may be self-signed).
$healthUrl = "${scheme}://${probeHost}:$appPort/healthz"
if ($scheme -eq 'https' -and $PSVersionTable.PSVersion.Major -lt 6) { [Net.ServicePointManager]::ServerCertificateValidationCallback = { $true } }
$backendReady = $false
for ($i = 0; $i -lt 45; $i++) {
    try {
        if ($PSVersionTable.PSVersion.Major -ge 6) { $null = Invoke-RestMethod $healthUrl -TimeoutSec 2 -SkipCertificateCheck } else { $null = Invoke-RestMethod $healthUrl -TimeoutSec 2 }
        $backendReady = $true; break
    } catch { Start-Sleep -Seconds 1 }
}
if ($scheme -eq 'https' -and $PSVersionTable.PSVersion.Major -lt 6) { [Net.ServicePointManager]::ServerCertificateValidationCallback = $null }
if (-not $backendReady) { throw "AHWR backend did not answer on $healthUrl. Review $(if ($ServiceMode) { 'logs\AHWR-Backend.log' } else { 'logs\backend.err.log' })." }

# The backend writes the current PLC configuration on startup. Start Telegraf
# afterwards so an unreachable sample/default PLC cannot make it exit before
# the generated configuration and retry policy are in place.
if (-not $ServiceMode) {
    Start-ManagedProcess 'telegraf' $Telegraf "--config `"$Root\app\telegraf\telegraf.conf`" --config-directory `"$Root\app\telegraf\telegraf.d`" --watch-config=poll" (Join-Path $Root 'app\telegraf')
    $telegrafReady = $false
    for ($i = 0; $i -lt 30; $i++) {
        if ((Test-Port 8888) -and (Test-Port 8186)) { $telegrafReady = $true; break }
        Start-Sleep -Seconds 1
    }
    if (-not $telegrafReady) { throw 'Telegraf did not start its local health and BOP listeners. Review logs\telegraf.err.log.' }
}

# The initial password is only needed once to seed the app user store; remove it
# from the environment file after the first successful initialization.
$settingsContent = Get-Content -LiteralPath $SettingsFile -Raw
if ($settingsContent -match '(?m)^ADMIN_PASSWORD=') {
    $settingsContent = [regex]::Replace($settingsContent, '(?m)^ADMIN_PASSWORD=.*(?:\r?\n|$)', '')
    Set-Content -LiteralPath $SettingsFile -Value $settingsContent.TrimEnd() -Encoding UTF8
}

if (-not $ServiceMode) { Start-ManagedProcess 'bop-collector' $Python "`"$Collector`"" (Join-Path $Root 'app') }

$lanIp = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -notlike '127.*' -and $_.AddressState -eq 'Preferred' } | Select-Object -First 1 -ExpandProperty IPAddress)
Write-Host ''
Write-Host "AHWR-EDGE is running (rig $($env:DEVICE_ID), historian: TimescaleDB, $($env:PG_MODE) mode$(if ($ServiceMode) { ', Windows services' }))." -ForegroundColor Green
$localUrl = "${scheme}://localhost:$appPort"
if ($probeHost -ne '127.0.0.1') { $localUrl = "${scheme}://${probeHost}:$appPort" }
Write-Host "This PC: $localUrl"
if ($lanIp -and $probeHost -eq '127.0.0.1' -and $env:HOST -ne '127.0.0.1') { Write-Host "Other PCs on this LAN: ${scheme}://${lanIp}:$appPort" }
Write-Host 'Allow Windows Firewall access on the Private network if prompted.'
# The single-click installer starts the edge once without opening a browser.
if (-not $env:AHWR_NO_BROWSER) { Start-Process $localUrl }
