<#
.SYNOPSIS
    Moves the tag of every major version, such as v1, to the newest release of that version.

.DESCRIPTION
    A workflow names the action as Gijsreyn/ghost-deploy-action@v1. It gets the newest release of version 1
    only when the tag v1 points at that release. semantic-release makes the tag of the release itself, such as
    v1.4.2, and nothing else. This script moves v1 along.

    It reads the tags of the form v<major>.<minor>.<patch> and takes the highest one of every major version.
    The tag v<major> is then made to point at the same commit, here and on the remote. A tag that points there
    already is left alone, so the script can run after every push, whether that push was released or not.

    The commit that is checked out plays no part. A run for an older commit cannot move a tag back. A
    pre-release such as v2.0.0-beta.1 is not counted.

.EXAMPLE
    ./build/Update-MajorTag.ps1 -WhatIf

    Says which tags would move, and changes nothing.

.EXAMPLE
    ./build/Update-MajorTag.ps1

    Moves the tags and pushes them to origin. The workflow CI runs this after semantic-release.
#>
#Requires -Version 7.4
[CmdletBinding(SupportsShouldProcess)]
[OutputType([pscustomobject])]
param(
    # The folder of the repository. Defaults to the repository that this script is in.
    [string] $Path = (Split-Path -Path $PSScriptRoot -Parent),

    # The remote to push the tags to.
    [string] $Remote = 'origin'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$InformationPreference = 'Continue'

$repository = (Resolve-Path -LiteralPath $Path).ProviderPath

# Runs git in the repository and stops when it fails.
$git = {
    $output = & git -C $repository @args 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "git $($args -join ' ') failed: $($output -join ' ')"
    }
    $output
}

$tags = @(& $git tag --list | ForEach-Object { [string] $_ })

# The newest release of every major version. A number never starts with a zero, as Semantic Versioning says.
$newest = @{}
foreach ($tag in $tags) {
    if ($tag -cnotmatch '^v(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$') {
        continue
    }
    $version = [version] $tag.Substring(1)
    if (-not $newest.ContainsKey($version.Major) -or $version -gt $newest[$version.Major]) {
        $newest[$version.Major] = $version
    }
}

foreach ($major in $newest.Keys | Sort-Object) {
    $name = "v$major"
    $release = "v$($newest[$major])"
    $target = [string] (& $git rev-parse --verify ('refs/tags/{0}^{{commit}}' -f $release))
    $current = if ($tags -ccontains $name) {
        [string] (& $git rev-parse --verify ('refs/tags/{0}^{{commit}}' -f $name))
    }

    $moved = $false
    if ($current -ne $target -and $PSCmdlet.ShouldProcess($name, "Point at $release")) {
        & $git tag --force $name $target | Out-Null
        & $git push --force $Remote "refs/tags/$name" | Out-Null
        $moved = $true
        Write-Information -MessageData "The tag $name now points at $release."
    }

    [pscustomobject]@{
        Tag     = $name
        Release = $release
        Commit  = $target
        Moved   = $moved
    }
}
