function Resolve-BaseCommit {
    <#
    .SYNOPSIS
        Finds the commit that the files of this run are compared with.

    .DESCRIPTION
        A post, a page or a tag is removed from the site when its file was removed from the repository. To know
        which files were removed, the files of this run are compared with those of an earlier commit: the state
        that the site was given before.

        That commit is, in this order:

        1. The input base-ref, when it is given. It can be a commit or anything else that git can resolve.
        2. For a push, the commit that the branch pointed to before the push.
        3. For a pull request, the commit of the branch that it would be merged into.

        A run that was started by hand or by a schedule has no such commit, and neither has the first push of
        a new branch. The result then has no commit and says why, and the caller removes nothing.

        A workflow usually checks out one commit only. When the commit to compare with is not in the clone it
        is fetched from origin. When that fails the function throws, because going on would silently leave
        files that were removed on the site for good.

    .EXAMPLE
        Resolve-BaseCommit -Repository .

        Returns the commit to compare with for the event of this run, with a sentence that says where it is from.

    .EXAMPLE
        Resolve-BaseCommit -Repository ./site -BaseRef 'HEAD~1'

        Returns the commit before the last one of the repository in the folder site.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        # A folder in the repository that holds the content.
        [Parameter(Mandatory)]
        [string] $Repository,

        # The input base-ref: a commit, or a name that git can resolve to one.
        [string] $BaseRef,

        # The name of the event that started the run. Defaults to the one of this run.
        [string] $EventName = $env:GITHUB_EVENT_NAME,

        # The file with the details of the event. Defaults to the one of this run.
        [string] $EventPath = $env:GITHUB_EVENT_PATH
    )

    $candidate = $null
    $source = $null

    if ($BaseRef) {
        $candidate = $BaseRef
        $source = 'the input base-ref'
    }
    elseif ($EventPath -and (Test-Path -LiteralPath $EventPath -PathType Leaf)) {
        $text = [System.IO.File]::ReadAllText($EventPath, [System.Text.Encoding]::UTF8)
        $details = ConvertFrom-Json -InputObject $text

        if ($EventName -eq 'push') {
            $before = $details.PSObject.Properties['before']
            if ($before -and $before.Value -and $before.Value -notmatch '^0+$') {
                $candidate = [string] $before.Value
                $source = 'the commit before this push'
            }
        }
        elseif ($EventName -eq 'pull_request' -or $EventName -eq 'pull_request_target') {
            $pullRequest = $details.PSObject.Properties['pull_request']
            if ($pullRequest) {
                $candidate = [string] $pullRequest.Value.base.sha
                $source = 'the branch of this pull request'
            }
        }
    }

    if (-not $candidate) {
        $name = if ($EventName) { $EventName } else { 'unknown' }
        $reason = "This run has no commit to compare with (event: $name), so nothing is removed."

        return [pscustomobject]@{
            Commit = $null
            Reason = "$reason Give the input base-ref a commit to compare with one."
        }
    }

    # The commit as git knows it. A clone of one commit does not have it yet, so it is fetched once.
    $query = 'rev-parse', '--verify', '--quiet', ('{0}^{{commit}}' -f $candidate)
    $found = Invoke-Git -Path $Repository -ArgumentList $query
    if ($found.ExitCode -ne 0) {
        Invoke-Git -Path $Repository -ArgumentList 'fetch', '--no-tags', '--depth=1', 'origin', $candidate |
            Out-Null
        $found = Invoke-Git -Path $Repository -ArgumentList $query
    }
    if ($found.ExitCode -ne 0 -or $found.Output.Count -eq 0) {
        $advice = 'Check out with fetch-depth: 0, or give the input base-ref a commit that exists.'
        $problem = "The commit to compare with, '$candidate' from $source, is not in this clone"
        throw "$problem and could not be fetched. $advice"
    }

    $commit = $found.Output[0].Trim()

    [pscustomobject]@{
        Commit = $commit
        Reason = "The files are compared with commit $commit, $source."
    }
}
