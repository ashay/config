Import-Module PSReadLine

$_bgKind = if ($env:PS_COLOR_THEME) {
  $env:PS_COLOR_THEME
} else {
  'dark'
}

if ($_bgKind -eq 'light') {
  # Gruvbox Light
  Set-PSReadLineOption -Colors @{
    Default              = "`e[38;2;60;56;54m"       # fg0  #3c3836
    Command              = "`e[38;2;69;133;136m"     # aqua #458588
    Parameter            = "`e[38;2;7;102;120m"      # dark aqua #076678
    String               = "`e[38;2;121;116;14m"     # green #797410
    Operator             = "`e[38;2;124;111;100m"    # fg4  #7c6f64
    Variable             = "`e[38;2;175;58;3m"       # orange #af3a03
    Keyword              = "`e[38;2;157;0;6m"        # red  #9d0006
    Number               = "`e[38;2;143;63;113m"     # purple #8f3f71
    Type                 = "`e[38;2;177;98;134m"     # light purple #b16286
    Member               = "`e[38;2;69;133;136m"     # aqua #458588
    Comment              = "`e[38;2;146;131;116m"    # gray #928374
    Error                = "`e[38;2;204;36;29m"      # bright red #cc241d
    InlinePrediction     = "`e[38;2;189;174;147m"    # bg3  #bdae93
    ListPrediction       = "`e[38;2;146;131;116m"    # gray #928374
    ListPredictionSelected = "`e[48;2;213;196;161m"  # bg2  #d5c4a1
    Selection            = "`e[48;2;213;196;161m"    # bg2  #d5c4a1
    ContinuationPrompt   = "`e[38;2;146;131;116m"   # gray #928374
  }
} else {
  # Gruvbox Dark
  Set-PSReadLineOption -Colors @{
    Default                = "`e[38;2;104;157;106m"    # green #689d6a
    Command                = "`e[38;2;142;192;124m"    # green #8ec07c
    Parameter              = "`e[38;2;131;165;152m"    # aqua #83a598
    String                 = "`e[38;2;184;187;38m"     # yellow-green #b8bb26
    Operator               = "`e[38;2;168;153;132m"    # fg4  #a89984
    Variable               = "`e[38;2;254;128;25m"     # orange #fe8019
    Keyword                = "`e[38;2;251;73;52m"      # red  #fb4934
    Number                 = "`e[38;2;211;134;155m"    # purple #d3869b
    Type                   = "`e[38;2;131;165;152m"    # aqua #83a598
    Member                 = "`e[38;2;250;189;47m"     # yellow #fabd2f
    Comment                = "`e[38;2;146;131;116m"    # gray #928374
    Error                  = "`e[38;2;204;36;29m"      # bright red #cc241d
    InlinePrediction       = "`e[38;2;124;111;100m"    # fg4  #7c6f64
    ListPrediction         = "`e[38;2;146;131;116m"    # gray #928374
    ListPredictionSelected = "`e[38;2;124;111;100m"    # fg4  #7c6f64
    Selection              = "`e[38;2;124;111;100m"    # fg4  #7c6f64
    ContinuationPrompt     = "`e[38;2;146;131;116m"    # gray #928374
  }
}
Remove-Variable _bgKind

# Fish-like inline suggestions
Set-PSReadLineOption -PredictionSource History
Set-PSReadLineOption -PredictionViewStyle InlineView
Set-PSReadLineOption -HistorySearchCursorMovesToEnd

# Fish-like prefix history on arrows
Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward
Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward

# Track state for double-Tab to show matches (like bash).
$script:_tabLastInsert = $null
$script:_tabLastCursor = -1

