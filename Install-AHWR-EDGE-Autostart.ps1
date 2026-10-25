$ErrorActionPreference = 'Stop'

$Root = $PSScriptRoot
$StartLauncher = Join-Path $Root 'Start AHWR-EDGE.exe'
if (-not (Test-Path -LiteralPath $StartLauncher)) {
    throw "Missing start file: $StartLauncher"
}

$StartupDir = [Environment]::GetFolderPath('Startup')
$ShortcutPath = Join-Path $StartupDir 'AHWR-EDGE.lnk'

$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($ShortcutPath)
$shortcut.TargetPath = $StartLauncher
$shortcut.WorkingDirectory = $Root
$shortcut.IconLocation = $StartLauncher
$shortcut.WindowStyle = 7
$shortcut.Description = 'Start AHWR-EDGE and open the local dashboard'
$shortcut.Save()

Write-Host "AHWR-EDGE will start automatically when this Windows user logs in." -ForegroundColor Green
Write-Host "Startup shortcut: $ShortcutPath"
