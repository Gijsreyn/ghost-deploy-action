#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.0.0' }
<#
    Tests for the scripts that ask git something: Invoke-Git, Get-ExistingFolder, Resolve-BaseCommit and
    Export-PreviousFile. They run against repositories that tests/New-TestRepository.ps1 makes below the test
    drive, so nothing outside that folder is read or changed.
#>

BeforeAll {
    foreach ($name in 'Invoke-Git', 'Get-ExistingFolder', 'Resolve-BaseCommit', 'Export-PreviousFile') {
        . "$PSScriptRoot/../../src/$name.ps1"
    }
    $script:NewRepository = Join-Path -Path $PSScriptRoot -ChildPath '../New-TestRepository.ps1'

    # Git writes file names as UTF-8. The script of the action sets this as well.
    $script:ConsoleEncoding = [Console]::OutputEncoding
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8

    # A name with an accented letter, written as a code point to keep this file ASCII.
    $script:Accented = 'caf{0} one.md' -f [char] 0x00E9

    # The text of a Markdown file with a title.
    $script:Markdown = {
        param([string] $Title)

        "---`ntitle: $Title`n---`n`nText.`n"
    }

    # A repository with a folder of content and two commits. The second commit removes two posts.
    $script:Repository = Join-Path -Path $TestDrive -ChildPath 'repository'
    $first = @{
        Write = @{
            'site/posts/a.md'               = & $script:Markdown 'A'
            "site/posts/$script:Accented"   = & $script:Markdown 'Accented'
            'site/posts/kept.md'            = & $script:Markdown 'Kept'
            'site/posts/x/index.md'         = & $script:Markdown 'X'
            'site/posts/x/images/cover.png' = 'not really a picture'
            'site/posts/README.md'          = 'What this folder is for.'
            'site/pages/about/index.md'     = & $script:Markdown 'About'
            'site/pages/README.md'          = 'What this folder is for.'
            'site/notes/[draft]/idea.md'    = & $script:Markdown 'Idea'
            'site/empty/picture.png'        = 'not really a picture'
        }
    }
    $second = @{
        Remove = 'site/posts/a.md', "site/posts/$script:Accented", 'site/pages', 'site/posts/README.md'
        Write  = @{ 'site/posts/new.md' = & $script:Markdown 'New' }
    }
    $script:Commits = @(& $script:NewRepository -Path $script:Repository -Commit $first, $second)
}

AfterAll {
    [Console]::OutputEncoding = $script:ConsoleEncoding

    # Git makes the files of its objects read-only, which Pester cannot delete on Windows.
    Get-ChildItem -LiteralPath $TestDrive -Force | Remove-Item -Recurse -Force
}

Describe 'Invoke-Git' -Tag 'Unit' {
    It 'returns the exit code and the lines that git wrote' {
        $result = Invoke-Git -Path $script:Repository -ArgumentList 'rev-parse', 'HEAD'

        $result.ExitCode | Should -Be 0
        $result.Output | Should -Be $script:Commits[1]
    }

    It 'returns the exit code and the message of a command that fails, without throwing' {
        $result = Invoke-Git -Path $script:Repository -ArgumentList 'cat-file', '-e', 'HEAD:site/missing'

        $result.ExitCode | Should -Not -Be 0
        $result.Output -join ' ' | Should -BeLike '*site/missing*'
    }

    It 'returns a file name with a character outside ASCII as it is' {
        $result = Invoke-Git -Path $script:Repository -ArgumentList 'ls-tree', '-r', '--name-only', 'HEAD~1'

        $result.Output | Should -Contain "site/posts/$script:Accented"
    }
}

Describe 'Get-ExistingFolder' -Tag 'Unit' {
    It 'returns a folder that exists, with nothing missing' {
        $result = Get-ExistingFolder -Path (Join-Path -Path $script:Repository -ChildPath 'site/posts')

        $result.Folder | Should -Be (Join-Path -Path $script:Repository -ChildPath 'site/posts')
        $result.Missing | Should -BeNullOrEmpty
    }

    It 'walks up to the first folder that exists and returns the names it passed' {
        $result = Get-ExistingFolder -Path (Join-Path -Path $script:Repository -ChildPath 'site/pages/about')

        $result.Folder | Should -Be (Join-Path -Path $script:Repository -ChildPath 'site')
        $result.Missing | Should -Be 'pages', 'about'
    }

    It 'reads a path from the working directory' {
        Push-Location -LiteralPath $script:Repository
        try {
            $result = Get-ExistingFolder -Path 'site/posts/'

            $result.Folder | Should -Be (Join-Path -Path (Get-Location).ProviderPath -ChildPath 'site/posts')
        }
        finally {
            Pop-Location
        }
    }
}

