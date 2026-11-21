#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.0.0' }
<#
    Checks that action.yml and the scripts agree with each other.

    The file action.yml cannot be run on a machine of your own. Only GitHub reads it. What can be checked here
    is that the three places that have to name the same things do so: the inputs of action.yml, the environment
    variables that its step passes on, and the names that the scripts read and write. A typo in one of them
    would otherwise only show in a workflow, as an input that is silently ignored.
#>

BeforeDiscovery {
    $root = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    $lines = [System.IO.File]::ReadAllLines((Join-Path -Path $root -ChildPath 'action.yml'))

    # The names below a top-level key of action.yml: the lines that are indented by two spaces.
    $section = $null
    $names = @{ inputs = @(); outputs = @() }
    foreach ($line in $lines) {
        if ($line -match '^(?<key>[a-z]+):') {
            $section = $Matches['key']
        }
        elseif ($line -match '^  (?<name>[a-z][a-z-]*):' -and $names.ContainsKey([string] $section)) {
            $names[$section] += $Matches['name']
        }
    }

    $script:Inputs = @($names['inputs'] | ForEach-Object {
            @{ Name = $_; Variable = 'GHOST_DEPLOY_{0}' -f $_.ToUpperInvariant().Replace('-', '_') }
        })
    $script:Outputs = @($names['outputs'] | ForEach-Object { @{ Name = $_ } })
}

BeforeAll {
    $script:Root = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    $script:Action = [System.IO.File]::ReadAllText((Join-Path -Path $script:Root -ChildPath 'action.yml'))
    $script:ReadText = {
        param([string] $Name)

        [System.IO.File]::ReadAllText((Join-Path -Path $script:Root -ChildPath "src/$Name"))
    }
}

Describe 'action.yml' -Tag 'Unit' {
    It 'has the inputs and outputs that the documentation describes' -ForEach @{
        Inputs  = $script:Inputs.Name
        Outputs = $script:Outputs.Name
    } {
        $expected = 'api-url', 'api-key', 'theme', 'theme-name', 'tags', 'pages', 'posts', 'delete', 'delete-limit',
        'base-ref', 'dry-run', 'module-version', 'module-path'

        $Inputs | Should -Be $expected
        $Outputs | Should -Be 'created', 'updated', 'removed', 'unchanged', 'changed'
    }

    It 'passes the input <Name> to the script as <Variable>' -ForEach $script:Inputs {
        $script:Action | Should -BeLike "*$Variable`: `${{ inputs.$Name }}*"
    }

    It 'has a script that reads <Variable>' -ForEach $script:Inputs {
        $key = $Variable.Substring('GHOST_DEPLOY_'.Length)

        & $script:ReadText 'Get-DeployInput.ps1' | Should -BeLike "*'$key'*"
    }

    It 'takes the output <Name> from the step that runs the script' -ForEach $script:Outputs {
        $script:Action | Should -BeLike "*value: `${{ steps.deploy.outputs.$Name }}*"
    }

    It 'has a script that writes the output <Name>' -ForEach $script:Outputs {
        & $script:ReadText 'Write-DeployReport.ps1' | Should -Match ("['`"]$Name=")
    }

    It 'runs the script of this repository and exits with its exit code' {
        $script:Action | Should -BeLike '*using: composite*'
        $script:Action | Should -BeLike '*id: deploy*shell: pwsh*'
        $script:Action | Should -BeLike "*`$env:GITHUB_ACTION_PATH*'src/Invoke-GhostDeploy.ps1'*exit `$LASTEXITCODE*"
        Join-Path -Path $script:Root -ChildPath 'src/Invoke-GhostDeploy.ps1' | Should -Exist
    }

    It 'has a description that the Marketplace accepts, of less than 125 characters' {
        $script:Action -match '(?m)^description: (?<text>.+)$' | Should -BeTrue
        $Matches['text'].Length | Should -BeLessThan 125
    }

    It 'never puts an input in the text of the script, where it could be run as code' {
        $run = $script:Action.Substring($script:Action.IndexOf('      run: |'))

        $run | Should -Not -BeLike '*${{*'
    }
}
