function Import-GhostModule {
    <#
    .SYNOPSIS
        Loads the PowerShell module Ghost, which does the work of the action.

    .DESCRIPTION
        The action is a thin layer around the module Ghost. This function gets the module in one of two ways.

        With a version, that exact version is saved from the PowerShell Gallery into a folder of this run and
        loaded from there. Nothing is installed on the runner, and a module that the runner already has does not
        get in the way. The same version is used on every run, which is why action.yml names one.

        With a path, the module is loaded from that folder. That is for a copy of the module that is not on
        the Gallery, such as one from a checkout.

        The module has to know the parameter PreviousPath of Sync-GhostPost, which came with version 0.6.0.
        An older module cannot remove what a commit removed and reports a dry run only half, so the action
        stops instead of working differently from what its documentation says.

    .EXAMPLE
        Import-GhostModule -Version 0.6.0 -Destination $folder

        Saves version 0.6.0 of the module in the folder and loads it.

    .EXAMPLE
        Import-GhostModule -Path ./ghost-sdk-powershell/Ghost

        Loads the module from a checkout.
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSModuleInfo])]
    param(
        # The version to take from the PowerShell Gallery.
        [string] $Version,

        # The folder of a copy of the module to load instead. It wins over Version.
        [string] $Path,

        # The folder to save the module from the Gallery in.
        [string] $Destination
    )

    if ($Path) {
        if (-not (Test-Path -LiteralPath $Path)) {
            throw "The input module-path names '$Path', which does not exist."
        }
        $source = (Resolve-Path -LiteralPath $Path).ProviderPath
    }
    else {
        New-Item -Path $Destination -ItemType Directory -Force | Out-Null
        $save = @{
            Name            = 'Ghost'
            Version         = $Version
            Repository      = 'PSGallery'
            Path            = $Destination
            TrustRepository = $true
        }
        try {
            Save-PSResource @save
        }
        catch {
            $reason = $_.Exception.Message
            throw "Version $Version of the module Ghost could not be taken from the PowerShell Gallery. $reason"
        }
        $source = Join-Path -Path $Destination -ChildPath 'Ghost'
    }

    $module = Import-Module -Name $source -Force -PassThru

    $command = Get-Command -Name 'Sync-GhostPost' -ErrorAction SilentlyContinue
    if (-not $command -or -not $command.Parameters.ContainsKey('PreviousPath')) {
        $found = @($module)[0].Version
        throw "This action needs version 0.6.0 or later of the module Ghost. Version $found was loaded."
    }

    @($module)[0]
}
