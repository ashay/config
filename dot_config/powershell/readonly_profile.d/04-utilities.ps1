function Convert-ToUnix {
    param(
        [Parameter(Mandatory = $true, ValueFromRemainingArguments = $true)]
        [string[]]$Path
    )

    foreach ($p in $Path) {
        $full = Resolve-Path $p -ErrorAction Stop
        $text = [System.IO.File]::ReadAllText($full)
        $text = $text -replace "`r`n", "`n"
        [System.IO.File]::WriteAllText($full, $text, (New-Object System.Text.UTF8Encoding($false)))
    }
}

Set-Alias dos2unix Convert-ToUnix

function prompt {
  $path = $ExecutionContext.SessionState.Path.CurrentLocation.Path
  # Full path in terminal title for context
  $Host.UI.RawUI.WindowTitle = $path
  # Build the path label
  if ($path.Length -le 3) {
    $label = $path
  } else {
    $parts = $path.Split('\')
    $label = "$($parts[-2])/$($parts[-1])"
  }
  # Path on line above the prompt, right-aligned, dimmed
  $width = $Host.UI.RawUI.WindowSize.Width
  $pad = [Math]::Max(0, $width - $label.Length)
  "`e[90m$(' ' * $pad)$label`e[0m`n>_ "
}

# Tell PSReadLine the prompt has an extra line so redraws work correctly.
Set-PSReadLineOption -ExtraPromptLineCount 1

try {
  gpgconf --launch gpg-agent | Out-Null
  gpg-connect-agent /bye | Out-Null
} catch {}
