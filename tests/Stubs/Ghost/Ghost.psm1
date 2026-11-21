<#
    A stand-in for the PowerShell module Ghost, for the unit tests of the action.

    The script of the action loads it through the input module-path. It has the commands that the action calls,
    with the same parameters, and sends nothing anywhere. Two environment variables steer it:

    GHOST_STUB_LOG   A file. Every call is added to it as one line of JSON, so that a test can read back which
                     commands ran, in which order and with which arguments.
    GHOST_STUB_PLAN  A file with JSON that says what the commands do. A property with the name of a command
                     holds the results it returns. The property Fail names a command that throws, and the
                     property Warning holds a warning per command.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-StubCall {
    <#
    .SYNOPSIS
        Adds a call of a command to the log of the stand-in.

    .DESCRIPTION
        Writes the name of the command and its arguments as one line of JSON to the file in GHOST_STUB_LOG.
        Without that variable nothing is written.

        The line also says what the command would have done with a real change: whether it ran as a dry run,
        whether it would have asked for confirmation, and whether the key of the site was still in the
        environment.

    .EXAMPLE
        Write-StubCall -Command 'Sync-GhostTag' -Argument @{ Path = './tags' }

        Adds that call to the log.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        # The name of the command that was called.
        [Parameter(Mandatory)]
        [string] $Command,

        # The arguments of the call.
        [System.Collections.IDictionary] $Argument = @{},

        # The command ran with -WhatIf.
        [bool] $DryRun,

        # The value of $ConfirmPreference in the command. None means that it does not ask.
        [string] $Asks
    )

    if (-not $env:GHOST_STUB_LOG) {
        return
    }

    $entry = [ordered]@{
        Command  = $Command
        DryRun   = $DryRun
        Confirm  = $Asks
        KeyInEnv = [bool] $env:GHOST_DEPLOY_API_KEY
    }
    foreach ($name in $Argument.Keys) {
        $entry[$name] = $Argument[$name]
    }

    $line = (ConvertTo-Json -InputObject $entry -Depth 4 -Compress) + "`n"
    [System.IO.File]::AppendAllText($env:GHOST_STUB_LOG, $line, [System.Text.UTF8Encoding]::new($false))
}

function Get-StubPlan {
    <#
    .SYNOPSIS
        Returns what the plan of the test says about a command.

    .DESCRIPTION
        Reads the JSON file in GHOST_STUB_PLAN and returns the property with the given name, or nothing when
        there is no plan or no such property.

    .EXAMPLE
        Get-StubPlan -Name 'Sync-GhostPost'

        Returns the results that Sync-GhostPost has to return in this test.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        # The name of a property of the plan: a command, Fail or Warning.
        [Parameter(Mandatory)]
        [string] $Name
    )

    if (-not $env:GHOST_STUB_PLAN -or -not (Test-Path -LiteralPath $env:GHOST_STUB_PLAN)) {
        return
    }

    $text = [System.IO.File]::ReadAllText($env:GHOST_STUB_PLAN, [System.Text.Encoding]::UTF8)
    $plan = ConvertFrom-Json -InputObject $text
    $property = $plan.PSObject.Properties[$Name]
    if ($property) {
        $property.Value
    }
}

