param(
    [ValidateRange(2,12)][double]$Scale = 4,
    [ValidateRange(0.25,4)][double]$Speed = 1,
    [string]$ConfigPath = '',
    [string]$InstallDir = ''
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'config-tools.ps1')
if (-not $ConfigPath) {
    $codexDir = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' }
    $ConfigPath = Join-Path $codexDir 'config.toml'
}
if (-not $InstallDir) { $InstallDir = Join-Path $env:USERPROFILE '.chatgpt-done' }
$ConfigPath = [IO.Path]::GetFullPath($ConfigPath); $InstallDir = [IO.Path]::GetFullPath($InstallDir)
$text = if (Test-Path -LiteralPath $ConfigPath) { [IO.File]::ReadAllText($ConfigPath) } else { '' }
$slot = Get-NotifySlot $text
$statePath = Join-Path $InstallDir 'install-state.json'
$command = @('powershell.exe','-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',
    (Join-Path $InstallDir 'notify.ps1'),'-Notification')
$line = 'notify = ' + (ConvertTo-Json -InputObject $command -Compress)
if (Test-Path -LiteralPath $statePath) {
    $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    if ($state.configPath -ne $ConfigPath -or $null -eq $slot -or $slot.Line.Trim() -ne $state.installedLine.Trim()) {
        throw 'Config changed after installation. Uninstall or resolve the notify change before reinstalling.'
    }
    $state.installedLine = $line; $state.scale = $Scale; $state.speed = $Speed
} else {
    $originalLine = if ($null -ne $slot) { $slot.Line } else { '' }
    $originalCommand = if ($null -ne $slot) { @($slot.Command) } else { @() }
    $state = [pscustomobject]@{ configPath=$ConfigPath; originalLine=$originalLine; originalCommand=@($originalCommand);
        installedLine=$line; scale=$Scale; speed=$Speed }
}
$updated = Set-NotifyLine $text $line
New-Item -ItemType Directory -Force $InstallDir | Out-Null
New-Item -ItemType Directory -Force (Split-Path -Parent $ConfigPath) | Out-Null
foreach ($name in @('chatgpt-done.ps1','notify.ps1','config-tools.ps1')) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination (Join-Path $InstallDir $name) -Force
}
if (Test-Path -LiteralPath $ConfigPath) {
    $backup = $ConfigPath + '.chatgpt-done.' + [DateTime]::UtcNow.ToString('yyyyMMddHHmmssfff') + '.bak'
    Copy-Item -LiteralPath $ConfigPath -Destination $backup
}
Write-Utf8Atomic $statePath ($state | ConvertTo-Json -Depth 10)
Write-Utf8Atomic $ConfigPath $updated
Write-Host "Installed: $InstallDir"
Write-Host 'Restart Codex/ChatGPT to load the notify command. Your previous handler is preserved.'
