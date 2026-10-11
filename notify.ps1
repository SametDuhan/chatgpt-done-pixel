param([Parameter(Position=0)][string]$Notification = '{}')
$ErrorActionPreference = 'Stop'
# Quote each native argv item according to Windows CommandLineToArgvW rules.
# Start-Process otherwise joins arguments without protecting JSON quotes/spaces.
function Quote-NativeArg([string]$Value) {
    $Value = [regex]::Replace($Value, '(\\*)"', '$1$1\"')
    $Value = [regex]::Replace($Value, '(\\+)$', '$1$1')
    return '"' + $Value + '"'
}
function Start-Native([string[]]$Command) {
    if ($Command.Count -eq 0) { return }
    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = $Command[0]
    $info.Arguments = (($Command | Select-Object -Skip 1 | ForEach-Object { Quote-NativeArg $_ }) -join ' ')
    $info.UseShellExecute = $false; $info.CreateNoWindow = $true
    return [System.Diagnostics.Process]::Start($info)
}
$statePath = Join-Path $PSScriptRoot 'install-state.json'
if (-not (Test-Path -LiteralPath $statePath)) { return }
$state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
# Forward the original notification first, for all event types. Never print or
# persist the payload: it may include private assistant/user message text.
if ($state.originalCommand.Count -gt 0) {
    try {
        $p = Start-Native (@($state.originalCommand) + @($Notification))
        if ($null -ne $p) { [void]$p.WaitForExit(10000); $p.Dispose() }
    } catch { Write-Warning 'The previous notify handler could not be started.' }
}
try { $event = $Notification | ConvertFrom-Json } catch { return }
if ($event.type -ne 'agent-turn-complete') { return }
$command = @('powershell.exe','-NoProfile','-STA','-ExecutionPolicy','Bypass','-WindowStyle','Hidden',
    '-File',(Join-Path $PSScriptRoot 'chatgpt-done.ps1'),'-Scale',[string]$state.scale,'-Speed',[string]$state.speed)
$p = Start-Native $command
if ($null -ne $p) { $p.Dispose() }