function Invoke-StubSync {
    <#
    .SYNOPSIS
        Does what the plan of the test says for a Sync command.

    .DESCRIPTION
        Writes the warning of the plan for the command, throws when the plan says that the command fails, and
        returns the results of the plan.

        A result of the plan names its file from the folder of the content, as File. The result that is
        returned has the full path instead, as the real module gives it. A result with Previous set to true is
        about a file that was removed, and its path is below the folder with the earlier files.

    .EXAMPLE
        Invoke-StubSync -Command 'Sync-GhostPost' -Path ./posts -PreviousPath $before

        Returns the results that the plan has for Sync-GhostPost.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        # The name of the Sync command.
        [Parameter(Mandatory)]
        [string] $Command,

        # The folder with the current files.
        [Parameter(Mandatory)]
        [string] $Path,

        # The folder with the earlier files.
        [string] $PreviousPath
    )

    $warning = Get-StubPlan -Name 'Warning'
    if ($warning -and $warning.PSObject.Properties[$Command]) {
        Write-Warning -Message $warning.PSObject.Properties[$Command].Value
    }

    if ((Get-StubPlan -Name 'Fail') -eq $Command) {
        throw "$Command failed, as the plan of the test says."
    }

    foreach ($item in @(Get-StubPlan -Name $Command)) {
        if (-not $item) {
            continue
        }

        $row = [ordered]@{}
        foreach ($property in $item.PSObject.Properties) {
            if (@('File', 'Previous') -notcontains $property.Name) {
                $row[$property.Name] = $property.Value
            }
        }

        $folder = (Resolve-Path -LiteralPath $Path).ProviderPath
        $previous = $item.PSObject.Properties['Previous']
        if ($previous -and $previous.Value -and $PreviousPath) {
            $folder = $PreviousPath
        }
        $file = $item.PSObject.Properties['File']
        if ($file) {
            $row['Path'] = Join-Path -Path $folder -ChildPath $file.Value
        }

        [pscustomobject] $row
    }
}

function Get-StubFile {
    <#
    .SYNOPSIS
        Lists the Markdown files below a folder, for the log of the stand-in.

    .DESCRIPTION
        Returns the paths of the .md files below the folder, from that folder and with forward slashes, in
        order. A test reads them back to see which earlier files a command was given.

    .EXAMPLE
        Get-StubFile -Path $before

        Returns, for example, about/index.md.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        # The folder to list. Without a folder nothing is returned.
        [string] $Path
    )

    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) {
        return
    }

    $root = (Resolve-Path -LiteralPath $Path).ProviderPath
    Get-ChildItem -LiteralPath $root -File -Recurse |
        Where-Object { $_.Extension -eq '.md' } |
        ForEach-Object { [string] [System.IO.Path]::GetRelativePath($root, $_.FullName).Replace('\', '/') } |
        Sort-Object
}

function Connect-Ghost {
    <#
    .SYNOPSIS
        Stands in for Connect-Ghost of the module Ghost.

    .DESCRIPTION
        Logs the call and returns a connection to a site that does not exist. The key is not logged. The log
        only says how long it was, so that a test can tell that the right text arrived.

    .EXAMPLE
        Connect-Ghost -Url 'https://ghost.test' -AdminApiKey $key

        Returns a connection with the title Stub site.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        # The address of the site.
        [string] $Url,

        # The key of the site.
        [securestring] $AdminApiKey
    )

    $length = [System.Net.NetworkCredential]::new('', $AdminApiKey).Password.Length
    Write-StubCall -Command 'Connect-Ghost' -Argument @{ Url = $Url; KeyLength = $length }

    [pscustomobject]@{
        Url        = $Url
        Title      = 'Stub site'
        Version    = '6.0'
        ApiVersion = 'v6.0'
    }
}

function Disconnect-Ghost {
    <#
    .SYNOPSIS
        Stands in for Disconnect-Ghost of the module Ghost.

    .DESCRIPTION
        Logs the call and does nothing else.

    .EXAMPLE
        Disconnect-Ghost

        Adds the call to the log.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param()

    Write-StubCall -Command 'Disconnect-Ghost'
}

function Sync-GhostTheme {
    <#
    .SYNOPSIS
        Stands in for Sync-GhostTheme of the module Ghost.

    .DESCRIPTION
        Logs the call and returns the results that the plan of the test has for this command.

    .EXAMPLE
        Sync-GhostTheme -Path ./theme -WhatIf

        Adds the call to the log, as a dry run.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        # The folder or the zip file of the theme.
        [Parameter(Mandatory)]
        [string] $Path,

        # The name to store the theme under.
        [string] $Name
    )

    $call = @{
        Command  = 'Sync-GhostTheme'
        Argument = @{ Path = $Path; Name = $Name }
        DryRun   = -not $PSCmdlet.ShouldProcess($Path, 'Bring the site in line with the files')
        Asks     = [string] $ConfirmPreference
    }
    Write-StubCall @call
    Invoke-StubSync -Command 'Sync-GhostTheme' -Path $Path
}

