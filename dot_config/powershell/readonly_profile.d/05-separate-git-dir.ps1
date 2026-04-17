# -- Separate-Git-Dir Repository Management ----------------------------------------
# These functions manage repositories cloned with git clone --separate-git-dir,
# where git metadata is stored under META_ROOT/<name>, the primary working copy
# lives under REPOS_ROOT/<name>, and additional worktrees are placed under
# TREES_ROOT/<name>/<worktree>.

function InitWithSeparateGitDir {
  # Initializes a repository with its .git directory stored separately.
  # Working copy -> REPOS_ROOT/<Name>, git metadata -> META_ROOT/<Name>.
  param(
    [Parameter(Mandatory)] [string] $Name
  )

  if (-not $env:REPOS_ROOT -or -not $env:META_ROOT) {
    throw "REPOS_ROOT and META_ROOT must both be set."
  }

  $metaDir = (Join-Path $env:META_ROOT  $Name).Replace('\', '/')
  $repoDir = (Join-Path $env:REPOS_ROOT $Name).Replace('\', '/')

  New-Item -ItemType Directory -Path $env:META_ROOT  -Force | Out-Null
  New-Item -ItemType Directory -Path $env:REPOS_ROOT -Force | Out-Null

  git init --separate-git-dir="$metaDir" $repoDir
  if ($LASTEXITCODE -ne 0) {
    Write-Error "git init failed (exit code $LASTEXITCODE)."
  }
}

function CloneWithSeparateGitDir {
  # Clones a repository with its .git directory stored separately.
  # Working copy -> REPOS_ROOT/<Name>, git metadata -> META_ROOT/<Name>.
  param(
    [Parameter(Mandatory)] [string] $Url,
    [string] $Name
  )

  if (-not $Name) {
    $Name = [IO.Path]::GetFileNameWithoutExtension($Url.Split('/')[-1])
  }

  if (-not $env:REPOS_ROOT -or -not $env:META_ROOT) {
    throw "REPOS_ROOT and META_ROOT must both be set."
  }

  $metaDir = (Join-Path $env:META_ROOT  $Name).Replace('\', '/')
  $repoDir = (Join-Path $env:REPOS_ROOT $Name).Replace('\', '/')

  New-Item -ItemType Directory -Path $env:META_ROOT  -Force | Out-Null
  New-Item -ItemType Directory -Path $env:REPOS_ROOT -Force | Out-Null

  git clone --separate-git-dir="$metaDir" $Url $repoDir
  if ($LASTEXITCODE -ne 0) {
    Write-Error "git clone failed (exit code $LASTEXITCODE)."
  }
}

function RemoveSeparateGitRepo {
  # Removes all artifacts for a repo: worktrees (TREES_ROOT/<Name>),
  # working copy (REPOS_ROOT/<Name>), and git metadata (META_ROOT/<Name>).
  # Prompts for confirmation before deleting.
  param(
    [Parameter(Mandatory)] [string] $Name
  )

  if (-not $env:REPOS_ROOT -or -not $env:META_ROOT -or -not $env:TREES_ROOT) {
    throw "REPOS_ROOT, META_ROOT, and TREES_ROOT must all be set."
  }

  $metaPath = (Join-Path $env:META_ROOT  $Name).Replace('\', '/')
  $repoPath = (Join-Path $env:REPOS_ROOT $Name).Replace('\', '/')
  $treePath = (Join-Path $env:TREES_ROOT $Name).Replace('\', '/')

  if (-not (Test-Path $repoPath) -and -not (Test-Path $metaPath) -and -not (Test-Path $treePath)) {
    Write-Error "Nothing found for '$Name' in configured roots."
    return
  }

  Write-Host "About to remove:"
  if (Test-Path $treePath) { Write-Host "  Worktrees:    $treePath" }
  if (Test-Path $repoPath) { Write-Host "  Working copy: $repoPath" }
  if (Test-Path $metaPath) { Write-Host "  Git metadata: $metaPath" }

  Read-Host "Press Enter to confirm or Ctrl+C to abort"

  try {
    if (Test-Path $treePath) { Remove-Item -LiteralPath $treePath -Recurse -Force -ErrorAction Stop }
    if (Test-Path $repoPath) { Remove-Item -LiteralPath $repoPath -Recurse -Force -ErrorAction Stop }
    if (Test-Path $metaPath) { Remove-Item -LiteralPath $metaPath -Recurse -Force -ErrorAction Stop }
    Write-Host "Removed '$Name'."
  } catch {
    Write-Error "Failed to remove: $_"
  }
}

function Get-RepoNames {
  # Tab-completion helper: lists repo directories under META_ROOT.
  param($commandName, $wordToComplete, $cursorPosition)

  if (-not $env:META_ROOT -or -not (Test-Path $env:META_ROOT)) { return }

  $names = Get-ChildItem -LiteralPath $env:META_ROOT -Directory -ErrorAction SilentlyContinue |
           Where-Object { $_.Name -like "$wordToComplete*" } |
           Select-Object -ExpandProperty Name

  if ($PSBoundParameters.ContainsKey('commandName')) {
    $names | ForEach-Object {
      [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
    }
  } else {
    $names
  }
}

function Get-WorktreeNames {
  # Tab-completion helper: lists worktree entries registered under
  # META_ROOT/<repoName>/worktrees.
  param($commandName, $wordToComplete, $cursorPosition, $repoName)

  if (-not $env:META_ROOT -or -not $repoName) { return }

  $worktreesDir = Join-Path $env:META_ROOT $repoName 'worktrees'
  if (-not (Test-Path $worktreesDir)) { return }

  $items = Get-ChildItem -LiteralPath $worktreesDir -Directory -ErrorAction SilentlyContinue | ForEach-Object {
    $gitdirFile = Join-Path $_.FullName 'gitdir'
    $display = if (Test-Path $gitdirFile) {
      (Get-Content -LiteralPath $gitdirFile -ErrorAction SilentlyContinue) -join ' '
    } else {
      $_.Name
    }
    [PSCustomObject]@{ Name = $_.Name; Display = $display }
  } | Where-Object { $_.Name -like "$wordToComplete*" }

  if ($PSBoundParameters.ContainsKey('commandName')) {
    $items | ForEach-Object {
      [System.Management.Automation.CompletionResult]::new($_.Name, $_.Name, 'ParameterValue', $_.Display)
    }
  } else {
    $items | Select-Object -ExpandProperty Name
  }
}

function AddWorktreeInSeparateGitDir {
  # Adds a git worktree for a separately-stored-git-dir repo.
  # Relative WorktreePath values resolve under TREES_ROOT/<RepoName>/.
  # On success, changes the current directory to the new worktree.
  param(
    [Parameter(Mandatory)] [string] $RepoName,
    [Parameter(Mandatory)] [string] $WorktreePath,
    [string] $Ref = 'HEAD'
  )

  if (-not $env:TREES_ROOT -or -not $env:META_ROOT -or -not $env:REPOS_ROOT) {
    throw "TREES_ROOT, META_ROOT, and REPOS_ROOT must all be set."
  }

  $metaDir = (Join-Path $env:META_ROOT  $RepoName).Replace('\', '/')
  $repoDir = (Join-Path $env:REPOS_ROOT $RepoName).Replace('\', '/')

  if (-not (Test-Path $metaDir) -and -not (Test-Path $repoDir)) {
    throw "Repository '$RepoName' not found under META_ROOT or REPOS_ROOT."
  }

  # Resolve target: relative names land under TREES_ROOT/<RepoName>/
  if ([System.IO.Path]::IsPathRooted($WorktreePath)) {
    $target = $WorktreePath.Replace('\', '/')
  } else {
    $target = (Join-Path $env:TREES_ROOT $RepoName $WorktreePath).Replace('\', '/')
  }

  if (Test-Path $target) {
    Write-Error "Cannot create worktree: target '$target' already exists."
    return
  }

  New-Item -ItemType Directory -Path (Split-Path $target -Parent) -Force | Out-Null

  # All paths are absolute, so git can run from any directory
  git --git-dir="$metaDir" worktree add "$target" $Ref
  if ($LASTEXITCODE -ne 0) {
    Write-Error "git worktree add failed (exit code $LASTEXITCODE)."
    return
  }

  Set-Location -Path $target
}

function RemoveWorktreeInSeparateGitDir {
  # Removes a git worktree for a separately-stored-git-dir repo.
  # Verifies the worktree is registered before removing unless -Force is given.
  # -Force also bypasses git's dirty-worktree check and skips delete confirmation.
  param(
    [Parameter(Mandatory)] [string] $RepoName,
    [Parameter(Mandatory)] [string] $WorktreePathOrName,
    [switch] $Force
  )

  if (-not $env:TREES_ROOT -or -not $env:META_ROOT) {
    throw "TREES_ROOT and META_ROOT must both be set."
  }

  $metaDir = (Join-Path $env:META_ROOT $RepoName).Replace('\', '/')

  # Resolve to an absolute, normalized path
  if ([System.IO.Path]::IsPathRooted($WorktreePathOrName)) {
    $targetFull = [System.IO.Path]::GetFullPath($WorktreePathOrName).Replace('\', '/')
  } else {
    $targetFull = [System.IO.Path]::GetFullPath((Join-Path $env:TREES_ROOT $RepoName $WorktreePathOrName)).Replace('\', '/')
  }

  # Verify the worktree is registered under META_ROOT/<RepoName>/worktrees.
  # Each subdirectory there has a 'gitdir' file pointing to the worktree's .git file.
  $worktreesDir = Join-Path $metaDir 'worktrees'
  $registered = $false

  if (Test-Path $worktreesDir) {
    foreach ($wt in Get-ChildItem -LiteralPath $worktreesDir -Directory -ErrorAction SilentlyContinue) {
      $gitdirFile = Join-Path $wt.FullName 'gitdir'
      if (-not (Test-Path $gitdirFile)) { continue }
      $content = (Get-Content -LiteralPath $gitdirFile -Raw -ErrorAction SilentlyContinue)
      if (-not $content) { continue }

      # The gitdir file contains the path to <worktree>/.git -- strip that suffix and compare
      $wtPath = $content.Trim().Replace('\', '/') -replace '/\.git$', ''
      if ($wtPath -eq $targetFull.TrimEnd('/')) {
        $registered = $true
        break
      }
    }
  }

  if (-not $registered) {
    if (-not $Force.IsPresent) {
      Write-Error "Worktree '$WorktreePathOrName' (resolved: $targetFull) is not registered for repo '$RepoName'."
      return
    }
    # Not registered but -Force: skip git worktree remove, just clean up directories
    Write-Warning "Worktree not registered; removing directories directly."
    if (Test-Path $targetFull) {
      Remove-Item -LiteralPath $targetFull -Recurse -Force -ErrorAction Stop
      Write-Host "Removed '$targetFull'."
    } else {
      Write-Host "Nothing to remove (directory does not exist)."
    }
    return
  }

  # Build git arguments; --force bypasses dirty-worktree safety check
  $gitArgs = @('--git-dir', $metaDir, 'worktree', 'remove')
  if ($Force.IsPresent) { $gitArgs += '--force' }
  $gitArgs += $targetFull

  & git @gitArgs
  if ($LASTEXITCODE -ne 0) {
    Write-Error "git worktree remove failed (exit code $LASTEXITCODE)."
  }

  # Clean up leftover files if git didn't fully remove the directory
  if (Test-Path $targetFull) {
    Remove-Item -LiteralPath $targetFull -Recurse -Force:$Force.IsPresent -Confirm:(-not $Force.IsPresent) -ErrorAction SilentlyContinue
  }
}

# -- Argument completers -------------------------------------------------------

Register-ArgumentCompleter -CommandName AddWorktreeInSeparateGitDir -ParameterName RepoName -ScriptBlock {
  param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
  Get-RepoNames $commandName $wordToComplete $null
}

Register-ArgumentCompleter -CommandName RemoveWorktreeInSeparateGitDir -ParameterName RepoName -ScriptBlock {
  param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
  Get-RepoNames $commandName $wordToComplete $null
}

Register-ArgumentCompleter -CommandName RemoveWorktreeInSeparateGitDir -ParameterName WorktreePathOrName -ScriptBlock {
  param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

  # Determine repo name from already-bound parameters if available
  $repoName = $null
  if ($fakeBoundParameters.ContainsKey('RepoName')) { $repoName = $fakeBoundParameters['RepoName'] }

  # Fall back to inferring from the first positional argument
  if (-not $repoName) {
    $tokens = $commandAst.CommandElements |
      Where-Object { $_ -is [System.Management.Automation.Language.StringConstantExpressionAst] } |
      ForEach-Object { $_.Value }
    if ($tokens.Count -ge 2) { $repoName = $tokens[1] }
  }

  if ($repoName) {
    Get-WorktreeNames $commandName $wordToComplete $null $repoName
  } else {
    # No repo context yet: offer top-level dirs under TREES_ROOT as candidates
    $treesRoot = $env:TREES_ROOT
    if ($treesRoot -and (Test-Path $treesRoot)) {
      Get-ChildItem -LiteralPath $treesRoot -Directory -Recurse -Depth 1 -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like "$wordToComplete*" } |
        ForEach-Object { [System.Management.Automation.CompletionResult]::new($_.Name, $_.Name, 'ParameterValue', $_.FullName) }
    }
  }
}

function ListSeparateGitRepos {
  # Lists all repos, their working copies, and worktrees.
  # If RepoName is given, only shows worktrees for that repo.
  param(
    [string] $RepoName
  )

  if (-not $env:META_ROOT) {
    throw "META_ROOT must be set."
  }

  if (-not (Test-Path $env:META_ROOT)) {
    Write-Host "No repos found (META_ROOT does not exist)."
    return
  }

  $repos = Get-ChildItem -LiteralPath $env:META_ROOT -Directory -ErrorAction SilentlyContinue
  if ($RepoName) {
    $repos = $repos | Where-Object { $_.Name -eq $RepoName }
    if (-not $repos) {
      Write-Error "Repository '$RepoName' not found under META_ROOT."
      return
    }
  }

  foreach ($repo in $repos) {
    $name = $repo.Name
    $repoPath = if ($env:REPOS_ROOT) { (Join-Path $env:REPOS_ROOT $name).Replace('\', '/') } else { $null }
    $repoExists = $repoPath -and (Test-Path $repoPath)

    Write-Host "`e[38;2;142;192;124m$name`e[0m"
    if ($repoExists) {
      Write-Host "  working copy: $repoPath"
    }
    Write-Host "  git metadata: $($repo.FullName.Replace('\', '/'))"

    # List worktrees from git; replace the meta path with the working copy
    # path for the main branch so the output shows usable locations.
    $worktrees = git --git-dir="$($repo.FullName)" worktree list 2>$null
    if ($worktrees) {
      Write-Host "  worktrees:"
      $metaNorm = $repo.FullName.Replace('\', '/')
      foreach ($wt in $worktrees) {
        if ($repoExists -and $wt.StartsWith($metaNorm)) {
          $wt = $wt -replace [regex]::Escape($metaNorm), $repoPath
        }
        Write-Host "    $wt"
      }
    }
    Write-Host ""
  }
}

Register-ArgumentCompleter -CommandName ListSeparateGitRepos -ParameterName RepoName -ScriptBlock {
  param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
  Get-RepoNames $commandName $wordToComplete $null
}

# -- Aliases -------------------------------------------------------------------

Set-Alias Init-Repo       InitWithSeparateGitDir
Set-Alias Clone-Repo      CloneWithSeparateGitDir
Set-Alias Remove-Repo     RemoveSeparateGitRepo
Set-Alias Add-Worktree    AddWorktreeInSeparateGitDir
Set-Alias Remove-Worktree RemoveWorktreeInSeparateGitDir
Set-Alias List-Repos      ListSeparateGitRepos
