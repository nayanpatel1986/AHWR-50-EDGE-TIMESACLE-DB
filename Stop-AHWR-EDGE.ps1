param(
    # Also stop the backend (dashboard) and PostgreSQL.
    [switch]$All
)
$ErrorActionPreference = 'Continue'
$Root = $PSScriptRoot
$RunDir = Join-Path $Root 'run'

# Windows services (Install-AHWR-EDGE-Services.ps1): stop collection; with -All
# also the backend and the bundled PostgreSQL. They start again at the next boot
# or with Start-AHWR-EDGE.bat. Stopping a service needs an elevated PowerShell.
if ($env:AHWR_PORTABLE -ne '1' -and (Get-Service 'AHWR-Backend' -ErrorAction SilentlyContinue)) {
    $names = @('AHWR-BOP-Collector', 'AHWR-Telegraf')
    if ($All) { $names += @('AHWR-Backend', 'AHWR-PostgreSQL') }
    $running = @($names | ForEach-Object { Get-Service $_ -ErrorAction SilentlyContinue } | Where-Object { $_.Status -ne 'Stopped' })
    if (-not $running.Count) {
        Write-Host 'AHWR-EDGE services are already stopped.'
        return
    }
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host 'Administrator approval is needed to stop AHWR-EDGE services.' -ForegroundColor Cyan
        $arguments = @('-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $PSCommandPath))
        if ($All) { $arguments += '-All' }
        try {
            $elevated = Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -Verb RunAs -Wait -PassThru
            exit $elevated.ExitCode
        } catch {
            Write-Host "Administrator approval was cancelled or failed: $($_.Exception.Message)" -ForegroundColor Red
            exit 1
        }
    }
    $failed = $false
    foreach ($name in $names) {
        $svc = Get-Service $name -ErrorAction SilentlyContinue
        if (-not $svc -or $svc.Status -eq 'Stopped') { continue }
        try {
            Stop-Service $name -Force -ErrorAction Stop
            $svc.WaitForStatus([ServiceProcess.ServiceControllerStatus]::Stopped, [TimeSpan]::FromSeconds(30))
            Write-Host "Stopped service $name."
        } catch {
            $failed = $true
            Write-Host "Could not stop $name ($($_.Exception.Message))." -ForegroundColor Red
        }
    }
    if ($failed) { exit 1 }
    if ($All) { Write-Host 'AHWR-EDGE services stopped.' }
    else { Write-Host 'AHWR-EDGE collection stopped. The dashboard UI remains available; refresh it to see NO DATA.' }
    return
}

# Portable processes. Without -All the backend UI server and PostgreSQL keep
# running: an open browser refreshes into the dashboard shell with -- / NO DATA
# values, and logbook/work-order records can still be saved.
$processes = @('bop-collector', 'telegraf')
if ($All) { $processes += 'backend' }
foreach ($name in $processes) {
    $pidFile = Join-Path $RunDir "$name.pid"
    if (-not (Test-Path -LiteralPath $pidFile)) { continue }
    $serviceId = 0
    if ([int]::TryParse((Get-Content -LiteralPath $pidFile -Raw), [ref]$serviceId)) {
        $proc = Get-CimInstance Win32_Process -Filter "ProcessId=$serviceId" -ErrorAction SilentlyContinue
        $processPath = if ($proc) { [string]$proc.ExecutablePath } else { '' }
        if (-not $processPath) {
            $fallback = Get-Process -Id $serviceId -ErrorAction SilentlyContinue
            if ($fallback) { try { $processPath = [string]$fallback.Path } catch {} }
        }
        if ($processPath -and $processPath.StartsWith($Root, [StringComparison]::OrdinalIgnoreCase)) {
            if ($name -eq 'backend') {
                # Graceful: the backend saves pending records, then exits.
                Set-Content -LiteralPath (Join-Path $RunDir 'backend.stop') -Value 'stop' -Encoding ASCII
                Wait-Process -Id $serviceId -Timeout 20 -ErrorAction SilentlyContinue
                Remove-Item -LiteralPath (Join-Path $RunDir 'backend.stop') -Force -ErrorAction SilentlyContinue
            }
            Stop-Process -Id $serviceId -Force -ErrorAction SilentlyContinue
            Write-Host "Stopped $name (PID $serviceId)."
        }
    }
    Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
}

# With -All the bundled PostgreSQL (PG_MODE=bundled) is stopped cleanly, after
# the backend; an installed PostgreSQL service (PG_MODE=service) is left to Windows.
$pgCtl = Join-Path $Root 'runtime\pgsql\bin\pg_ctl.exe'
$pgData = Join-Path $Root 'data\pgdata'
$pgStopFailed = $false
if ($All -and (Test-Path -LiteralPath $pgCtl) -and (Test-Path -LiteralPath (Join-Path $pgData 'postmaster.pid'))) {
    & $pgCtl stop -D $pgData -m fast -w | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host 'Stopped PostgreSQL + TimescaleDB.'
    } elseif ($env:AHWR_PORTABLE -eq '1') {
        # Only touch PostgreSQL processes whose executable belongs to this
        # extracted folder. Windows can reject pg_ctl's stop signal in some
        # restricted environments; a forced stop is the last resort.
        $exe = Join-Path $Root 'runtime\pgsql\bin\postgres.exe'
        $owned = @(Get-Process -Name postgres -ErrorAction SilentlyContinue | Where-Object {
            try { [string]$_.Path -ieq $exe } catch { $false }
        })
        foreach ($process in $owned) { Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue }
        $remaining = @()
        $portOpen = $true
        for ($i = 0; $i -lt 15; $i++) {
            $remaining = @(Get-Process -Name postgres -ErrorAction SilentlyContinue | Where-Object {
                try { [string]$_.Path -ieq $exe } catch { $false }
            })
            $client = New-Object Net.Sockets.TcpClient
            try { $portOpen = $client.ConnectAsync('127.0.0.1', 5432).Wait(500) -and $client.Connected }
            catch { $portOpen = $false }
            finally { $client.Dispose() }
            if (-not $remaining.Count -and -not $portOpen) { break }
            Start-Sleep -Seconds 1
        }
        if ($remaining.Count -or $portOpen) {
            $pgStopFailed = $true
            Write-Host 'PostgreSQL is still running; see logs\postgresql.err.log.' -ForegroundColor Red
        } else {
            Remove-Item -LiteralPath (Join-Path $RunDir 'postgresql.pid') -Force -ErrorAction SilentlyContinue
            Write-Host 'PostgreSQL stopped after Windows rejected the graceful stop signal.' -ForegroundColor Yellow
        }
    } else {
        $pgStopFailed = $true
        Write-Host 'PostgreSQL did not stop cleanly; see logs\postgresql.log.' -ForegroundColor Red
    }
}
if ($pgStopFailed) { exit 1 }
if ($All) { Write-Host 'AHWR-EDGE stopped.' }
else { Write-Host 'AHWR-EDGE live services stopped. The dashboard UI remains available; refresh it to see NO DATA.' }
