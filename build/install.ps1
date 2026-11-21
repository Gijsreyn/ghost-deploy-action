<#
.SYNOPSIS
    Installs the modules that are needed to test the action.

.DESCRIPTION
    Installs Pester and PSScriptAnalyzer for the current user when the required version is not there yet.

    The module Ghost is not installed here. The action saves the version it needs in a folder of the run, and
    the unit tests use a stand-in for it.

.EXAMPLE
    ./build/install.ps1

    Installs what is missing. Run it once on a new machine. The workflow runs it at the start of every job.
#>
#Requires -Version 7.4
[CmdletBinding()]
[OutputType([void])]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$InformationPreference = 'Continue'

$required = @(
    @{ Name = 'Pester'; MinimumVersion = '6.0.0' }
    @{ Name = 'PSScriptAnalyzer'; MinimumVersion = '1.25.0' }
)

foreach ($module in $required) {
    $minimum = [version] $module.MinimumVersion
    $installed = Get-Module -Name $module.Name -ListAvailable |
        Where-Object { $_.Version -ge $minimum } |
        Sort-Object -Property Version -Descending |
        Select-Object -First 1

    if ($installed) {
        Write-Information -MessageData "$($module.Name) $($installed.Version) is installed."
        continue
    }

    Write-Information -MessageData "Installing $($module.Name) $minimum or later."
    $install = @{
        Name            = $module.Name
        Version         = '[{0}, ]' -f $minimum
        Repository      = 'PSGallery'
        Scope           = 'CurrentUser'
        TrustRepository = $true
    }
    Install-PSResource @install
}