# Tab completion (common prefix like Linux shells, forward slashes, no .\)
Set-PSReadLineKeyHandler -Key Tab -ScriptBlock {
    param($key, $arg)

    $line = $null
    $cursor = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)

    # Ask PowerShell for completions against the current buffer.
    $result = [System.Management.Automation.CommandCompletion]::CompleteInput($line, $cursor, $null)
    if (-not $result -or $result.CompletionMatches.Count -eq 0) { return }

    # Helper: normalize a completion text -- strip leading .\ ./ and use /
    $normalize = {
        param($s)
        $s = $s -replace '^(["'']?)\.[\\/]', '$1'
        $s.Replace('\', '/')
    }

    $matches = $result.CompletionMatches
    $replStart = $result.ReplacementIndex
    $replLen   = $result.ReplacementLength

    # Filter to completions whose normalized text starts with what was typed.
    # CompleteInput can return outliers (e.g. module-qualified names like
    # Microsoft.PowerShell.Management\Remove-Item) that break the common
    # prefix computation. Normalize slashes before comparing so that
    # forward-slash input matches backslash completions.
    $typed = $line.Substring($replStart, $replLen)
    if ($typed.Length -gt 0) {
        $typedNorm = $typed.Replace('\', '/')
        $filtered = @($matches | Where-Object { ($_.CompletionText.Replace('\', '/')) -like "$typedNorm*" })
        if ($filtered.Count -gt 0) { $matches = $filtered }
    }

    if ($matches.Count -eq 1) {
        # Unambiguous: insert the single match directly.
        $insert = & $normalize $matches[0].CompletionText
        # If it's a directory and doesn't already end with /, append one.
        $bare = $insert.Trim("'`"")
        if ($bare -and (Test-Path -LiteralPath $bare -PathType Container) -and -not $insert.EndsWith('/')) {
            $insert += '/'
        }
        $script:_tabLastInsert = $null
        $script:_tabLastCursor = -1
    } else {
        # Multiple matches: compute longest common prefix (case-insensitive).
        $normalized = @($matches | ForEach-Object { & $normalize $_.CompletionText })
        $prefix = $normalized[0]
        foreach ($m in $normalized[1..($normalized.Count - 1)]) {
            $len = [Math]::Min($prefix.Length, $m.Length)
            $common = 0
            for ($i = 0; $i -lt $len; $i++) {
                if ([char]::ToLowerInvariant($prefix[$i]) -eq [char]::ToLowerInvariant($m[$i])) {
                    $common++
                } else {
                    break
                }
            }
            $prefix = $prefix.Substring(0, $common)
        }
        $insert = $prefix
    }

    # Replace the original token region with the clean result in one shot.
    [Microsoft.PowerShell.PSConsoleReadLine]::Replace($replStart, $replLen, $insert)
    $newCursor = $replStart + $insert.Length
    [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($newCursor)

    # If ambiguous: first Tab inserts prefix, second Tab shows matches.
    if ($matches.Count -gt 1) {
        if ($script:_tabLastInsert -eq $insert -and $script:_tabLastCursor -eq $newCursor) {
            # Second consecutive Tab on same prefix -- show matches.
            [Microsoft.PowerShell.PSConsoleReadLine]::PossibleCompletions()
            $script:_tabLastInsert = $null
            $script:_tabLastCursor = -1
        } else {
            # First Tab -- just remember what we inserted.
            $script:_tabLastInsert = $insert
            $script:_tabLastCursor = $newCursor
        }
    }
}

Set-PSReadLineOption -HistorySaveStyle SaveIncrementally
Set-PSReadLineOption -HistoryNoDuplicates
Set-PSReadLineOption -MaximumHistoryCount 5000

# Skip writing sensitive commands to history
Set-PSReadLineOption -AddToHistoryHandler {
    param($line)

    if ([string]::IsNullOrWhiteSpace($line)) { return $false }

    # Block obvious secret-bearing patterns
    $sensitive = @(
        '(?i)\b(password|passwd|pwd|token|apikey|api_key|secret|clientsecret)\b',
        '(?i)\b(ConvertTo-SecureString|Get-Credential|New-Object\s+PSCredential)\b',
        '(?i)\bAuthorization:\s*Bearer\b',
        '(?i)\b(aws_access_key_id|aws_secret_access_key)\b',
        '(?i)\bsetx?\s+.*(password|token|secret)\b'
    )

    foreach ($pattern in $sensitive) {
        if ($line -match $pattern) { return $false }
    }

    return $true
}

Set-PSReadLineKeyHandler -Key Ctrl+a -Function BeginningOfLine
Set-PSReadLineKeyHandler -Key Ctrl+e -Function EndOfLine
Set-PSReadLineKeyHandler -Key Ctrl+d -ScriptBlock { [System.Environment]::Exit(0) }
