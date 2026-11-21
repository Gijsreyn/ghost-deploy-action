function ConvertTo-DeployRow {
    <#
    .SYNOPSIS
        Turns a result of a Sync command of the module Ghost into a row for the report of the run.

    .DESCRIPTION
        The Sync commands return one result per file, and each kind has its own properties: a post and a page
        have a title, a tag has a name, a theme has a name and a version. The report shows them in one table,
        so every result becomes a row with the same five properties: Kind, Action, Name, Slug and File.

        File is the path as it is in the repository, with forward slashes, because that is how the reader knows
        the file. A result for something that was removed points to a copy of the earlier file in a folder of
        this run. That path is turned back into the path the file had in the repository.

        A file that is not below the working directory is shown by its name alone. That is the case for the
        package of a theme that an earlier step of the workflow downloaded.

    .EXAMPLE
        Sync-GhostPost -Path posts -Recurse | ConvertTo-DeployRow -Kind Post -Root (Get-Location).Path

        Returns a row per post, with the path of its file from the working directory.

    .EXAMPLE
        $result | ConvertTo-DeployRow -Kind Page -Root $root -PreviousRoot $copy -PreviousName pages

        Returns the rows of the pages. A removed page, whose file is below the folder in $copy, gets a path
        that starts with pages.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        # What the result is about.
        [Parameter(Mandatory)]
        [ValidateSet('Theme', 'Tag', 'Page', 'Post')]
        [string] $Kind,

        # A result of Sync-GhostTheme, Sync-GhostTag, Sync-GhostPage or Sync-GhostPost.
        [Parameter(Mandatory, ValueFromPipeline)]
        [object] $InputObject,

        # The folder that the paths in the report start from: the working directory of the run.
        [Parameter(Mandatory)]
        [string] $Root,

        # The folder of this run that holds the earlier files of this kind.
        [string] $PreviousRoot,

        # The folder of this kind as the workflow names it, such as posts.
        [string] $PreviousName
    )

    process {
        $properties = $InputObject.PSObject.Properties

        # A theme and a tag have a name. A post and a page have a title.
        $name = $null
        foreach ($candidate in 'Title', 'Name') {
            if (-not $name -and $properties[$candidate]) {
                $name = [string] $properties[$candidate].Value
            }
        }
        if ($Kind -eq 'Theme' -and $properties['Version'] -and $properties['Version'].Value) {
            $name = '{0} {1}' -f $name, $properties['Version'].Value
        }

        $slug = $null
        if ($properties['Slug']) {
            $slug = [string] $properties['Slug'].Value
        }

        $file = $null
        if ($properties['Path'] -and $properties['Path'].Value) {
            $path = [string] $properties['Path'].Value
            $inPrevious = $false
            if ($PreviousRoot) {
                $below = [System.IO.Path]::GetRelativePath($PreviousRoot, $path)
                $inPrevious = -not $below.StartsWith('..') -and -not [System.IO.Path]::IsPathRooted($below)
            }
            if ($inPrevious) {
                $file = (Join-Path -Path $PreviousName -ChildPath $below)
            }
            else {
                $file = [System.IO.Path]::GetRelativePath($Root, $path)
                if ($file -match '^\.\.([\\/]|$)' -or [System.IO.Path]::IsPathRooted($file)) {
                    # The way from the working directory to a file outside it tells the reader nothing.
                    $file = [System.IO.Path]::GetFileName($path.TrimEnd('\', '/'))
                }
            }
            $file = $file.Replace('\', '/').TrimEnd('/')
        }

        [pscustomobject]@{
            Kind   = $Kind
            Action = [string] $properties['Action'].Value
            Name   = $name
            Slug   = $slug
            File   = $file
        }
    }
}
