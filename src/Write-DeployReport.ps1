function Write-DeployReport {
    <#
    .SYNOPSIS
        Writes the summary of the run and sets the outputs of the action.

    .DESCRIPTION
        The summary is the page that GitHub shows for a run. It gets one sentence that says what happened and a
        table with a row for everything that was created, updated or removed. What did not change is only
        counted, because a site with hundreds of posts would otherwise bury the three that matter.

        In a dry run nothing was changed. The summary then says what a real run would do, which is what a
        reviewer of a pull request wants to read.

        The outputs are the numbers of the same sentence: created, updated, removed and unchanged. The output
        changed is true when at least one of the first three is not zero. In a dry run they count what would be
        done.

        GitHub gives a run a file for the summary and a file for the outputs. Without those files, on a machine
        of your own, nothing is written and the numbers are only returned.

    .EXAMPLE
        Write-DeployReport -Row $rows -Site 'My site'

        Writes the summary and the outputs of a run that changed the site, and returns the numbers.

    .EXAMPLE
        Write-DeployReport -Row $rows -Site 'My site' -DryRun

        Writes what a real run would do.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        # The rows of ConvertTo-DeployRow, for everything the run looked at.
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Row,

        # The title of the site, for the first sentence.
        [string] $Site,

        # The run changed nothing and the rows say what would be done.
        [switch] $DryRun,

        # The run stopped with an error, so the rows are what was done until then.
        [switch] $Failed,

        # The file for the summary. Defaults to the one of this run.
        [string] $SummaryPath = $env:GITHUB_STEP_SUMMARY,

        # The file for the outputs. Defaults to the one of this run.
        [string] $OutputPath = $env:GITHUB_OUTPUT
    )

    # Text for an action, as it reads in a table.
    $labels = @{
        Created     = 'Created'
        Updated     = 'Updated'
        Removed     = 'Removed'
        WouldCreate = 'Would create'
        WouldUpdate = 'Would update'
        WouldRemove = 'Would remove'
    }

    $created = @($Row | Where-Object { $_.Action -in 'Created', 'WouldCreate' }).Count
    $updated = @($Row | Where-Object { $_.Action -in 'Updated', 'WouldUpdate' }).Count
    $removed = @($Row | Where-Object { $_.Action -in 'Removed', 'WouldRemove' }).Count
    $unchanged = @($Row | Where-Object { $_.Action -eq 'Unchanged' }).Count
    $changed = ($created + $updated + $removed) -gt 0

    $result = [pscustomobject]@{
        Created   = $created
        Updated   = $updated
        Removed   = $removed
        Unchanged = $unchanged
        Changed   = $changed
    }

    $encoding = [System.Text.UTF8Encoding]::new($false)

    if ($OutputPath) {
        $outputs = @(
            "created=$created"
            "updated=$updated"
            "removed=$removed"
            "unchanged=$unchanged"
            'changed={0}' -f $changed.ToString().ToLowerInvariant()
        )
        [System.IO.File]::AppendAllText($OutputPath, (($outputs -join "`n") + "`n"), $encoding)
    }

    if ($SummaryPath) {
        $name = if ($Site) { "**$Site**" } else { 'the site' }
        $lines = [System.Collections.Generic.List[string]]::new()
        $lines.Add('## Deploy to Ghost')
        $lines.Add('')

        if ($Failed) {
            $lines.Add("The run for $name stopped with an error. The log has the reason. This was done before:")
        }
        elseif ($DryRun) {
            $lines.Add("This was a dry run for $name. Nothing was changed. A real run would do this:")
        }
        else {
            $lines.Add("The files were deployed to $name.")
        }
        $lines.Add('')

        $verbs = if ($DryRun) { 'To create', 'to update', 'to remove' } else { 'Created', 'updated', 'removed' }
        $count = '{0}: {1}, {2}: {3}, {4}: {5}. Unchanged: {6}.'
        $lines.Add(($count -f $verbs[0], $created, $verbs[1], $updated, $verbs[2], $removed, $unchanged))

        if ($changed) {
            $lines.Add('')
            $lines.Add('| Kind | Action | Name | Slug | File |')
            $lines.Add('| --- | --- | --- | --- | --- |')
            foreach ($item in $Row | Where-Object { $_.Action -ne 'Unchanged' }) {
                $cells = @(
                    $item.Kind
                    $labels[[string] $item.Action]
                    $item.Name
                    $item.Slug
                    $item.File
                ) | ForEach-Object {
                    # A cell is one line, and a bar would start a new cell.
                    ([string] $_).Replace('|', '\|') -replace '\s+', ' '
                }
                $lines.Add('| {0} |' -f ($cells -join ' | '))
            }
        }
        $lines.Add('')

        [System.IO.File]::AppendAllText($SummaryPath, (($lines -join "`n") + "`n"), $encoding)
    }

    $result
}
