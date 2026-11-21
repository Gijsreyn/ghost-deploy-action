#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.0.0' }
<#
    Tests for the scripts that say what a run did: ConvertTo-DeployRow, Write-DeployReport and
    Write-DeployMessage.
#>

BeforeAll {
    foreach ($name in 'ConvertTo-DeployRow', 'Write-DeployReport', 'Write-DeployMessage') {
        . "$PSScriptRoot/../../src/$name.ps1"
    }
}

Describe 'ConvertTo-DeployRow' -Tag 'Unit' {
    BeforeAll {
        $script:Root = Join-Path -Path $TestDrive -ChildPath 'repository'
        $script:Copy = Join-Path -Path $TestDrive -ChildPath 'run/previous-pages/files/pages'
    }

    It 'gives a post a row with its title, its slug and the path of its file in the repository' {
        $post = [pscustomobject]@{
            Action = 'Created'
            Status = 'draft'
            Slug   = 'hello'
            Title  = 'Hello'
            Id     = 'p1'
            Path   = Join-Path -Path $script:Root -ChildPath 'posts/2026-11-21-hello/index.md'
        }

        $row = $post | ConvertTo-DeployRow -Kind 'Post' -Root $script:Root

        $row.Kind | Should -Be 'Post'
        $row.Action | Should -Be 'Created'
        $row.Name | Should -Be 'Hello'
        $row.Slug | Should -Be 'hello'
        $row.File | Should -Be 'posts/2026-11-21-hello/index.md'
    }

    It 'gives a tag a row with its name' {
        $tag = [pscustomobject]@{
            Action = 'WouldUpdate'
            Name   = 'News'
            Slug   = 'news'
            Id     = 't1'
            Path   = Join-Path -Path $script:Root -ChildPath 'tags/news.md'
        }

        $row = $tag | ConvertTo-DeployRow -Kind 'Tag' -Root $script:Root

        $row.Name | Should -Be 'News'
        $row.Action | Should -Be 'WouldUpdate'
        $row.File | Should -Be 'tags/news.md'
    }

    It 'gives a theme a row with its name and version, and no slug' {
        $theme = [pscustomobject]@{
            Action      = 'Updated'
            Name        = 'my-theme'
            Version     = '1.2.0'
            Fingerprint = 'abc'
            Path        = Join-Path -Path $script:Root -ChildPath 'theme'
        }

        $row = $theme | ConvertTo-DeployRow -Kind 'Theme' -Root $script:Root

        $row.Name | Should -Be 'my-theme 1.2.0'
        $row.Slug | Should -BeNullOrEmpty
        $row.File | Should -Be 'theme'
    }

    It 'shows a file that is not below the working directory by its name' {
        $theme = [pscustomobject]@{
            Action      = 'WouldUpdate'
            Name        = 'my-theme'
            Version     = '1.2.0'
            Fingerprint = 'abc'
            Path        = Join-Path -Path $TestDrive -ChildPath 'runner-temp/theme/my-theme.zip'
        }

        $row = $theme | ConvertTo-DeployRow -Kind 'Theme' -Root $script:Root

        $row.File | Should -Be 'my-theme.zip'
    }

    It 'keeps the path of a folder whose name starts with two dots' {
        $post = [pscustomobject]@{
            Action = 'Unchanged'
            Slug   = 'hello'
            Title  = 'Hello'
            Path   = Join-Path -Path $script:Root -ChildPath '..drafts/hello/index.md'
        }

        ($post | ConvertTo-DeployRow -Kind 'Post' -Root $script:Root).File | Should -Be '..drafts/hello/index.md'
    }

    It 'turns the path of a removed page back into the path it had in the repository' {
        $page = [pscustomobject]@{
            Action = 'Removed'
            Slug   = 'about'
            Title  = 'About'
            Path   = Join-Path -Path $script:Copy -ChildPath 'about/index.md'
        }
        $convert = @{
            Kind         = 'Page'
            Root         = $script:Root
            PreviousRoot = $script:Copy
            PreviousName = 'site/pages'
        }

        $row = $page | ConvertTo-DeployRow @convert

        $row.File | Should -Be 'site/pages/about/index.md'
    }

    It 'leaves the path of a current file alone when there are earlier files as well' {
        $page = [pscustomobject]@{
            Action = 'Unchanged'
            Slug   = 'contact'
            Title  = 'Contact'
            Path   = Join-Path -Path $script:Root -ChildPath 'pages/contact/index.md'
        }
        $convert = @{
            Kind         = 'Page'
            Root         = $script:Root
            PreviousRoot = $script:Copy
            PreviousName = 'pages'
        }

        ($page | ConvertTo-DeployRow @convert).File | Should -Be 'pages/contact/index.md'
    }

    It 'returns a row for every result from the pipeline' {
        $results = 'a', 'b', 'c' | ForEach-Object {
            [pscustomobject]@{ Action = 'Unchanged'; Slug = $_; Title = $_; Path = $null }
        }

        @($results | ConvertTo-DeployRow -Kind 'Post' -Root $script:Root).Slug | Should -Be 'a', 'b', 'c'
    }
}