function Sync-GhostTag {
    <#
    .SYNOPSIS
        Stands in for Sync-GhostTag of the module Ghost.

    .DESCRIPTION
        Logs the call, with the earlier files it was given, and returns the results that the plan of the test
        has for this command.

    .EXAMPLE
        Sync-GhostTag -Path ./tags -PreviousPath $before -Confirm:$false

        Adds the call to the log.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        # The folder with the files of the tags.
        [Parameter(Mandatory)]
        [string[]] $Path,

        # The folder with the files as they were before.
        [string[]] $PreviousPath
    )

    $before = if ($PreviousPath) { $PreviousPath[0] } else { '' }
    $call = @{
        Command  = 'Sync-GhostTag'
        Argument = @{
            Path          = $Path[0]
            Files         = @(Get-StubFile -Path $Path[0])
            HasPrevious   = [bool] $PreviousPath
            PreviousFiles = @(Get-StubFile -Path $before)
        }
        DryRun   = -not $PSCmdlet.ShouldProcess($Path[0], 'Bring the site in line with the files')
        Asks     = [string] $ConfirmPreference
    }
    Write-StubCall @call
    Invoke-StubSync -Command 'Sync-GhostTag' -Path $Path[0] -PreviousPath $before
}

function Sync-GhostPage {
    <#
    .SYNOPSIS
        Stands in for Sync-GhostPage of the module Ghost.

    .DESCRIPTION
        Logs the call, with the earlier files it was given, and returns the results that the plan of the test
        has for this command.

    .EXAMPLE
        Sync-GhostPage -Path ./pages -Recurse -PreviousPath $before -Confirm:$false

        Adds the call to the log.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        # The folder with the files of the pages.
        [Parameter(Mandatory)]
        [string[]] $Path,

        # Also use the files in the folders below the folder.
        [switch] $Recurse,

        # The folder with the files as they were before.
        [string[]] $PreviousPath
    )

    $before = if ($PreviousPath) { $PreviousPath[0] } else { '' }
    $call = @{
        Command  = 'Sync-GhostPage'
        Argument = @{
            Path          = $Path[0]
            Files         = @(Get-StubFile -Path $Path[0])
            Recurse       = $Recurse.IsPresent
            HasPrevious   = [bool] $PreviousPath
            PreviousFiles = @(Get-StubFile -Path $before)
        }
        DryRun   = -not $PSCmdlet.ShouldProcess($Path[0], 'Bring the site in line with the files')
        Asks     = [string] $ConfirmPreference
    }
    Write-StubCall @call
    Invoke-StubSync -Command 'Sync-GhostPage' -Path $Path[0] -PreviousPath $before
}

function Sync-GhostPost {
    <#
    .SYNOPSIS
        Stands in for Sync-GhostPost of the module Ghost.

    .DESCRIPTION
        Logs the call, with the earlier files it was given, and returns the results that the plan of the test
        has for this command.

    .EXAMPLE
        Sync-GhostPost -Path ./posts -Recurse -PreviousPath $before -Confirm:$false

        Adds the call to the log.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        # The folder with the files of the posts.
        [Parameter(Mandatory)]
        [string[]] $Path,

        # Also use the files in the folders below the folder.
        [switch] $Recurse,

        # The folder with the files as they were before.
        [string[]] $PreviousPath
    )

    $before = if ($PreviousPath) { $PreviousPath[0] } else { '' }
    $call = @{
        Command  = 'Sync-GhostPost'
        Argument = @{
            Path          = $Path[0]
            Files         = @(Get-StubFile -Path $Path[0])
            Recurse       = $Recurse.IsPresent
            HasPrevious   = [bool] $PreviousPath
            PreviousFiles = @(Get-StubFile -Path $before)
        }
        DryRun   = -not $PSCmdlet.ShouldProcess($Path[0], 'Bring the site in line with the files')
        Asks     = [string] $ConfirmPreference
    }
    Write-StubCall @call
    Invoke-StubSync -Command 'Sync-GhostPost' -Path $Path[0] -PreviousPath $before
}

Export-ModuleMember -Function @(
    'Connect-Ghost'
    'Disconnect-Ghost'
    'Sync-GhostTheme'
    'Sync-GhostTag'
    'Sync-GhostPage'
    'Sync-GhostPost'
)
