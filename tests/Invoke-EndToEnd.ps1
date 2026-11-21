<#
.SYNOPSIS
    Tests the action against a Ghost site on this machine, with the example site.

.DESCRIPTION
    The unit tests run the script of the action against a stand-in for the module Ghost. This test uses the
    real module and a real Ghost site, so it shows that the theme of the example is accepted, that posts, pages
    and tags are created, updated and removed, and that a dry run changes nothing.

    The site is a Ghost site of its own, in the folder .local-ghost of this repository, which the module
    installs and starts. That takes a few minutes the first time. It is a site to throw away: nothing in this
    test goes to a site that somebody reads.

    The test follows the getting-started guide, with tests/Set-ExampleRepository.ps1:

    1. A dry run of the first deployment. Nothing is on the site afterwards.
    2. The first deployment. The theme, the tag, the page and the post are on the site.
    3. The same deployment again. Nothing changes.
    4. The second commit, without the input delete. The post and the theme are updated and the page stays.
    5. The same commit with delete, as a dry run. The page is reported and stays.
    6. The same commit with delete. The page is removed.
    7. The same once more. Nothing changes.
    8. The third commit with a delete-limit of 1. The run fails before it changes anything.
    9. The third commit with the usual limit. The tag and the post are removed.

    Every step starts the script of the action in a process of its own, with its inputs in the environment, the
    way action.yml does. What cannot be tested here is action.yml itself. Only GitHub runs that.

.EXAMPLE
    ./tests/Invoke-EndToEnd.ps1 -ModulePath ../ghost-sdk-powershell/Ghost

    Runs the test with the module from a checkout next to this repository.

.EXAMPLE
    ./tests/Invoke-EndToEnd.ps1 -KeepRunning

    Runs the test with the version of the module that action.yml names, and leaves the site running.
