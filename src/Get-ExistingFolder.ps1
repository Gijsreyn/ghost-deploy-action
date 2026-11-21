function Get-ExistingFolder {
    <#
    .SYNOPSIS
        Returns the part of a path that exists as a folder, and the part that does not.

    .DESCRIPTION
        A folder of content does not have to exist in a checkout. Git keeps no empty folders, so the folder is
        gone as soon as its last file was removed. That is exactly the run in which its posts, pages or tags
        have to be removed from the site.

        Git still has to be asked about the folder, and git runs in a folder that exists. This function walks
        up from the path until it finds one. The names it passed on the way are returned as well, so that the
        caller can name the whole path to git.

    .EXAMPLE
        Get-ExistingFolder -Path site/pages

        Returns the full path of site/pages in Folder and nothing in Missing when the folder exists. When only
        site exists, Folder is the full path of site and Missing is pages.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        # A path to a folder, from the working directory or from the root.
        [Parameter(Mandatory)]
        [string] $Path
    )

    $full = [System.IO.Path]::GetFullPath($Path, (Get-Location).ProviderPath)
    $folder = $full.TrimEnd('\', '/')
    if (-not $folder) {
        $folder = $full
    }

    $missing = @()
    while (-not (Test-Path -LiteralPath $folder -PathType Container)) {
        $missing = @([System.IO.Path]::GetFileName($folder)) + $missing
        $parent = [System.IO.Path]::GetDirectoryName($folder)
        if (-not $parent) {
            throw "The folder '$Path' does not exist, and neither does a folder above it."
        }
        $folder = $parent
    }

    [pscustomobject]@{
        Folder  = $folder
        Missing = @($missing)
    }
}
