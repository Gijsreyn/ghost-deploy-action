function Export-PreviousFile {
    <#
    .SYNOPSIS
        Writes the Markdown files of a folder as they were in an earlier commit to a folder of this run.

    .DESCRIPTION
        The module Ghost removes a post, a page or a tag when it is given the files as they were before and one
        of them is gone. This function gets those earlier files out of git.

        Git writes the Markdown files of the folder in the earlier commit to an archive, which is then unpacked.
        No file name and no content passes through the text handling of PowerShell on the way, so a name with
        characters outside ASCII comes out as it went in. Pictures and other files are left out. Only the
        Markdown files say which post, page or tag there was.

        The folder is given as the workflow names it. It does not have to exist any more: when the last file of
        a folder was removed, the checkout no longer has the folder. Git is asked where the folder is in its
        repository, which also works for a repository that was checked out below the working directory.

        The result says where the earlier files are and which Markdown files were deleted since. The caller
        counts those to hold a run to a limit before anything is removed. A README.md is not counted, because
        it is never a post, a page or a tag.

    .EXAMPLE
        Export-PreviousFile -Path posts -Commit $commit -Destination $folder

        Returns an object. Its property Path is the folder with the posts as they were in that commit, or
        nothing when the commit had no folder posts. Its property Deleted lists the files that are gone.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        # The folder with the content, as the workflow names it.
        [Parameter(Mandatory)]
        [string] $Path,

        # The commit to take the earlier files from.
        [Parameter(Mandatory)]
        [string] $Commit,

        # A folder of this run to write to. It is created when it is not there.
        [Parameter(Mandatory)]
        [string] $Destination
    )

    # The part of the path that still exists says which repository is meant. The rest is added as text.
    $place = Get-ExistingFolder -Path $Path

    $prefix = Invoke-Git -Path $place.Folder -ArgumentList 'rev-parse', '--show-prefix'
    $top = Invoke-Git -Path $place.Folder -ArgumentList 'rev-parse', '--show-toplevel'
    if ($prefix.ExitCode -ne 0 -or $top.ExitCode -ne 0 -or $top.Output.Count -eq 0) {
        throw "The folder '$Path' is not in a git repository, so there are no earlier files to compare with."
    }
    $root = $top.Output[0]

    # The folder as git names it: from the top of the repository, with forward slashes.
    $segments = @((@($prefix.Output) -join '') -split '/') + $place.Missing | Where-Object { $_ }
    $segments = @($segments)
    $relative = $segments -join '/'

    # Every Markdown file in the folder and below it. A character that means something in a pattern is put
    # between brackets, which makes it stand for itself. A folder name with a bracket in it is then taken as
    # it is. A backslash would do the same, but git for Windows reads that as the end of a folder name.
    $escaped = [regex]::Replace($relative, '[*?\[]', '[$0]')
    $pattern = if ($escaped) { ":(glob)$escaped/**/*.md" } else { ':(glob)**/*.md' }

    $result = [pscustomobject]@{
        Path    = $null
        Deleted = @()
    }

    # A folder that the earlier commit did not have gives no earlier files.
    if ($relative) {
        $tree = Invoke-Git -Path $root -ArgumentList 'cat-file', '-e', ('{0}:{1}' -f $Commit, $relative)
        if ($tree.ExitCode -ne 0) {
            return $result
        }
    }

    New-Item -Path $Destination -ItemType Directory -Force | Out-Null
    $files = Join-Path -Path $Destination -ChildPath 'files'
    $previous = $files
    foreach ($segment in $segments) {
        $previous = Join-Path -Path $previous -ChildPath $segment
    }
    New-Item -Path $previous -ItemType Directory -Force | Out-Null

    $archive = Join-Path -Path $Destination -ChildPath 'previous.zip'
    $packed = Invoke-Git -Path $root -ArgumentList 'archive', '--format=zip', '-o', $archive, $Commit, '--', $pattern
    if ($packed.ExitCode -eq 0) {
        Expand-Archive -LiteralPath $archive -DestinationPath $files -Force
        Remove-Item -LiteralPath $archive -Force
    }
    elseif (-not ($packed.Output -match 'did not match any files')) {
        throw "The files of '$Path' in commit $Commit could not be read. $($packed.Output -join ' ')"
    }
    $result.Path = $previous

    # The Markdown files that the earlier commit had and the working folder has not.
    $query = 'diff', '--name-only', '--no-renames', '--diff-filter=D', $Commit, '--', $pattern
    $deleted = Invoke-Git -Path $root -ArgumentList $query
    if ($deleted.ExitCode -ne 0) {
        throw "The files of '$Path' could not be compared with commit $Commit. $($deleted.Output -join ' ')"
    }
    $result.Deleted = @(
        $deleted.Output | Where-Object { $_ -and ($_ -split '/')[-1] -ne 'README.md' }
    )

    $result
}
