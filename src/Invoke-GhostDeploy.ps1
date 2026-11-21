<#
.SYNOPSIS
    Deploys the theme, tags, pages and posts of a repository to a Ghost site.

.DESCRIPTION
    This is the script that action.yml runs. It reads the inputs of the action from the environment, loads the
    PowerShell module Ghost, and lets the Sync commands of that module do the work:

    1. Sync-GhostTheme uploads and activates the theme, when the site does not show it yet.
    2. Sync-GhostTag creates and updates the tags. They go first, so that a post never creates a tag with
       nothing but a name.
    3. Sync-GhostPage does the same for the pages.
    4. Sync-GhostPost does the same for the posts.

    A kind without an input is skipped. Every command only changes what differs from its file.

    With the input delete, the run also removes the posts, pages and tags whose file was removed. The files are
    compared with an earlier commit for that, see Resolve-BaseCommit. A run that would remove more than the
    input delete-limit allows stops before anything is sent.

    With the input dry-run nothing is changed. The commands then report what they would do.

    The run ends with a summary on the page of the run and with the outputs of the action, see
    Write-DeployReport. The script exits with 1 when something failed and with 0 otherwise.

    The inputs are environment variables that start with GHOST_DEPLOY_, see Get-DeployInput. The script takes no
    parameters, so that the key of the site is never part of a command line.

.EXAMPLE
    ./src/Invoke-GhostDeploy.ps1

    Deploys what the variables GHOST_DEPLOY_API_URL, GHOST_DEPLOY_API_KEY and, for example, GHOST_DEPLOY_POSTS
    describe.
#>
#Requires -Version 7.4
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$InformationPreference = 'Continue'

# Git writes file names as UTF-8, whatever the code page of the machine is.
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
}
catch {
    Write-Verbose -Message "The encoding of the console was left as it is: $($_.Exception.Message)"
}

# Every other script in this folder holds one function with the name of its file.
$functions = Get-ChildItem -LiteralPath $PSScriptRoot -File |
    Where-Object { $_.Extension -eq '.ps1' -and $_.FullName -ne $PSCommandPath } |
    Sort-Object -Property Name
foreach ($function in $functions) {
    . $function.FullName
}

# A group folds a part of the log on the page of a run. Outside a workflow it is a heading.
$inWorkflow = $env:GITHUB_ACTIONS -eq 'true'
$startGroup = {
    param([string] $Title)

    $line = if ($inWorkflow) { "::group::$Title" } else { "`n$Title" }
    Write-Information -MessageData $line
}
$endGroup = {
    if ($inWorkflow) {
        Write-Information -MessageData '::endgroup::'
    }
}

$exitCode = 0
$failed = $false
$dryRun = $false
$connected = $false
$site = $null
$workFolder = $null
$rows = [System.Collections.Generic.List[object]]::new()
$root = (Get-Location).ProviderPath