Describe 'Resolve-BaseCommit' -Tag 'Unit' {
    BeforeAll {
        # Writes the details of an event to a file, as GitHub does, and returns its path.
        $script:WriteEvent = {
            param([hashtable] $Details)

            $path = Join-Path -Path $TestDrive -ChildPath ('event-{0}.json' -f [guid]::NewGuid().ToString('N'))
            $json = ConvertTo-Json -InputObject $Details -Depth 5
            [System.IO.File]::WriteAllText($path, $json, [System.Text.UTF8Encoding]::new($false))
            $path
        }
    }

    It 'takes the input base-ref over the event, and resolves a name to a commit' {
        $eventFile = & $script:WriteEvent @{ before = $script:Commits[1] }
        $resolve = @{
            Repository = $script:Repository
            BaseRef    = 'HEAD~1'
            EventName  = 'push'
            EventPath  = $eventFile
        }

        $result = Resolve-BaseCommit @resolve

        $result.Commit | Should -Be $script:Commits[0]
        $result.Reason | Should -BeLike "*$($script:Commits[0])*the input base-ref*"
    }

    It 'takes the commit before a push' {
        $eventFile = & $script:WriteEvent @{ before = $script:Commits[0]; after = $script:Commits[1] }

        $result = Resolve-BaseCommit -Repository $script:Repository -EventName 'push' -EventPath $eventFile

        $result.Commit | Should -Be $script:Commits[0]
        $result.Reason | Should -BeLike '*the commit before this push*'
    }

    It 'takes the branch that a pull request goes into' {
        $eventFile = & $script:WriteEvent @{ pull_request = @{ base = @{ sha = $script:Commits[0] } } }

        $result = Resolve-BaseCommit -Repository $script:Repository -EventName 'pull_request' -EventPath $eventFile

        $result.Commit | Should -Be $script:Commits[0]
    }

    It 'has no commit for <Name>, and says so' -ForEach @(
        @{ Name = 'the first push of a branch'; EventName = 'push'; Details = @{ before = '0' * 40 } }
        @{ Name = 'a push without a commit before it'; EventName = 'push'; Details = @{ after = 'abc' } }
        @{ Name = 'a run that was started by hand'; EventName = 'workflow_dispatch'; Details = @{ inputs = @{} } }
        @{ Name = 'a run on a schedule'; EventName = 'schedule'; Details = @{ schedule = '17 5 * * *' } }
    ) {
        $path = & $script:WriteEvent $Details

        $result = Resolve-BaseCommit -Repository $script:Repository -EventName $EventName -EventPath $path

        $result.Commit | Should -BeNullOrEmpty
        $result.Reason | Should -BeLike "*no commit to compare with (event: $EventName)*nothing is removed*base-ref*"
    }

    It 'has no commit without an event at all' {
        $result = Resolve-BaseCommit -Repository $script:Repository -EventName '' -EventPath ''

        $result.Commit | Should -BeNullOrEmpty
    }

    It 'fails for a commit that does not exist, with what to do about it' {
        $missing = 'f' * 40

        { Resolve-BaseCommit -Repository $script:Repository -BaseRef $missing -EventName '' -EventPath '' } |
            Should -Throw -ExpectedMessage "*'$missing' from the input base-ref*fetch-depth: 0*"
    }

    It 'fetches the commit when the clone has one commit only, as a workflow has' {
        # The repository of this file is the origin. Like GitHub, it hands out any commit that is asked for.
        & git -C $script:Repository config uploadpack.allowAnySHA1InWant true
        $clone = Join-Path -Path $TestDrive -ChildPath 'clone'
        $origin = 'file://{0}' -f $script:Repository.Replace('\', '/')
        & git clone --quiet --depth 1 $origin $clone 2>&1 | Out-Null
        (Invoke-Git -Path $clone -ArgumentList 'cat-file', '-e', $script:Commits[0]).ExitCode | Should -Not -Be 0

        $eventFile = & $script:WriteEvent @{ before = $script:Commits[0] }
        $result = Resolve-BaseCommit -Repository $clone -EventName 'push' -EventPath $eventFile

        $result.Commit | Should -Be $script:Commits[0]
        (Invoke-Git -Path $clone -ArgumentList 'cat-file', '-e', $script:Commits[0]).ExitCode | Should -Be 0
    }
}

Describe 'Export-PreviousFile' -Tag 'Unit' {
    BeforeAll {
        # The Markdown files below a folder, from that folder, with forward slashes and in order.
        $script:ListFiles = {
            param([string] $Folder)

            Get-ChildItem -LiteralPath $Folder -File -Recurse |
                ForEach-Object { [System.IO.Path]::GetRelativePath($Folder, $_.FullName).Replace('\', '/') } |
                Sort-Object
        }
        $script:Destination = {
            Join-Path -Path $TestDrive -ChildPath ('previous-{0}' -f [guid]::NewGuid().ToString('N'))
        }
    }

    BeforeEach {
        Push-Location -LiteralPath $script:Repository
    }

    AfterEach {
        Pop-Location
    }

    It 'writes the Markdown files of the folder as they were, and nothing else' {
        $result = Export-PreviousFile -Path 'site/posts' -Commit $script:Commits[0] -Destination (& $script:Destination)

        $result.Path | Should -Exist
        $expected = @('README.md', 'a.md', $script:Accented, 'kept.md', 'x/index.md') | Sort-Object
        & $script:ListFiles $result.Path | Should -Be $expected
        $text = [System.IO.File]::ReadAllText((Join-Path -Path $result.Path -ChildPath 'a.md'))
        $text | Should -BeExactly (& $script:Markdown 'A')
    }

    It 'lists the Markdown files that are gone since, without a README.md' {
        $result = Export-PreviousFile -Path 'site/posts' -Commit $script:Commits[0] -Destination (& $script:Destination)

        $result.Deleted | Sort-Object | Should -Be (@('site/posts/a.md', "site/posts/$script:Accented") | Sort-Object)
    }

    It 'works for a folder that is gone from the checkout, because its last file was removed' {
        Join-Path -Path $script:Repository -ChildPath 'site/pages' | Should -Not -Exist

        $result = Export-PreviousFile -Path 'site/pages' -Commit $script:Commits[0] -Destination (& $script:Destination)

        & $script:ListFiles $result.Path | Should -Be 'about/index.md', 'README.md'
        $result.Deleted | Should -Be 'site/pages/about/index.md'
    }

    It 'returns no folder when the commit did not have the folder' {
        $result = Export-PreviousFile -Path 'site/tags' -Commit $script:Commits[0] -Destination (& $script:Destination)

        $result.Path | Should -BeNullOrEmpty
        $result.Deleted | Should -BeNullOrEmpty
    }

    It 'returns an empty folder when the folder had no Markdown files' {
        $result = Export-PreviousFile -Path 'site/empty' -Commit $script:Commits[0] -Destination (& $script:Destination)

        $result.Path | Should -Exist
        & $script:ListFiles $result.Path | Should -BeNullOrEmpty
    }

    It 'takes a folder name with brackets as it is' {
        $export = @{
            Path        = 'site/notes/[draft]'
            Commit      = $script:Commits[0]
            Destination = & $script:Destination
        }

        $result = Export-PreviousFile @export

        & $script:ListFiles $result.Path | Should -Be 'idea.md'
    }

    It 'finds the repository of a folder that is below the working directory' {
        Pop-Location
        Push-Location -LiteralPath $TestDrive
        $export = @{
            Path        = 'repository/site/posts'
            Commit      = $script:Commits[0]
            Destination = & $script:Destination
        }

        $result = Export-PreviousFile @export

        & $script:ListFiles $result.Path | Should -Contain 'kept.md'
        $result.Deleted | Should -Contain 'site/posts/a.md'
    }

    It 'fails for a folder that is not in a repository' {
        $outside = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ([guid]::NewGuid().ToString('N'))
        New-Item -Path $outside -ItemType Directory | Out-Null
        try {
            { Export-PreviousFile -Path $outside -Commit $script:Commits[0] -Destination (& $script:Destination) } |
                Should -Throw -ExpectedMessage '*is not in a git repository*'
        }
        finally {
            Remove-Item -LiteralPath $outside -Recurse -Force
        }
    }
}
