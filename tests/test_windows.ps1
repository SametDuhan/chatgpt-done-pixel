$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
. (Join-Path $repo 'config-tools.ps1')
function Assert($ok, [string]$message) { if (-not $ok) { throw $message } }
$temp = Join-Path ([IO.Path]::GetTempPath()) ('chatgpt-pixel-test-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $temp | Out-Null
try {
    $config = Join-Path $temp 'config.toml'; $target = Join-Path $temp 'installed with spaces'
    $original = "notify = [`"original.exe`", `"turn-ended`"]`r`nmodel = `"test`"`r`n[desktop]`r`nother = true`r`n"
    Write-Utf8Atomic $config $original
    & (Join-Path $repo 'install.ps1') -ConfigPath $config -InstallDir $target
    $state = Get-Content (Join-Path $target 'install-state.json') -Raw | ConvertFrom-Json
    Assert ($state.originalCommand[0] -eq 'original.exe') 'Original command not preserved'
    & (Join-Path $repo 'install.ps1') -ConfigPath $config -InstallDir $target -Scale 5
    $text = [IO.File]::ReadAllText($config)
    Assert (([regex]::Matches($text,'(?m)^notify\s*=')).Count -eq 1) 'Duplicate notify after reinstall'
    # Exercise the real notify adapter against a harmless native receiver.
    $receiver = Join-Path $temp 'receiver.ps1'; $received = Join-Path $temp 'received.txt'
    Write-Utf8Atomic $receiver 'param([string]$OutputFile,[string]$Notification); [IO.File]::WriteAllText($OutputFile,$Notification)'
    $state = Get-Content (Join-Path $target 'install-state.json') -Raw | ConvertFrom-Json
    $state.originalCommand = @('powershell.exe','-NoProfile','-ExecutionPolicy','Bypass','-File',$receiver,'-OutputFile',$received,'-Notification')
    Write-Utf8Atomic (Join-Path $target 'install-state.json') ($state | ConvertTo-Json -Depth 10)
    $payload = '{"type":"approval-requested","text":"quoted \"private\" message, C:\\space path\\"}'
    & (Join-Path $target 'notify.ps1') -Notification $payload
    Assert ((Test-Path -LiteralPath $received) -and [IO.File]::ReadAllText($received) -eq $payload) 'Native JSON forwarding changed the payload'
    $text += "`r`n# user's later edit`r`n"
    Write-Utf8Atomic $config $text
    & (Join-Path $repo 'uninstall.ps1') -InstallDir $target
    $restored = [IO.File]::ReadAllText($config)
    Assert ($restored.StartsWith($original)) 'Original notify was not restored'
    Assert ($restored.Contains("# user's later edit")) 'Later config edit lost'
    $bad = "notify = [`r`n  `"program`"`r`n]`r`nmodel = `"test`""
    Write-Utf8Atomic $config $bad
    $failed = $false
    try { & (Join-Path $repo 'install.ps1') -ConfigPath $config -InstallDir $target } catch { $failed = $true }
    Assert $failed 'Multiline notify must fail closed'
    Assert ([IO.File]::ReadAllText($config) -eq $bad) 'Unsupported TOML was modified'
    # Load the actual renderer and assert window flags, geometry and lifetime.
    . (Join-Path $repo 'chatgpt-done.ps1') -CompileOnly
    $form = New-Object ChatGPTDonePixel -ArgumentList 4,1
    try {
        Assert (-not $form.ShowInTaskbar) 'Overlay should not appear on the taskbar'
        Assert $form.TopMost 'Overlay should be topmost'
        Assert ($form.Bottom -lt [Windows.Forms.Screen]::PrimaryScreen.WorkingArea.Bottom) 'Overlay covers taskbar'
        Assert ([ChatGPTDonePixel]::Duration -gt 5 -and [ChatGPTDonePixel]::Duration -lt 7) 'Unexpected duration'
    } finally { $form.Dispose() }
    Write-Host 'PASS: install/reinstall/uninstall, config preservation, native JSON forwarding, unsupported TOML, renderer.'
} finally {
    # Only the uniquely-created test folder is removed.
    Remove-Item -LiteralPath $temp -Recurse -Force
}
