#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.0.0' }
<#
    Tests for the script that action.yml runs. Every test starts the script in a process of its own, the way a
    workflow does, with its inputs in the environment. The module Ghost is replaced by the stand-in in
    tests/Stubs/Ghost, which writes down every call it gets and returns what the test tells it to.

    The tests run in a repository that tests/New-TestRepository.ps1 makes below the test drive. Its second
    commit removes the only page, which is the case that needs the earlier files.
#>

BeforeAll {
    $script:Entry = Join-Path -Path $PSScriptRoot -ChildPath '../../src/Invoke-GhostDeploy.ps1'
    $script:Stub = (Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '../Stubs/Ghost')).ProviderPath
    $script:PowerShell = (Get-Process -Id $PID).Path
    $script:Encoding = [System.Text.UTF8Encoding]::new($false)

    $markdown = "---`ntitle: Title`n---`n`nText.`n"
    $script:Repository = Join-Path -Path $TestDrive -ChildPath 'repository'
    $first = @{
        Write = @{
            'theme/package.json'   = '{ "name": "my-theme", "version": "1.0.0" }'
            'tags/news.md'         = "---`nname: News`n---`n"
            'pages/about/index.md' = $markdown
            'posts/hello/index.md' = $markdown
            'posts/second.md'      = $markdown
            'posts/third.md'       = $markdown
        }
    }
    $second = @{
        Remove = 'pages', 'posts/second.md'
    }
    $new = Join-Path -Path $PSScriptRoot -ChildPath '../New-TestRepository.ps1'
    $script:Commits = @(& $new -Path $script:Repository -Commit $first, $second)

    # The inputs of a run that deploys every kind. A test changes the ones it is about.
    $script:Inputs = @{
        API_URL        = 'https://ghost.test'
        API_KEY        = 'abcdef:0123456789'
        THEME          = 'theme'
        TAGS           = 'tags'
        PAGES          = ''
        POSTS          = 'posts'
        MODULE_PATH    = $script:Stub
        MODULE_VERSION = ''
    }

    # Runs the script in a process of its own and returns what it did: the exit code, the text it wrote, the
    # calls the stand-in got, the outputs of the action and the summary.
    $script:Invoke = {
        param(
            [hashtable] $Change = @{},
            [hashtable] $Plan = @{},
            [string] $EventName = 'workflow_dispatch',
            [hashtable] $EventDetails = @{},
            [switch] $InWorkflow
        )

        $run = Join-Path -Path $TestDrive -ChildPath ('run-{0}' -f [guid]::NewGuid().ToString('N'))
        New-Item -Path $run -ItemType Directory | Out-Null
        $files = @{
            Log     = Join-Path -Path $run -ChildPath 'log.jsonl'
            Plan    = Join-Path -Path $run -ChildPath 'plan.json'
            Event   = Join-Path -Path $run -ChildPath 'event.json'
            Output  = Join-Path -Path $run -ChildPath 'output.txt'
            Summary = Join-Path -Path $run -ChildPath 'summary.md'
        }
        [System.IO.File]::WriteAllText($files.Plan, (ConvertTo-Json -InputObject $Plan -Depth 6), $script:Encoding)
        [System.IO.File]::WriteAllText($files.Event, (ConvertTo-Json -InputObject $EventDetails), $script:Encoding)

        # The environment of the child. Everything a real workflow sets is set here as well, so that the tests
        # give the same result in a workflow as on a machine of your own.
        $workflow = if ($InWorkflow) { 'true' } else { '' }
        $environment = @{
            GITHUB_ACTIONS      = $workflow
            GITHUB_EVENT_NAME   = $EventName
            GITHUB_EVENT_PATH   = $files.Event
            GITHUB_OUTPUT       = $files.Output
            GITHUB_STEP_SUMMARY = $files.Summary
            RUNNER_TEMP         = $run
            GHOST_STUB_LOG      = $files.Log
            GHOST_STUB_PLAN     = $files.Plan
        }
        $names = 'API_URL', 'API_KEY', 'THEME', 'THEME_NAME', 'TAGS', 'PAGES', 'POSTS', 'DELETE', 'DELETE_LIMIT',
        'BASE_REF', 'DRY_RUN', 'MODULE_VERSION', 'MODULE_PATH'
        foreach ($name in $names) {
            $value = ''
            if ($Change.ContainsKey($name)) {
                $value = $Change[$name]
            }
            elseif ($script:Inputs.ContainsKey($name)) {
                $value = $script:Inputs[$name]
            }
            $environment["GHOST_DEPLOY_$name"] = $value
        }

        $before = @{}
        foreach ($name in $environment.Keys) {
            $before[$name] = [System.Environment]::GetEnvironmentVariable($name)
            [System.Environment]::SetEnvironmentVariable($name, [string] $environment[$name])
        }
        Push-Location -LiteralPath $script:Repository
        try {
            $text = & $script:PowerShell -NoProfile -NonInteractive -File $script:Entry 2>&1 | Out-String
            $exitCode = $LASTEXITCODE
        }
        finally {
            Pop-Location
            foreach ($name in $before.Keys) {
                [System.Environment]::SetEnvironmentVariable($name, $before[$name])
            }
        }

        $calls = @()
        if (Test-Path -LiteralPath $files.Log) {
            $calls = @(
                [System.IO.File]::ReadAllLines($files.Log) |
                    Where-Object { $_ } |
                    ForEach-Object { ConvertFrom-Json -InputObject $_ }
            )
        }
        $outputs = @{}
        if (Test-Path -LiteralPath $files.Output) {
            foreach ($line in [System.IO.File]::ReadAllLines($files.Output)) {
                $name, $value = $line -split '=', 2
                $outputs[$name] = $value
            }
        }
        $summary = ''
        if (Test-Path -LiteralPath $files.Summary) {
            $summary = [System.IO.File]::ReadAllText($files.Summary)
        }

        [pscustomobject]@{
            ExitCode = $exitCode
            Text     = $text
            Calls    = $calls
            Outputs  = $outputs
            Summary  = $summary
            Leftover = @(Get-ChildItem -LiteralPath $run -Directory)
        }
    }
}

