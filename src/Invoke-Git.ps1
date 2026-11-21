function Invoke-Git {
    <#
    .SYNOPSIS
        Runs git in a folder and returns its exit code and its output.

    .DESCRIPTION
        Git reports a problem with its exit code and a message on the error stream. PowerShell would only show
        that message. This function returns both, so that the caller can decide what an exit code means. A path
        that is not in a commit is an answer to a question, for example, and not an error.

        File names are returned as they are, also when they have characters outside ASCII. Without the setting
        core.quotepath=off git would write those as escape codes.

    .EXAMPLE
        Invoke-Git -Path . -ArgumentList 'rev-parse', '--show-prefix'

        Returns an object with the exit code 0 and, in Output, the path of the current folder in its repository.

    .EXAMPLE
        (Invoke-Git -Path . -ArgumentList 'cat-file', '-e', 'HEAD:posts').ExitCode

        Returns 0 when the last commit has a folder posts and another number when it has not.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        # The folder that git runs in. It decides which repository is meant.
        [Parameter(Mandatory)]
        [string] $Path,

        # The arguments for git, as they would be typed after git.
        [Parameter(Mandatory)]
        [string[]] $ArgumentList
    )

    $output = & git -C $Path -c core.quotepath=off @ArgumentList 2>&1
    $exitCode = $LASTEXITCODE

    [pscustomobject]@{
        ExitCode = $exitCode
        Output   = @($output | ForEach-Object { [string] $_ })
    }
}
