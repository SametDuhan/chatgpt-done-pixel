# Deliberately support only a single-line top-level notify array. Unknown TOML
# shapes fail before any write, rather than silently damaging the user's config.
function Get-NotifySlot([string]$Text) {
    $table = [regex]::Match($Text, '(?m)^\s*\[')
    $end = if ($table.Success) { $table.Index } else { $Text.Length }
    $prefix = $Text.Substring(0, $end)
    $matches = [regex]::Matches($prefix, '(?m)^[ \t]*notify[ \t]*=[ \t]*(\[[^\r\n]*\])[ \t]*(?:#[^\r\n]*)?\r?$')
    $starts = [regex]::Matches($prefix, '(?m)^[ \t]*notify[ \t]*=')
    if ($starts.Count -ne $matches.Count -or $matches.Count -gt 1) {
        throw 'Unsupported notify syntax. Put the top-level notify array on one line first.'
    }
    if ($matches.Count -eq 0) { return $null }
    $m = $matches[0]
    # JSON strings and TOML basic strings share the escapes needed for commands.
    try { $parsed = $m.Groups[1].Value | ConvertFrom-Json; $command = @($parsed) }
    catch { throw 'Use double-quoted strings in the single-line notify array first.' }
    foreach ($arg in $command) { if ($arg -isnot [string]) { throw 'notify must be an array of strings.' } }
    return [pscustomobject]@{ Index=$m.Index; Length=$m.Length; Line=$m.Value; Command=$command }
}
function Set-NotifyLine([string]$Text, [string]$Line) {
    $slot = Get-NotifySlot $Text
    if ($null -ne $slot) { return $Text.Remove($slot.Index,$slot.Length).Insert($slot.Index,$Line) }
    if (-not $Line) { return $Text }
    return $Line + "`r`n" + $Text
}
function Write-Utf8Atomic([string]$Path,[string]$Text) {
    $tmp = $Path + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
    $swapBackup = $tmp + '.bak'
    try {
        [System.IO.File]::WriteAllText($tmp,$Text,(New-Object System.Text.UTF8Encoding($false)))
        if (Test-Path -LiteralPath $Path) { [System.IO.File]::Replace($tmp,$Path,$swapBackup) }
        else { [System.IO.File]::Move($tmp,$Path) }
    } finally {
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp }
        if (Test-Path -LiteralPath $swapBackup) { Remove-Item -LiteralPath $swapBackup }
    }
}
