#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.0.0' }
<#
    Tests for the release of the action: build/Update-MajorTag.ps1, which moves the tag v1, and the settings of
    semantic-release in the folder release.

    semantic-release itself only runs in the workflow, after a push to main. What can be checked here is the
    script, against repositories that tests/New-TestRepository.ps1 makes below the test drive, and that the
    places that have to agree do so: the settings, the packages that the lock file installs, and the workflow.
    A plugin that is named but not installed would otherwise only show after a merge, as a release that fails.
#>

BeforeDiscovery {
    $root = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    $lines = [System.IO.File]::ReadAllLines((Join-Path -Path $root -ChildPath 'release/.releaserc.yml'))

    # The packages that the settings name: every plugin, and the preset under the name that npm knows it by.
    $script:Packages = @(
        foreach ($line in $lines) {
            if ($line -match "^  - '(?<plugin>[^']+)'") {
                @{ Package = $Matches['plugin'] }
            }
            elseif ($line -match '^preset: (?<preset>\S+)') {
                @{ Package = 'conventional-changelog-{0}' -f $Matches['preset'] }
            }
        }
    )
}

BeforeAll {
    $script:Root = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    $script:UpdateMajorTag = Join-Path -Path $script:Root -ChildPath 'build/Update-MajorTag.ps1'
    $script:NewRepository = Join-Path -Path $PSScriptRoot -ChildPath '../New-TestRepository.ps1'

    # The commit that a tag of a repository points at, or nothing when the repository has no such tag.
    $script:TagCommit = {
        param([string] $Repository, [string] $Tag)

        $commit = & git -C $Repository rev-parse --verify --quiet ('refs/tags/{0}^{{commit}}' -f $Tag)
        if ($LASTEXITCODE -eq 0) {
            [string] $commit
        }
    }

    # A repository that stands in for GitHub, with five commits and the given tags, and a clone of it as a
    # workflow has. Tags is a table of the name of a tag and the number of the commit that it points at.
    $script:NewRemoteAndClone = {
        param([System.Collections.IDictionary] $Tags)

        $folder = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString('N'))
        $remote = Join-Path -Path $folder -ChildPath 'remote'
        $clone = Join-Path -Path $folder -ChildPath 'clone'

        $changes = 1..5 | ForEach-Object { @{ Write = @{ 'file.txt' = "Text $_" } } }
        $commits = @(& $script:NewRepository -Path $remote -Commit $changes)
        foreach ($tag in $Tags.Keys) {
            & git -C $remote tag $tag $commits[$Tags[$tag]] | Out-Null
        }
        & git clone --quiet ('file://{0}' -f $remote.Replace('\', '/')) $clone 2>&1 | Out-Null

        @{ Remote = $remote; Clone = $clone; Commits = $commits }
    }

    # The releases of two major versions. The tag v1 is two releases behind, and there is no tag v2 yet.
    $script:Releases = @{
        'v1.0.0'        = 0
        'v1'            = 0
        'v1.2.0'        = 1
        'v1.10.0'       = 2
        'v2.0.0'        = 3
        'v2.1.0-beta.1' = 4
        'nightly'       = 4
    }
}

AfterAll {
    # Git makes the files of its objects read-only, which Pester cannot delete on Windows.
    Get-ChildItem -LiteralPath $TestDrive -Force | Remove-Item -Recurse -Force
}

Describe 'Update-MajorTag' -Tag 'Unit' {
    It 'points the tag of every major version at its newest release, on the remote as well' {
        $pair = & $script:NewRemoteAndClone $script:Releases

        $result = @(& $script:UpdateMajorTag -Path $pair.Clone 6> $null)

        # 1.10.0 is newer than 1.2.0, although it sorts before it as text. The beta of 2.1.0 is no release.
        $result.Tag | Should -Be 'v1', 'v2'
        $result.Release | Should -Be 'v1.10.0', 'v2.0.0'
        $result.Moved | Should -Be $true, $true
        & $script:TagCommit $pair.Remote 'v1' | Should -Be $pair.Commits[2]
        & $script:TagCommit $pair.Remote 'v2' | Should -Be $pair.Commits[3]
        & $script:TagCommit $pair.Clone 'v1' | Should -Be $pair.Commits[2]
    }

    It 'leaves a tag alone that points at the newest release already' {
        $pair = & $script:NewRemoteAndClone $script:Releases
        & $script:UpdateMajorTag -Path $pair.Clone 6> $null | Out-Null

        $result = @(& $script:UpdateMajorTag -Path $pair.Clone 6> $null)

        $result.Tag | Should -Be 'v1', 'v2'
        $result.Moved | Should -Be $false, $false
    }

    It 'does not move a tag back when an older commit is checked out' {
        $pair = & $script:NewRemoteAndClone $script:Releases
        & git -C $pair.Clone checkout --quiet --detach $pair.Commits[0] 2>&1 | Out-Null

        & $script:UpdateMajorTag -Path $pair.Clone 6> $null | Out-Null

        & $script:TagCommit $pair.Remote 'v1' | Should -Be $pair.Commits[2]
    }

    It 'changes nothing with -WhatIf, and says what it would do' {
        $pair = & $script:NewRemoteAndClone $script:Releases

        $result = @(& $script:UpdateMajorTag -Path $pair.Clone -WhatIf)

        $result.Release | Should -Be 'v1.10.0', 'v2.0.0'
        $result.Moved | Should -Be $false, $false
        & $script:TagCommit $pair.Remote 'v1' | Should -Be $pair.Commits[0]
        & $script:TagCommit $pair.Remote 'v2' | Should -BeNullOrEmpty
        & $script:TagCommit $pair.Clone 'v1' | Should -Be $pair.Commits[0]
    }

    It 'does nothing in a repository without a release' {
        $pair = & $script:NewRemoteAndClone @{ 'nightly' = 4; 'v1.0' = 1; 'v01.0.0' = 2; 'v1.0.0-rc.1' = 3 }

        $result = @(& $script:UpdateMajorTag -Path $pair.Clone)

        $result | Should -BeNullOrEmpty
        & $script:TagCommit $pair.Remote 'v1' | Should -BeNullOrEmpty
    }

    It 'fails when the tag cannot be pushed' {
        $pair = & $script:NewRemoteAndClone $script:Releases

        { & $script:UpdateMajorTag -Path $pair.Clone -Remote 'missing' 6> $null } |
            Should -Throw -ExpectedMessage '*git push*failed*'
    }
}

Describe 'The settings of semantic-release' -Tag 'Unit' {
    BeforeAll {
        $read = {
            param([string] $Name)

            [System.IO.File]::ReadAllText((Join-Path -Path $script:Root -ChildPath $Name))
        }
        $script:Package = ConvertFrom-Json -InputObject (& $read 'release/package.json') -AsHashtable
        $script:Lock = ConvertFrom-Json -InputObject (& $read 'release/package-lock.json') -AsHashtable
        $script:Workflow = & $read '.github/workflows/ci.yml'
        $script:Settings = & $read 'release/.releaserc.yml'
    }

    It 'names the plugins and the preset' -ForEach @{ Names = $script:Packages.Package } {
        $expected = '@semantic-release/commit-analyzer', '@semantic-release/release-notes-generator',
        '@semantic-release/github', 'conventional-changelog-conventionalcommits'

        $Names | Sort-Object | Should -Be ($expected | Sort-Object)
    }

    It 'has <Package> in the lock file, so that npm ci installs it' -ForEach $script:Packages {
        $script:Lock['packages'].Keys | Should -Contain "node_modules/$Package"
    }

    It 'names an exact version of <_> in package.json, and the lock file has the same one' -ForEach @(
        'semantic-release'
        'conventional-changelog-conventionalcommits'
    ) {
        $version = $script:Package['devDependencies'][$_]

        $version | Should -Match '^\d+\.\d+\.\d+$'
        $script:Lock['packages']["node_modules/$_"]['version'] | Should -Be $version
    }

    It 'releases from main only, with a tag that Update-MajorTag reads' {
        $script:Settings | Should -Match '(?m)^branches:\r?\n  - main\r?\n\r?\n'
        $script:Settings | Should -Match '(?m)^tagFormat: v\$\{version\}\r?$'
    }

    It 'releases after the tests passed, and only for a push to main' {
        $job = $script:Workflow.Substring($script:Workflow.IndexOf("`n  release:"))

        $job | Should -BeLike '*needs: `[test, action`]*'
        $job | Should -BeLike "*if: github.event_name == 'push' && github.ref == 'refs/heads/main'*"
    }

    It 'never stops a run for main, which may be in the middle of a release' {
        $script:Workflow | Should -BeLike "*cancel-in-progress: `${{ github.ref != 'refs/heads/main' }}*"
    }

    It 'gives only the job release the right to write' {
        $before = $script:Workflow.Substring(0, $script:Workflow.IndexOf("`n  release:"))

        $before | Should -Not -BeLike '*: write*'
        $before | Should -BeLike "*`npermissions:*contents: read*"
    }

    It 'installs from the lock file, runs semantic-release in the folder release and then moves the tag' {
        $job = $script:Workflow.Substring($script:Workflow.IndexOf("`n  release:"))
        $steps = 'fetch-depth: 0', 'working-directory: release', 'run: npm ci --ignore-scripts',
        'run: npm audit signatures', 'GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}', 'run: npx semantic-release',
        'run: ./build/Update-MajorTag.ps1'

        $job | Should -BeLike ('*{0}*' -f ($steps -join '*'))
    }
}
