function Write-DeployMessage {
    <#
    .SYNOPSIS
        Writes a notice, a warning or an error to the log of the run.

    .DESCRIPTION
        In a GitHub workflow the message is written as a workflow command. GitHub then shows it on the page of
        the run, next to the log, where it is seen without opening the log. Outside a workflow the same message
        is written as a plain line, so that the script can be tried on any machine.

        A workflow command is one line. The characters that would end it or change its meaning are escaped the
        way GitHub asks for.

    .EXAMPLE
        Write-DeployMessage -Level notice -Message 'This run has no commit to compare with.'

        Shows the notice on the page of the run.

    .EXAMPLE
        Write-DeployMessage -Level error -Message $_.Exception.Message

        Shows why the run failed.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        # How serious the message is.
        [Parameter(Mandatory)]
        [ValidateSet('notice', 'warning', 'error')]
        [string] $Level,

        # The text of the message.
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Message
    )

    if ($env:GITHUB_ACTIONS -eq 'true') {
        $escaped = $Message.Replace('%', '%25').Replace("`r", '%0D').Replace("`n", '%0A')
        $line = '::{0} title=Deploy to Ghost::{1}' -f $Level, $escaped
    }
    else {
        $label = $Level.Substring(0, 1).ToUpperInvariant() + $Level.Substring(1)
        $line = '{0}: {1}' -f $label, $Message
    }

    Write-Information -MessageData $line -InformationAction Continue
}