#>
#Requires -Version 7.4
[CmdletBinding()]
[OutputType([void])]
param(
    # The folder of a copy of the module Ghost. Without it the version that action.yml names is taken from the
    # PowerShell Gallery.
    [string] $ModulePath = $env:GHOST_MODULE_PATH,

    # The folder of the Ghost site of this test. Defaults to .local-ghost in the root of the repository.
    [string] $SitePath,

    # The port of the site.
    [ValidateRange(1024, 65535)]
    [int] $Port = 2372,

    # Leave the site running when the test is done. It starts faster the next time.
    [switch] $KeepRunning
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$InformationPreference = 'Continue'

$root = Split-Path -Path $PSScriptRoot -Parent
$entry = Join-Path -Path $root -ChildPath 'src/Invoke-GhostDeploy.ps1'
$setRepository = Join-Path -Path $PSScriptRoot -ChildPath 'Set-ExampleRepository.ps1'
$powershell = (Get-Process -Id $PID).Path
if (-not $SitePath) {
    $SitePath = Join-Path -Path $root -ChildPath '.local-ghost'
}

$run = [guid]::NewGuid().ToString('N').Substring(0, 8)
$work = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "ghost-deploy-e2e-$run"
New-Item -Path $work -ItemType Directory | Out-Null
$repository = Join-Path -Path $work -ChildPath 'site'

$slugs = @{
    Post = 'hello-from-a-repository'
    Page = 'about-this-example'
    Tag  = 'deploy-example'
}
$failures = [System.Collections.Generic.List[string]]::new()

# Compares what was found with what was expected, and remembers what differs.
$expect = {
    param([string] $What, $Actual, $Expected)

    if ("$Actual" -ceq "$Expected") {
        Write-Information -MessageData "  ok      $What"
    }
    else {
        Write-Information -MessageData "  FAILED  $What. Expected '$Expected' and found '$Actual'."
        $failures.Add($What)
    }
}

# The post, the page or the tag of the example on the site, or nothing.
$find = {
    param([string] $Kind)

    $filter = "slug:'$($slugs[$Kind])'"
    switch ($Kind) {
        'Post' { Get-GhostPost -Filter $filter }
        'Page' { Get-GhostPage -Filter $filter }
        'Tag' { Get-GhostTag -Filter $filter }
    }
}

$siteVariables = @{
    GHOST_ADMIN_API_URL = $env:GHOST_ADMIN_API_URL
    GHOST_ADMIN_API_KEY = $env:GHOST_ADMIN_API_KEY
}

try {
    # The module, from a folder or from the Gallery in the version that the action uses.
    if ($ModulePath) {
        $ModulePath = (Resolve-Path -LiteralPath $ModulePath).ProviderPath
    }
    else {
        $action = [System.IO.File]::ReadAllText((Join-Path -Path $root -ChildPath 'action.yml'))
        if ($action -notmatch "(?s)module-version:.*?default: '(?<version>[^']+)'") {
            throw 'The version of the module was not found in action.yml.'
        }
        $modules = Join-Path -Path $work -ChildPath 'modules'
        New-Item -Path $modules -ItemType Directory | Out-Null
        $save = @{
            Name            = 'Ghost'
            Version         = $Matches['version']
            Repository      = 'PSGallery'
            Path            = $modules
            TrustRepository = $true
        }
        Save-PSResource @save
        $ModulePath = Join-Path -Path $modules -ChildPath 'Ghost'
    }
    Import-Module -Name $ModulePath -Force
    Write-Information -MessageData "The module Ghost is loaded from $ModulePath."

    $site = Start-GhostLocalSite -Path $SitePath -Port $Port -Title 'Deploy action test'
    if ($site.Url -notmatch '^http://(localhost|127\.0\.0\.1)[:/]') {
        throw "The site of this test has to be on this machine, and it is $($site.Url)."
    }
    $key = [System.Net.NetworkCredential]::new('', [string] $site.AdminApiKey).SecurePassword
    Connect-Ghost -Url $site.Url -AdminApiKey $key | Out-Null

    # What an earlier run left behind.
    foreach ($post in @(& $find 'Post')) {
        Remove-GhostPost -Id $post.id -Confirm:$false
    }
    foreach ($page in @(& $find 'Page')) {
        Remove-GhostPage -Id $page.id -Confirm:$false
    }
    foreach ($tag in @(& $find 'Tag')) {
        Remove-GhostTag -Id $tag.id -Confirm:$false
    }

    # Runs the script of the action in the repository and returns its exit code, outputs, summary and text.
    $deploy = {
        param([hashtable] $Change = @{})

        $step = Join-Path -Path $work -ChildPath ('step-{0}' -f [guid]::NewGuid().ToString('N'))
        New-Item -Path $step -ItemType Directory | Out-Null
        $outputFile = Join-Path -Path $step -ChildPath 'output.txt'
        $summaryFile = Join-Path -Path $step -ChildPath 'summary.md'

        $environment = @{
            GITHUB_ACTIONS              = ''
            GITHUB_EVENT_NAME           = 'workflow_dispatch'
            GITHUB_EVENT_PATH           = ''
            GITHUB_OUTPUT               = $outputFile
            GITHUB_STEP_SUMMARY         = $summaryFile
            RUNNER_TEMP                 = $step
            GHOST_DEPLOY_API_URL        = $site.Url
            GHOST_DEPLOY_API_KEY        = $site.AdminApiKey
            GHOST_DEPLOY_THEME          = 'theme'
            GHOST_DEPLOY_THEME_NAME     = ''
            GHOST_DEPLOY_TAGS           = 'tags'
            GHOST_DEPLOY_PAGES          = 'pages'
            GHOST_DEPLOY_POSTS          = 'posts'
            GHOST_DEPLOY_DELETE         = ''
            GHOST_DEPLOY_DELETE_LIMIT   = ''
            GHOST_DEPLOY_BASE_REF       = ''
            GHOST_DEPLOY_DRY_RUN        = ''
            GHOST_DEPLOY_MODULE_VERSION = ''
            GHOST_DEPLOY_MODULE_PATH    = $ModulePath
        }
        foreach ($name in $Change.Keys) {
            $environment["GHOST_DEPLOY_$name"] = $Change[$name]
        }

        $before = @{}
        foreach ($name in $environment.Keys) {
            $before[$name] = [System.Environment]::GetEnvironmentVariable($name)
            [System.Environment]::SetEnvironmentVariable($name, [string] $environment[$name])
        }
        Push-Location -LiteralPath $repository
        try {
            $text = & $powershell -NoProfile -NonInteractive -File $entry 2>&1 | Out-String
            $exitCode = $LASTEXITCODE
        }
        finally {
            Pop-Location
            foreach ($name in $before.Keys) {
                [System.Environment]::SetEnvironmentVariable($name, $before[$name])
            }
        }
        Write-Information -MessageData ($text.TrimEnd() -replace '(?m)^', '      ')

        $outputs = @{ created = ''; updated = ''; removed = ''; unchanged = ''; changed = '' }
        if (Test-Path -LiteralPath $outputFile) {
            foreach ($line in [System.IO.File]::ReadAllLines($outputFile)) {
                $name, $value = $line -split '=', 2
                $outputs[$name] = $value
            }
        }
        $summary = ''
        if (Test-Path -LiteralPath $summaryFile) {
            $summary = [System.IO.File]::ReadAllText($summaryFile)
        }

        [pscustomobject]@{
            ExitCode = $exitCode
            Outputs  = $outputs
            Summary  = $summary
            Text     = $text
        }
    }

    # The numbers of a run as one text: created, updated, removed, unchanged.
    $numbers = {
        param($Result)

        '{0} {1} {2} {3}' -f $Result.Outputs.created, $Result.Outputs.updated, $Result.Outputs.removed,
        $Result.Outputs.unchanged
    }

    # The stylesheet that the site serves, which is that of the active theme.
    $stylesheet = {
        $address = '{0}/assets/css/screen.css?t={1}' -f $site.Url, [datetime]::UtcNow.Ticks
        [string] (Invoke-WebRequest -Uri $address -UseBasicParsing).Content
    }

    Write-Information -MessageData "`n1. A dry run of the first deployment"
    & $setRepository -Path $repository -Step First -Marker "run $run"
    $result = & $deploy @{ DRY_RUN = 'true' }
    & $expect 'the run succeeds' $result.ExitCode 0
    & $expect 'it would create the tag, the page and the post, and update the theme' (& $numbers $result) '3 1 0 0'
    & $expect 'the summary says that nothing was changed' ($result.Summary -like '*Nothing was changed*') $true
    & $expect 'the post is not on the site' @(& $find 'Post').Count 0
    & $expect 'the page is not on the site' @(& $find 'Page').Count 0
    & $expect 'the tag is not on the site' @(& $find 'Tag').Count 0
    & $expect 'the theme is not on the site' ((& $stylesheet) -like "*run $run*") $false

    Write-Information -MessageData "`n2. The first deployment"
    $result = & $deploy
    & $expect 'the run succeeds' $result.ExitCode 0
    & $expect 'it created the tag, the page and the post, and updated the theme' (& $numbers $result) '3 1 0 0'
    & $expect 'the output changed is true' $result.Outputs.changed 'true'
    $post = @(& $find 'Post') | Select-Object -First 1
    & $expect 'the post is a draft' $post.status 'draft'
    & $expect 'the post has its tag' ($post.tags.name -join ',') 'Deploy example'
    $uploaded = [string] $post.feature_image -like '*/content/images/*cover-*.png'
    & $expect 'the picture of the post was uploaded' $uploaded $true
    & $expect 'the page is on the site' @(& $find 'Page').Count 1
    $tag = @(& $find 'Tag') | Select-Object -First 1
    & $expect 'the tag has the description of its file' $tag.description 'Posts that came from the example repository.'
    & $expect 'the site shows the theme of this run' ((& $stylesheet) -like "*run $run*") $true
    $summaryRow = '*| Post | Created | Hello from a repository | hello-from-a-repository | posts/*index.md |*'
    & $expect 'the summary has a row for the post' ($result.Summary -like $summaryRow) $true

    Write-Information -MessageData "`n3. The same deployment again"
    $result = & $deploy
    & $expect 'the run succeeds' $result.ExitCode 0
    & $expect 'everything is unchanged' (& $numbers $result) '0 0 0 4'
    & $expect 'the output changed is false' $result.Outputs.changed 'false'

    Write-Information -MessageData "`n4. The second commit, without the input delete"
    & $setRepository -Path $repository -Step Second
    $result = & $deploy @{ BASE_REF = 'HEAD~1' }
    & $expect 'the run succeeds' $result.ExitCode 0
    & $expect 'the theme and the post are updated, and nothing is removed' (& $numbers $result) '0 2 0 1'
    & $expect 'the post is published' (@(& $find 'Post') | Select-Object -First 1).status 'published'
    & $expect 'the site shows the new colour of the theme' ((& $stylesheet) -like '*#b83280*') $true
    & $expect 'the page is still on the site' @(& $find 'Page').Count 1

    Write-Information -MessageData "`n5. The same commit with delete, as a dry run"
    $result = & $deploy @{ DELETE = 'true'; BASE_REF = 'HEAD~1'; DRY_RUN = 'true' }
    & $expect 'the run succeeds' $result.ExitCode 0
    & $expect 'it would remove the page' (& $numbers $result) '0 0 1 3'
    $summaryRow = '*| Page | Would remove | About this example | about-this-example | pages/*/index.md |*'
    & $expect 'the summary names the file the page had' ($result.Summary -like $summaryRow) $true
    & $expect 'the page is still on the site' @(& $find 'Page').Count 1

    Write-Information -MessageData "`n6. The same commit with delete"
    $result = & $deploy @{ DELETE = 'true'; BASE_REF = 'HEAD~1' }
    & $expect 'the run succeeds' $result.ExitCode 0
    & $expect 'it removed the page' (& $numbers $result) '0 0 1 3'
    & $expect 'the page is gone from the site' @(& $find 'Page').Count 0
    & $expect 'the post is still on the site' @(& $find 'Post').Count 1

    Write-Information -MessageData "`n7. The same once more"
    $result = & $deploy @{ DELETE = 'true'; BASE_REF = 'HEAD~1' }
    & $expect 'the run succeeds' $result.ExitCode 0
    & $expect 'nothing changes' (& $numbers $result) '0 0 0 3'

    Write-Information -MessageData "`n8. The third commit, with a delete-limit of 1"
    & $setRepository -Path $repository -Step Third
    $result = & $deploy @{ DELETE = 'true'; BASE_REF = 'HEAD~1'; DELETE_LIMIT = '1' }
    & $expect 'the run fails' $result.ExitCode 1
    & $expect 'the message names the limit' ($result.Text -like '*2 files were removed*delete-limit allows 1*') $true
    & $expect 'the post is still on the site' @(& $find 'Post').Count 1
    & $expect 'the tag is still on the site' @(& $find 'Tag').Count 1

    Write-Information -MessageData "`n9. The third commit, with the usual limit"
    $result = & $deploy @{ DELETE = 'true'; BASE_REF = 'HEAD~1' }
    & $expect 'the run succeeds' $result.ExitCode 0
    & $expect 'it removed the tag and the post' (& $numbers $result) '0 0 2 1'
    & $expect 'the post is gone from the site' @(& $find 'Post').Count 0
    & $expect 'the tag is gone from the site' @(& $find 'Tag').Count 0
}
finally {
    if (Get-Command -Name 'Disconnect-Ghost' -ErrorAction SilentlyContinue) {
        Disconnect-Ghost
    }
    if (-not $KeepRunning -and (Get-Command -Name 'Stop-GhostLocalSite' -ErrorAction SilentlyContinue)) {
        Stop-GhostLocalSite -Path $SitePath
    }
    foreach ($name in $siteVariables.Keys) {
        [System.Environment]::SetEnvironmentVariable($name, $siteVariables[$name])
    }
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failures.Count -gt 0) {
    throw "The end-to-end test failed: $($failures.Count) of its checks did not hold. See the lines marked FAILED."
}
Write-Information -MessageData "`nThe end-to-end test passed."
