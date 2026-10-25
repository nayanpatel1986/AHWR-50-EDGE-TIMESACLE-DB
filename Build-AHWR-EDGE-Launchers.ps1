$ErrorActionPreference = 'Stop'
$Root = $PSScriptRoot
$Compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
$Source = Join-Path $Root 'launchers\AhwrEdgeLauncher.cs'
$Icon = Join-Path $Root 'assets\ahwr-edge-rig-photo.ico'

foreach ($path in @($Compiler, $Source, $Icon)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Missing build file: $path" }
}

foreach ($action in @('Start', 'Stop')) {
    $output = Join-Path $Root "$action AHWR-EDGE.exe"
    $define = if ($action -eq 'Stop') { 'STOP' } else { 'START' }
    & $Compiler /nologo /target:winexe /platform:x64 /optimize+ "/define:$define" "/win32icon:$Icon" "/out:$output" /reference:System.Windows.Forms.dll $Source
    if ($LASTEXITCODE -ne 0) { throw "Could not build $output" }
    Write-Host "Built $output"
}
