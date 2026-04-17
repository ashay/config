# Git branch/tag completion for common git subcommands (no external module)
Register-ArgumentCompleter -Native -CommandName git -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    # Parse tokens from current command line
    $tokens = @($commandAst.CommandElements | ForEach-Object { $_.Extent.Text })
    if ($tokens.Count -lt 2) { return }

    $subcommand = $tokens[1].ToLowerInvariant()
    $refCommands = @(
        'checkout', 'switch', 'merge', 'rebase', 'cherry-pick',
        'branch', 'show', 'diff', 'log', 'restore'
    )

    if ($subcommand -in $refCommands) {
        # Local branches, remotes, and tags
        $refs = git for-each-ref --format='%(refname:short)' refs/heads refs/remotes refs/tags 2>$null
        if (-not $refs) { return }

        $refs |
            Sort-Object -Unique |
            Where-Object { $_ -like "$wordToComplete*" } |
            ForEach-Object {
                [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
            }
    }
}
