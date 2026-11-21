#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.0.0' }

BeforeAll {
    . "$PSScriptRoot/../../src/Get-DeployInput.ps1"

    # The smallest set of inputs that is accepted. A test changes the ones it is about.
    $script:NewInput = {
        param([hashtable] $Change = @{})

        $values = @{
            GHOST_DEPLOY_API_URL        = 'https://ghost.test'
            GHOST_DEPLOY_API_KEY        = 'abc:123'
            GHOST_DEPLOY_POSTS          = 'posts'
            GHOST_DEPLOY_MODULE_VERSION = '0.6.0'
        }
        foreach ($name in $Change.Keys) {
            $values["GHOST_DEPLOY_$name"] = $Change[$name]
        }
        $values
    }
}

Describe 'Get-DeployInput' -Tag 'Unit' {
    It 'returns the inputs, with false, 10 and empty text for what was not given' {
        $result = Get-DeployInput -Environment (& $script:NewInput)

        $result.ApiUrl | Should -Be 'https://ghost.test'
        $result.Posts | Should -Be 'posts'
        $result.Theme | Should -Be ''
        $result.ThemeName | Should -Be ''
        $result.Tags | Should -Be ''
        $result.Pages | Should -Be ''
        $result.Delete | Should -BeFalse
        $result.DryRun | Should -BeFalse
        $result.DeleteLimit | Should -Be 10
        $result.BaseRef | Should -Be ''
        $result.ModuleVersion | Should -Be '0.6.0'
        $result.ModulePath | Should -Be ''
    }

    It 'returns the key as a secure string with the same text' {
        $result = Get-DeployInput -Environment (& $script:NewInput)

        $result.ApiKey | Should -BeOfType ([securestring])
        [System.Net.NetworkCredential]::new('', $result.ApiKey).Password | Should -BeExactly 'abc:123'
    }

    It 'takes the spaces around an input away' {
        $change = @{ API_URL = '  https://ghost.test  '; THEME = ' theme '; BASE_REF = " abc123`n" }

        $result = Get-DeployInput -Environment (& $script:NewInput $change)

        $result.ApiUrl | Should -Be 'https://ghost.test'
        $result.Theme | Should -Be 'theme'
        $result.BaseRef | Should -Be 'abc123'
    }

    It 'reads <Text> for <Name> as <Expected>' -ForEach @(
        @{ Name = 'DELETE'; Property = 'Delete'; Text = 'true'; Expected = $true }
        @{ Name = 'DELETE'; Property = 'Delete'; Text = 'True'; Expected = $true }
        @{ Name = 'DELETE'; Property = 'Delete'; Text = 'false'; Expected = $false }
        @{ Name = 'DELETE'; Property = 'Delete'; Text = ''; Expected = $false }
        @{ Name = 'DRY_RUN'; Property = 'DryRun'; Text = 'true'; Expected = $true }
        @{ Name = 'DRY_RUN'; Property = 'DryRun'; Text = 'FALSE'; Expected = $false }
    ) {
        $result = Get-DeployInput -Environment (& $script:NewInput @{ $Name = $Text })

        $result.$Property | Should -Be $Expected
    }

    It 'refuses <Text> for an input that is true or false, and names the input' -ForEach @(
        @{ Name = 'DELETE'; Text = 'yes'; Message = '*delete has to be true or false*' }
        @{ Name = 'DELETE'; Text = '1'; Message = '*delete has to be true or false*' }
        @{ Name = 'DRY_RUN'; Text = '0'; Message = '*dry-run has to be true or false*' }
        @{ Name = 'DRY_RUN'; Text = 'no'; Message = '*dry-run has to be true or false*' }
    ) {
        { Get-DeployInput -Environment (& $script:NewInput @{ $Name = $Text }) } |
            Should -Throw -ExpectedMessage $Message
    }

    It 'needs the address of the site' {
        { Get-DeployInput -Environment (& $script:NewInput @{ API_URL = '' }) } |
            Should -Throw -ExpectedMessage '*api-url is empty*'
    }

    It 'needs the key, and says what an empty key usually means' {
        { Get-DeployInput -Environment (& $script:NewInput @{ API_KEY = ' ' }) } |
            Should -Throw -ExpectedMessage '*api-key is empty*pull request from a fork*'
    }

    It 'needs at least one of theme, tags, pages and posts' {
        { Get-DeployInput -Environment (& $script:NewInput @{ POSTS = '' }) } |
            Should -Throw -ExpectedMessage '*nothing to deploy*'

        (Get-DeployInput -Environment (& $script:NewInput @{ POSTS = ''; THEME = 'theme' })).Theme |
            Should -Be 'theme'
    }

    It 'reads the limit for removals as a number' {
        (Get-DeployInput -Environment (& $script:NewInput @{ DELETE_LIMIT = '25' })).DeleteLimit | Should -Be 25
        (Get-DeployInput -Environment (& $script:NewInput @{ DELETE_LIMIT = '0' })).DeleteLimit | Should -Be 0
    }

    It 'refuses <Text> as the limit for removals' -ForEach @(
        @{ Text = 'many' }
        @{ Text = '-1' }
        @{ Text = '2.5' }
    ) {
        { Get-DeployInput -Environment (& $script:NewInput @{ DELETE_LIMIT = $Text }) } |
            Should -Throw -ExpectedMessage '*delete-limit has to be a whole number*'
    }

    It 'needs a version of the module, unless a copy of the module is given' {
        { Get-DeployInput -Environment (& $script:NewInput @{ MODULE_VERSION = '' }) } |
            Should -Throw -ExpectedMessage '*module-version is empty*'

        $change = @{ MODULE_VERSION = ''; MODULE_PATH = './module' }
        (Get-DeployInput -Environment (& $script:NewInput $change)).ModulePath | Should -Be './module'
    }

    It 'reads the environment of the process when it is given nothing' {
        $names = 'API_URL', 'API_KEY', 'POSTS', 'MODULE_VERSION'
        $before = @{}
        foreach ($name in $names) {
            $before[$name] = [System.Environment]::GetEnvironmentVariable("GHOST_DEPLOY_$name")
        }
        try {
            $env:GHOST_DEPLOY_API_URL = 'https://from-the-environment.test'
            $env:GHOST_DEPLOY_API_KEY = 'abc:123'
            $env:GHOST_DEPLOY_POSTS = 'posts'
            $env:GHOST_DEPLOY_MODULE_VERSION = '0.6.0'

            (Get-DeployInput).ApiUrl | Should -Be 'https://from-the-environment.test'
        }
        finally {
            foreach ($name in $names) {
                [System.Environment]::SetEnvironmentVariable("GHOST_DEPLOY_$name", $before[$name])
            }
        }
    }
}