AfterAll {
    # Git makes the files of its objects read-only, which Pester cannot delete on Windows.
    Get-ChildItem -LiteralPath $TestDrive -Force | Remove-Item -Recurse -Force
}

Describe 'Invoke-GhostDeploy' -Tag 'Unit' {
    Context 'a run that deploys' {
        It 'connects, runs the theme, the tags and the posts in that order, and disconnects' {
            $result = & $script:Invoke

            $result.ExitCode | Should -Be 0 -Because $result.Text
            $result.Calls.Command |
                Should -Be 'Connect-Ghost', 'Sync-GhostTheme', 'Sync-GhostTag', 'Sync-GhostPost', 'Disconnect-Ghost'
        }

        It 'runs the pages between the tags and the posts when they are given' {
            $result = & $script:Invoke -Change @{ PAGES = 'posts' }

            $result.Calls.Command |
                Should -Be 'Connect-Ghost', 'Sync-GhostTheme', 'Sync-GhostTag', 'Sync-GhostPage', 'Sync-GhostPost',
                'Disconnect-Ghost'
        }

        It 'skips a kind without an input' {
            $result = & $script:Invoke -Change @{ THEME = ''; TAGS = '' }

            $result.ExitCode | Should -Be 0 -Because $result.Text
            $result.Calls.Command | Should -Be 'Connect-Ghost', 'Sync-GhostPost', 'Disconnect-Ghost'
        }

        It 'connects with the address and the key of the inputs' {
            $result = & $script:Invoke

            $connect = $result.Calls | Where-Object { $_.Command -eq 'Connect-Ghost' }
            $connect.Url | Should -Be 'https://ghost.test'
            $connect.KeyLength | Should -Be 'abcdef:0123456789'.Length
        }

        It 'never writes the key, and takes it out of the environment before a command runs' {
            $result = & $script:Invoke

            $result.Text | Should -Not -BeLike '*0123456789*'
            $result.Summary | Should -Not -BeLike '*0123456789*'
            $result.Calls.KeyInEnv | Select-Object -Unique | Should -Be $false
        }

        It 'changes the site in a real run, and never asks for confirmation' {
            $result = & $script:Invoke

            $sync = @($result.Calls | Where-Object { $_.Command -like 'Sync-*' })
            $sync.Count | Should -Be 3
            $sync.DryRun | Select-Object -Unique | Should -Be $false
            $sync.Confirm | Select-Object -Unique | Should -Be 'None'
        }

        It 'passes the dry run on to every command, because the -WhatIf of a script does not reach a module' {
            $result = & $script:Invoke -Change @{ DRY_RUN = 'true'; PAGES = 'posts' }

            $sync = @($result.Calls | Where-Object { $_.Command -like 'Sync-*' })
            $sync.Count | Should -Be 4
            $sync.DryRun | Select-Object -Unique | Should -Be $true
            $result.Text | Should -BeLike '*This is a dry run. Nothing is changed.*'
        }

        It 'reads the folders below a folder for pages and posts, and not for tags' {
            $result = & $script:Invoke -Change @{ PAGES = 'posts' }

            ($result.Calls | Where-Object { $_.Command -eq 'Sync-GhostPage' }).Recurse | Should -BeTrue
            ($result.Calls | Where-Object { $_.Command -eq 'Sync-GhostPost' }).Recurse | Should -BeTrue
            ($result.Calls | Where-Object { $_.Command -eq 'Sync-GhostTag' }).PSObject.Properties['Recurse'] |
                Should -BeNullOrEmpty
        }

        It 'stores the theme under the name of the input theme-name' {
            $result = & $script:Invoke -Change @{ THEME_NAME = 'preview' }

            ($result.Calls | Where-Object { $_.Command -eq 'Sync-GhostTheme' }).Name | Should -Be 'preview'
        }

        It 'removes its folder of the run when it is done' {
            $result = & $script:Invoke

            $result.Leftover | Should -BeNullOrEmpty
        }
    }

    Context 'the report' {
        BeforeAll {
            $script:Plan = @{
                'Sync-GhostTheme' = @(
                    @{ Action = 'Updated'; Name = 'my-theme'; Version = '1.0.0'; File = '' }
                )
                'Sync-GhostTag'   = @(
                    @{ Action = 'Unchanged'; Name = 'News'; Slug = 'news'; File = 'news.md' }
                )
                'Sync-GhostPost'  = @(
                    @{ Action = 'Created'; Title = 'Hello'; Slug = 'hello'; Status = 'draft'; File = 'hello/index.md' }
                    @{ Action = 'Unchanged'; Title = 'Third'; Slug = 'third'; Status = 'draft'; File = 'third.md' }
                )
            }
        }

        It 'sets the outputs of the action' {
            $result = & $script:Invoke -Plan $script:Plan

            $result.Outputs['created'] | Should -Be '1'
            $result.Outputs['updated'] | Should -Be '1'
            $result.Outputs['removed'] | Should -Be '0'
            $result.Outputs['unchanged'] | Should -Be '2'
            $result.Outputs['changed'] | Should -Be 'true'
        }

        It 'writes the summary, with the path of every file as it is in the repository' {
            $result = & $script:Invoke -Plan $script:Plan

            $result.Summary | Should -BeLike '*The files were deployed to `*`*Stub site`*`*.*'
            $result.Summary | Should -BeLike '*| Theme | Updated | my-theme 1.0.0 |  | theme |*'
            $result.Summary | Should -BeLike '*| Post | Created | Hello | hello | posts/hello/index.md |*'
            $result.Summary | Should -Not -BeLike '*third.md*'
        }

        It 'shows what every command returned in the log' {
            $result = & $script:Invoke -Plan $script:Plan

            $result.Text | Should -BeLike '*Created*Hello*hello*posts/hello/index.md*'
            $result.Text | Should -BeLike '*Created: 1, updated: 1, removed: 0. Unchanged: 2.*'
        }

        It 'shows a warning of a command' {
            $plan = @{ Warning = @{ 'Sync-GhostTag' = 'A tag file could not be read.' } }

            $result = & $script:Invoke -Plan $plan

            $result.ExitCode | Should -Be 0 -Because $result.Text
            $result.Text | Should -BeLike '*Warning: A tag file could not be read.*'
        }
    }

    Context 'a run that fails' {
        It 'stops at the command that fails, reports what was done until then, and exits with 1' {
            $plan = @{
                'Sync-GhostTheme' = @(@{ Action = 'Updated'; Name = 'my-theme'; Version = '1.0.0'; File = '' })
                Fail              = 'Sync-GhostTag'
            }

            $result = & $script:Invoke -Plan $plan

            $result.ExitCode | Should -Be 1
            $result.Calls.Command | Should -Be 'Connect-Ghost', 'Sync-GhostTheme', 'Sync-GhostTag', 'Disconnect-Ghost'
            $result.Text | Should -BeLike '*Error: Sync-GhostTag failed*'
            $result.Summary | Should -BeLike '*stopped with an error*| Theme | Updated |*'
            $result.Outputs['updated'] | Should -Be '1'
            $result.Leftover | Should -BeNullOrEmpty
        }

        It 'fails before it connects when the key is empty' {
            $result = & $script:Invoke -Change @{ API_KEY = '' }

            $result.ExitCode | Should -Be 1
            $result.Calls | Should -BeNullOrEmpty
            $result.Text | Should -BeLike '*Error: The input api-key is empty*fork*'
        }

        It 'fails before a command runs for a folder that does not exist' {
            $result = & $script:Invoke -Change @{ PAGES = 'no-such-folder' }

            $result.ExitCode | Should -Be 1
            $result.Calls.Command | Should -Be 'Connect-Ghost', 'Disconnect-Ghost'
            $expected = "*Error: The input pages names the folder 'no-such-folder', which does not exist.*"
            $result.Text | Should -BeLike $expected
        }
    }

    Context 'files that were removed, with the input delete' {
        It 'gives every command the files as they were in the commit of base-ref' {
            $change = @{ DELETE = 'true'; BASE_REF = 'HEAD~1'; PAGES = 'pages' }

            $result = & $script:Invoke -Change $change

            $result.ExitCode | Should -Be 0 -Because $result.Text
            $tags = $result.Calls | Where-Object { $_.Command -eq 'Sync-GhostTag' }
            $tags.HasPrevious | Should -BeTrue
            $tags.PreviousFiles | Should -Be 'news.md'
            $posts = $result.Calls | Where-Object { $_.Command -eq 'Sync-GhostPost' }
            $posts.PreviousFiles | Should -Be 'hello/index.md', 'second.md', 'third.md'
            $posts.Files | Should -Be 'hello/index.md', 'third.md'
            $result.Text | Should -BeLike "*compared with commit $($script:Commits[0])*"
        }

        It 'gives a command an empty folder when every file of its kind was removed' {
            $change = @{ DELETE = 'true'; BASE_REF = 'HEAD~1'; PAGES = 'pages' }

            $result = & $script:Invoke -Change $change

            $pages = $result.Calls | Where-Object { $_.Command -eq 'Sync-GhostPage' }
            $pages.Files | Should -BeNullOrEmpty
            $pages.PreviousFiles | Should -Be 'about/index.md'
        }

        It 'reports a removed page with the path its file had in the repository' {
            $change = @{ DELETE = 'true'; BASE_REF = 'HEAD~1'; PAGES = 'pages'; DRY_RUN = 'true' }
            $plan = @{
                'Sync-GhostPage' = @(
                    @{
                        Action   = 'WouldRemove'
                        Title    = 'About'
                        Slug     = 'about'
                        File     = 'about/index.md'
                        Previous = $true
                    }
                )
            }

            $result = & $script:Invoke -Change $change -Plan $plan

            $result.Outputs['removed'] | Should -Be '1'
            $result.Summary | Should -BeLike '*| Page | Would remove | About | about | pages/about/index.md |*'
        }

        It 'takes the commit before a push when base-ref is not given' {
            $change = @{ DELETE = 'true'; PAGES = 'pages' }
            $details = @{ before = $script:Commits[0]; after = $script:Commits[1] }

            $result = & $script:Invoke -Change $change -EventName 'push' -EventDetails $details

            $result.ExitCode | Should -Be 0 -Because $result.Text
            $pages = $result.Calls | Where-Object { $_.Command -eq 'Sync-GhostPage' }
            $pages.PreviousFiles | Should -Be 'about/index.md'
        }

        It 'removes nothing and says why when the run has no commit to compare with' {
            $result = & $script:Invoke -Change @{ DELETE = 'true' }

            $result.ExitCode | Should -Be 0 -Because $result.Text
            $result.Text | Should -BeLike '*Notice: This run has no commit to compare with (event: workflow_dispatch)*'
            $content = $result.Calls | Where-Object { $_.Command -in 'Sync-GhostTag', 'Sync-GhostPost' }
            $content.HasPrevious | Select-Object -Unique | Should -Be $false
        }

        It 'gives no earlier files without the input delete' {
            $result = & $script:Invoke -Change @{ BASE_REF = 'HEAD~1' }

            ($result.Calls | Where-Object { $_.Command -eq 'Sync-GhostPost' }).HasPrevious | Should -BeFalse
        }

        It 'stops before a command runs when more files were removed than delete-limit allows' {
            $change = @{ DELETE = 'true'; BASE_REF = 'HEAD~1'; PAGES = 'pages'; DELETE_LIMIT = '1' }

            $result = & $script:Invoke -Change $change

            $result.ExitCode | Should -Be 1
            $result.Calls.Command | Should -Be 'Connect-Ghost', 'Disconnect-Ghost'
            $expected = '*Error: 2 files were removed since commit*delete-limit allows 1*Nothing was changed.*'
            $result.Text | Should -BeLike $expected
            $result.Text | Should -BeLike '*pages/about/index.md*'
            $result.Text | Should -BeLike '*posts/second.md*'
        }

        It 'goes on when the number of removed files is exactly the limit' {
            $change = @{ DELETE = 'true'; BASE_REF = 'HEAD~1'; PAGES = 'pages'; DELETE_LIMIT = '2' }

            (& $script:Invoke -Change $change).ExitCode | Should -Be 0
        }

        It 'fails before a command runs when the commit to compare with cannot be found' {
            $change = @{ DELETE = 'true'; BASE_REF = ('f' * 40) }

            $result = & $script:Invoke -Change $change

            $result.ExitCode | Should -Be 1
            $result.Calls.Command | Should -Be 'Connect-Ghost', 'Disconnect-Ghost'
            $result.Text | Should -BeLike '*Error: The commit to compare with*fetch-depth: 0*'
        }
    }

    Context 'in a workflow' {
        It 'writes a group per kind, so that GitHub can fold the log' {
            $result = & $script:Invoke -InWorkflow

            $groups = '*::group::Theme*::endgroup::*::group::Tags*::endgroup::*::group::Posts*::endgroup::*'
            $result.Text | Should -BeLike $groups
        }

        It 'writes an error as a workflow command, so that GitHub shows it on the page of the run' {
            $result = & $script:Invoke -Change @{ API_KEY = '' } -InWorkflow

            $result.ExitCode | Should -Be 1
            $result.Text | Should -BeLike '*::error title=Deploy to Ghost::The input api-key is empty*'
        }

        It 'closes a group when the command in it fails' {
            $result = & $script:Invoke -Plan @{ Fail = 'Sync-GhostTag' } -InWorkflow

            $expected = '*::group::Tags*::endgroup::*::error title=Deploy to Ghost::Sync-GhostTag failed*'
            $result.Text | Should -BeLike $expected
        }
    }
}
