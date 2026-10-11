param([string]$InstallDir = '')
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'config-tools.ps1')
if (-not $InstallDir) { $InstallDir = Join-Path $env:USERPROFILE '.chatgpt-done' }
$statePath = Join-Path $InstallDir 'install-state.json'
if (-not (Test-Path -LiteralPath $statePath)) { Write-Host 'Already uninstalled.'; return }
$state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
$text = [IO.File]::ReadAllText($state.configPath)
$slot = Get-NotifySlot $text
if ($null -eq $slot -or $slot.Line.Trim() -ne $state.installedLine.Trim()) {
    throw 'notify was changed after installation. No config or files were removed; resolve that change first.'
}
$updated = Set-NotifyLine $text $state.originalLine
if (-not $state.originalLine) { $updated = $updated.TrimStart([char[]]"`r`n") }
Copy-Item -LiteralPath $state.configPath -Destination ($state.configPath+'.chatgpt-done.uninstall.bak') -Force
Write-Utf8Atomic $state.configPath $updated
# Delete only files owned by this installer, never an arbitrary directory tree.
foreach ($name in @('chatgpt-done.ps1','notify.ps1','config-tools.ps1','install-state.json')) {
    $file = Join-Path $InstallDir $name
    if (Test-Path -LiteralPath $file) { Remove-Item -LiteralPath $file }
}
Write-Host 'Uninstalled. Previous notify restored; other configuration preserved.'