try {
    $deploy = Get-DeployInput
    $dryRun = $deploy.DryRun

    # The key is in a secure string now. Git and the other programs this script starts do not need it.
    Remove-Item -Path 'Env:GHOST_DEPLOY_API_KEY' -ErrorAction SilentlyContinue

    $temp = if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { [System.IO.Path]::GetTempPath() }
    $workFolder = Join-Path -Path $temp -ChildPath ('ghost-deploy-{0}' -f [guid]::NewGuid().ToString('N'))
    New-Item -Path $workFolder -ItemType Directory | Out-Null

    $load = @{
        Version     = $deploy.ModuleVersion
        Path        = $deploy.ModulePath
        Destination = Join-Path -Path $workFolder -ChildPath 'modules'
    }
    $module = Import-GhostModule @load
    Write-Information -MessageData "The module Ghost $($module.Version) does the work."

    $connection = Connect-Ghost -Url $deploy.ApiUrl -AdminApiKey $deploy.ApiKey
    $connected = $true
    $site = [string] $connection.Title
    $mode = if ($dryRun) { 'This is a dry run. Nothing is changed.' } else { 'This run changes the site.' }
    Write-Information -MessageData "Connected to $($connection.Url) ($site, Ghost $($connection.Version)). $mode"

    # The kinds of content, in the order they are sent in.
    $kinds = @(
        @{ Kind = 'Tag'; Name = 'tags'; Path = $deploy.Tags; Command = 'Sync-GhostTag'; Recurse = $false }
        @{ Kind = 'Page'; Name = 'pages'; Path = $deploy.Pages; Command = 'Sync-GhostPage'; Recurse = $true }
        @{ Kind = 'Post'; Name = 'posts'; Path = $deploy.Posts; Command = 'Sync-GhostPost'; Recurse = $true }
    ) | Where-Object { $_.Path }
    $kinds = @($kinds)

    # The files as they were before, for the kinds that had files then.
    $previous = @{}
    if ($deploy.Delete -and $kinds.Count -gt 0) {
        $repository = (Get-ExistingFolder -Path $kinds[0].Path).Folder
        $base = Resolve-BaseCommit -Repository $repository -BaseRef $deploy.BaseRef

        if ($base.Commit) {
            Write-Information -MessageData $base.Reason
            $deleted = @()
            foreach ($kind in $kinds) {
                $export = @{
                    Path        = $kind.Path
                    Commit      = $base.Commit
                    Destination = Join-Path -Path $workFolder -ChildPath "previous-$($kind.Name)"
                }
                $earlier = Export-PreviousFile @export
                if ($earlier.Path) {
                    $previous[$kind.Kind] = $earlier.Path
                }
                $deleted += @($earlier.Deleted)
            }

            if ($deleted.Count -gt $deploy.DeleteLimit) {
                $shown = @($deleted | Select-Object -First 10)
                $list = $shown -join ', '
                if ($deleted.Count -gt $shown.Count) {
                    $list = "$list and $($deleted.Count - $shown.Count) more"
                }
                $what = "$($deleted.Count) files were removed since commit $($base.Commit): $list"
                $limit = "The input delete-limit allows $($deploy.DeleteLimit)."
                $advice = 'Give delete-limit a higher number for this run when that is what you want.'
                throw "$what. $limit $advice Nothing was changed."
            }
        }
        else {
            Write-DeployMessage -Level notice -Message $base.Reason
        }
    }

    # Every folder has to be there before anything is sent.
    foreach ($kind in $kinds) {
        $kind['Current'] = $kind.Path
        if (Test-Path -LiteralPath $kind.Path -PathType Container) {
            continue
        }
        if (-not $previous.ContainsKey($kind.Kind)) {
            throw "The input $($kind.Name) names the folder '$($kind.Path)', which does not exist."
        }

        # Every file of the folder was removed, and git keeps no empty folder.
        $empty = Join-Path -Path $workFolder -ChildPath "empty-$($kind.Name)"
        New-Item -Path $empty -ItemType Directory | Out-Null
        $kind['Current'] = $empty
    }

    if ($deploy.Theme) {
        & $startGroup 'Theme'
        try {
            $arguments = @{
                Path    = $deploy.Theme
                WhatIf  = $dryRun
                Confirm = $false
            }
            if ($deploy.ThemeName) {
                $arguments['Name'] = $deploy.ThemeName
            }
            $result = @(Sync-GhostTheme @arguments | ConvertTo-DeployRow -Kind 'Theme' -Root $root)
            $rows.AddRange($result)
            $table = $result | Format-Table -Property Action, Name, File -AutoSize | Out-String -Width 200
            Write-Information -MessageData $table.TrimEnd()
        }
        finally {
            & $endGroup
        }
    }

    foreach ($kind in $kinds) {
        & $startGroup ($kind.Name.Substring(0, 1).ToUpperInvariant() + $kind.Name.Substring(1))
        try {
            $arguments = @{
                Path    = $kind.Current
                WhatIf  = $dryRun
                Confirm = $false
            }
            if ($kind.Recurse) {
                $arguments['Recurse'] = $true
            }
            $convert = @{
                Kind = $kind.Kind
                Root = $root
            }
            if ($previous.ContainsKey($kind.Kind)) {
                $arguments['PreviousPath'] = $previous[$kind.Kind]
                $convert['PreviousRoot'] = $previous[$kind.Kind]
                $convert['PreviousName'] = $kind.Path
            }

            # The warnings of the command come along with its results, so that they can be shown on the page
            # of the run.
            $output = @(& $kind.Command @arguments 3>&1)
            foreach ($warning in $output | Where-Object { $_ -is [System.Management.Automation.WarningRecord] }) {
                Write-DeployMessage -Level warning -Message $warning.Message
            }
            $result = @(
                $output |
                    Where-Object { $_ -isnot [System.Management.Automation.WarningRecord] } |
                    ConvertTo-DeployRow @convert
            )
            $rows.AddRange($result)

            if ($result.Count -gt 0) {
                $table = $result | Format-Table -Property Action, Name, Slug, File -AutoSize | Out-String -Width 200
                Write-Information -MessageData $table.TrimEnd()
            }
            else {
                Write-Information -MessageData 'No files.'
            }
        }
        finally {
            & $endGroup
        }
    }
}
catch {
    $failed = $true
    $exitCode = 1
    Write-DeployMessage -Level error -Message $_.Exception.Message
}
finally {
    try {
        $numbers = Write-DeployReport -Row $rows.ToArray() -Site $site -DryRun:$dryRun -Failed:$failed
        $verbs = if ($dryRun) { 'To create', 'to update', 'to remove' } else { 'Created', 'updated', 'removed' }
        $text = '{0}: {1}, {2}: {3}, {4}: {5}. Unchanged: {6}.'
        $values = $verbs[0], $numbers.Created, $verbs[1], $numbers.Updated, $verbs[2], $numbers.Removed
        Write-Information -MessageData ($text -f ($values + $numbers.Unchanged))
    }
    catch {
        $exitCode = 1
        Write-DeployMessage -Level error -Message "The report could not be written. $($_.Exception.Message)"
    }

    if ($connected) {
        Disconnect-Ghost
    }
    if ($workFolder -and (Test-Path -LiteralPath $workFolder)) {
        Remove-Item -LiteralPath $workFolder -Recurse -Force -ErrorAction SilentlyContinue
    }
}

exit $exitCode
