#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.0.0' }

BeforeAll {
    . "$PSScriptRoot/../../src/Import-GhostModule.ps1"
    $script:Stub = Join-Path -Path $PSScriptRoot -ChildPath '../Stubs/Ghost'

    # Writes a module with the name Ghost to a folder below the test drive and returns that folder. The module
    # has a Sync-GhostPost with or without the parameter PreviousPath.
    $script:WriteModule = {
        param([string] $Name, [bool] $WithPreviousPath)

        $folder = Join-Path -Path (Join-Path -Path $TestDrive -ChildPath $Name) -ChildPath 'Ghost'
        New-Item -Path $folder -ItemType Directory -Force | Out-Null
        $parameter = if ($WithPreviousPath) { ', [string[]] $PreviousPath' } else { '' }
        $text = 'function Sync-GhostPost {{ param([string[]] $Path{0}) }}' -f $parameter
        [System.IO.File]::WriteAllText((Join-Path -Path $folder -ChildPath 'Ghost.psm1'), $text)
        $folder
    }
}

AfterAll {
    Remove-Module -Name 'Ghost' -Force -ErrorAction SilentlyContinue
}

Describe 'Import-GhostModule' -Tag 'Unit' {
    AfterEach {
        Remove-Module -Name 'Ghost' -Force -ErrorAction SilentlyContinue
    }

    It 'loads the module from a folder' {
        $module = Import-GhostModule -Path $script:Stub

        $module.Name | Should -Be 'Ghost'
        Get-Command -Name 'Sync-GhostPost' -Module 'Ghost' | Should -Not -BeNullOrEmpty
    }

    It 'fails for a folder that does not exist, and names the input' {
        { Import-GhostModule -Path (Join-Path -Path $TestDrive -ChildPath 'missing') } |
            Should -Throw -ExpectedMessage '*module-path*does not exist*'
    }

    It 'refuses a module that cannot remove what a commit removed' {
        $old = & $script:WriteModule 'old' $false

        { Import-GhostModule -Path $old } | Should -Throw -ExpectedMessage '*needs version 0.6.0 or later*'
    }

    It 'saves the version it is given from the PowerShell Gallery into the folder of the run, and loads that' {
        # Stands in for the Gallery: puts a module in the folder that the action asked for.
        Mock -CommandName 'Save-PSResource' -MockWith {
            $source = & $script:WriteModule 'gallery' $true
            Copy-Item -LiteralPath $source -Destination $Path -Recurse
        }
        $destination = Join-Path -Path $TestDrive -ChildPath ('modules-{0}' -f [guid]::NewGuid().ToString('N'))

        $module = Import-GhostModule -Version '0.6.0' -Destination $destination

        $module.Name | Should -Be 'Ghost'
        $module.ModuleBase | Should -Be (Join-Path -Path $destination -ChildPath 'Ghost')
        Should -Invoke -CommandName 'Save-PSResource' -Times 1 -Exactly -ParameterFilter {
            $Name -eq 'Ghost' -and
            $Version -eq '0.6.0' -and
            $Repository -eq 'PSGallery' -and
            $Path -eq $destination -and
            $TrustRepository
        }
    }

    It 'says which version could not be taken from the Gallery' {
        Mock -CommandName 'Save-PSResource' -MockWith { throw 'Package not found.' }
        $destination = Join-Path -Path $TestDrive -ChildPath ('modules-{0}' -f [guid]::NewGuid().ToString('N'))

        { Import-GhostModule -Version '9.9.9' -Destination $destination } |
            Should -Throw -ExpectedMessage '*Version 9.9.9 of the module Ghost*Package not found*'
    }
}
