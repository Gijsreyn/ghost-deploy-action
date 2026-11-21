<#
.SYNOPSIS
    Makes a git repository with the commits that a test needs.

.DESCRIPTION
    The action compares the files of a run with those of an earlier commit. To test that, a test needs a
    repository with a known history. This script makes one in a folder that the test gives it.

    Every commit is described by a table. The key Write holds the files to write, as path and text. The key
    Remove holds the paths to remove. Paths are written with forward slashes, from the root of the repository.

    The repository gets its own name and address for the commits, signs nothing and leaves line endings as
    they are. The settings of the machine have no say in it that way, so the test gives the same result
    everywhere.

.EXAMPLE
    $commits = ./tests/New-TestRepository.ps1 -Path $folder -Commit @{ Write = @{ 'posts/a.md' = 'Text' } }

    Makes a repository with one commit that has the file posts/a.md, and returns the id of that commit.

.EXAMPLE
    ./tests/New-TestRepository.ps1 -Path $folder -Commit $first, @{ Remove = 'posts/a.md' }

    Makes a repository with two commits, the second of which removes a file, and returns both ids in order.
#>
#Requires -Version 7.4
[CmdletBinding()]
[OutputType([string[]])]
param(
    # The folder to make the repository in. It is created when it is not there.
    [Parameter(Mandatory)]
    [string] $Path,

    # The commits, in order.
    [Parameter(Mandatory)]
    [System.Collections.IDictionary[]] $Commit
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Runs git in the repository and stops when it fails.
$git = {
    $output = & git -C $Path @args 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "git $($args -join ' ') failed: $($output -join ' ')"
    }
    $output
}

New-Item -Path $Path -ItemType Directory -Force | Out-Null
if (-not (Test-Path -LiteralPath (Join-Path -Path $Path -ChildPath '.git'))) {
    & $git init --quiet --initial-branch main | Out-Null
    & $git config user.name 'Test' | Out-Null
    & $git config user.email 'test@example.com' | Out-Null
    & $git config commit.gpgsign false | Out-Null
    & $git config core.autocrlf false | Out-Null
}

$encoding = [System.Text.UTF8Encoding]::new($false)
$number = 0

foreach ($change in $Commit) {
    $number++

    if ($change.Keys -contains 'Write') {
        foreach ($name in $change['Write'].Keys) {
            $file = Join-Path -Path $Path -ChildPath $name
            New-Item -Path (Split-Path -Path $file -Parent) -ItemType Directory -Force | Out-Null
            [System.IO.File]::WriteAllText($file, [string] $change['Write'][$name], $encoding)
        }
    }
    if ($change.Keys -contains 'Remove') {
        foreach ($name in @($change['Remove'])) {
            Remove-Item -LiteralPath (Join-Path -Path $Path -ChildPath $name) -Recurse -Force
        }
    }

    & $git add --all | Out-Null
    & $git commit --quiet --allow-empty --message "Commit $number" | Out-Null
    [string] (& $git rev-parse HEAD)
}