Describe 'Write-DeployReport' -Tag 'Unit' {
    BeforeAll {
        # A row as ConvertTo-DeployRow returns it.
        $script:NewRow = {
            param([string] $Kind, [string] $Action, [string] $Name, [string] $Slug, [string] $File)

            [pscustomobject]@{ Kind = $Kind; Action = $Action; Name = $Name; Slug = $Slug; File = $File }
        }
        $script:Rows = @(
            & $script:NewRow 'Theme' 'Updated' 'my-theme 1.0.0' '' 'theme'
            & $script:NewRow 'Tag' 'Unchanged' 'News' 'news' 'tags/news.md'
            & $script:NewRow 'Page' 'Removed' 'About' 'about' 'pages/about/index.md'
            & $script:NewRow 'Post' 'Created' 'Hello | world' 'hello' 'posts/hello/index.md'
            & $script:NewRow 'Post' 'Created' 'Second' 'second' 'posts/second.md'
            & $script:NewRow 'Post' 'Unchanged' 'Old' 'old' 'posts/old.md'
        )
    }

    BeforeEach {
        $script:Summary = Join-Path -Path $TestDrive -ChildPath ('summary-{0}.md' -f [guid]::NewGuid().ToString('N'))
        $script:Output = Join-Path -Path $TestDrive -ChildPath ('output-{0}.txt' -f [guid]::NewGuid().ToString('N'))
        $script:Report = @{
            SummaryPath = $script:Summary
            OutputPath  = $script:Output
        }
    }

    It 'returns how many were created, updated, removed and unchanged' {
        $report = $script:Report
        $result = Write-DeployReport -Row $script:Rows -Site 'My site' @report

        $result.Created | Should -Be 2
        $result.Updated | Should -Be 1
        $result.Removed | Should -Be 1
        $result.Unchanged | Should -Be 2
        $result.Changed | Should -BeTrue
    }

    It 'writes the same numbers as the outputs of the action' {
        $report = $script:Report
        Write-DeployReport -Row $script:Rows -Site 'My site' @report | Out-Null

        $lines = [System.IO.File]::ReadAllLines($script:Output)
        $lines | Should -Be 'created=2', 'updated=1', 'removed=1', 'unchanged=2', 'changed=true'
    }

    It 'adds to the file with the outputs and keeps what another step wrote' {
        [System.IO.File]::WriteAllText($script:Output, "earlier=1`n")
        $report = $script:Report
        Write-DeployReport -Row @() -Site 'My site' @report | Out-Null

        $lines = [System.IO.File]::ReadAllLines($script:Output)
        $lines[0] | Should -Be 'earlier=1'
        $lines[-1] | Should -Be 'changed=false'
    }

    It 'writes a summary with a row for everything that changed, and only a number for the rest' {
        $report = $script:Report
        Write-DeployReport -Row $script:Rows -Site 'My site' @report | Out-Null

        $text = [System.IO.File]::ReadAllText($script:Summary)
        $text | Should -BeLike '## Deploy to Ghost*The files were deployed to `*`*My site`*`*.*'
        $text | Should -BeLike '*Created: 2, updated: 1, removed: 1. Unchanged: 2.*'
        $text | Should -BeLike '*| Theme | Updated | my-theme 1.0.0 |  | theme |*'
        $text | Should -BeLike '*| Page | Removed | About | about | pages/about/index.md |*'
        $text | Should -Not -BeLike '*tags/news.md*'
        $text | Should -Not -BeLike '*posts/old.md*'
    }

    It 'keeps a bar in a title from starting a new cell' {
        $report = $script:Report
        Write-DeployReport -Row $script:Rows -Site 'My site' @report | Out-Null

        [System.IO.File]::ReadAllText($script:Summary) | Should -BeLike '*| Hello \| world | hello |*'
    }

    It 'says in a dry run that nothing was changed, and what a real run would do' {
        $rows = @(
            & $script:NewRow 'Post' 'WouldCreate' 'Hello' 'hello' 'posts/hello.md'
            & $script:NewRow 'Page' 'WouldRemove' 'About' 'about' 'pages/about/index.md'
            & $script:NewRow 'Theme' 'WouldUpdate' 'my-theme 1.0.0' '' 'theme'
        )
        $report = $script:Report
        $result = Write-DeployReport -Row $rows -Site 'My site' -DryRun @report

        $result.Created | Should -Be 1
        $result.Updated | Should -Be 1
        $result.Removed | Should -Be 1
        $text = [System.IO.File]::ReadAllText($script:Summary)
        $text | Should -BeLike '*dry run*Nothing was changed*'
        $text | Should -BeLike '*To create: 1, to update: 1, to remove: 1. Unchanged: 0.*'
        $text | Should -BeLike '*| Post | Would create | Hello |*'
        $text | Should -BeLike '*| Page | Would remove | About |*'
        $text | Should -BeLike '*| Theme | Would update | my-theme 1.0.0 |*'
    }

    It 'writes no table when nothing changed, and the output changed is false' {
        $rows = @(& $script:NewRow 'Post' 'Unchanged' 'Old' 'old' 'posts/old.md')
        $report = $script:Report
        $result = Write-DeployReport -Row $rows -Site 'My site' @report

        $result.Changed | Should -BeFalse
        [System.IO.File]::ReadAllText($script:Summary) | Should -Not -BeLike '*| Kind |*'
        [System.IO.File]::ReadAllLines($script:Output)[-1] | Should -Be 'changed=false'
    }

    It 'says that the run stopped when it failed' {
        $report = $script:Report
        Write-DeployReport -Row $script:Rows -Site 'My site' -Failed @report | Out-Null

        [System.IO.File]::ReadAllText($script:Summary) | Should -BeLike '*stopped with an error*This was done before*'
    }

    It 'writes nothing without the files of a workflow, and still returns the numbers' {
        $result = Write-DeployReport -Row $script:Rows -SummaryPath '' -OutputPath ''

        $result.Created | Should -Be 2
        $script:Summary | Should -Not -Exist
        $script:Output | Should -Not -Exist
    }
}

Describe 'Write-DeployMessage' -Tag 'Unit' {
    BeforeAll {
        $script:InWorkflow = $env:GITHUB_ACTIONS
    }

    AfterEach {
        $env:GITHUB_ACTIONS = $script:InWorkflow
    }

    It 'writes a workflow command in a workflow, as one line' {
        $env:GITHUB_ACTIONS = 'true'

        $line = Write-DeployMessage -Level 'error' -Message "100% wrong`r`nSecond line" 6>&1

        "$line" | Should -BeExactly '::error title=Deploy to Ghost::100%25 wrong%0D%0ASecond line'
    }

    It 'writes a <Level> as a plain line outside a workflow' -ForEach @(
        @{ Level = 'notice'; Expected = 'Notice: Something to know.' }
        @{ Level = 'warning'; Expected = 'Warning: Something to know.' }
        @{ Level = 'error'; Expected = 'Error: Something to know.' }
    ) {
        $env:GITHUB_ACTIONS = ''

        $line = Write-DeployMessage -Level $Level -Message 'Something to know.' 6>&1

        "$line" | Should -BeExactly $Expected
    }
}
