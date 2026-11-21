function Get-DeployInput {
    <#
    .SYNOPSIS
        Reads the inputs of the action from the environment and checks them.

    .DESCRIPTION
        A composite action does not get its inputs by itself. The file action.yml passes every input to the
        script as an environment variable with a name that starts with GHOST_DEPLOY_. This function reads them
        and returns one object with a property per input.

        The inputs are checked before anything is sent to the site:

        - The address of the site and the key are required. An empty key usually means that the run is for a
          pull request from a fork, which does not get the secrets of a repository. The message says so.
        - At least one of theme, tags, pages and posts has to be given.
        - An input that is true or false has to be exactly that. The text is compared, because PowerShell
          takes any text that is not empty for true, the text false included.
        - The limit for removals is a whole number of zero or more.

        The key is returned as a secure string, which is what Connect-Ghost takes. It is never written anywhere.

    .EXAMPLE
        Get-DeployInput

        Returns the inputs of the current run.

    .EXAMPLE
        Get-DeployInput -Environment @{ GHOST_DEPLOY_API_URL = 'https://example.org'; GHOST_DEPLOY_POSTS = 'posts' }

        Throws, because the key is missing.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        # The variables to read the inputs from. Defaults to the environment of this process.
        [System.Collections.IDictionary] $Environment = [System.Environment]::GetEnvironmentVariables()
    )

    # The inputs by their name, without the prefix and without the spaces around their text.
    $inputs = @{}
    foreach ($key in $Environment.Keys) {
        if ([string] $key -like 'GHOST_DEPLOY_*') {
            $inputs[([string] $key).Substring('GHOST_DEPLOY_'.Length)] = ([string] $Environment[$key]).Trim()
        }
    }

    # The text of an input. An input that was not given is empty text.
    $read = {
        param([string] $Name)

        if ($inputs.ContainsKey($Name)) {
            return $inputs[$Name]
        }
        ''
    }

    # An input that is true or false. Without a value it is false.
    $readSwitch = {
        param([string] $Name, [string] $InputName)

        $text = & $read $Name
        if ($text -eq '' -or $text -eq 'false') {
            return $false
        }
        if ($text -eq 'true') {
            return $true
        }
        throw "The input $InputName has to be true or false. It is '$text'."
    }

    $url = & $read 'API_URL'
    if (-not $url) {
        throw 'The input api-url is empty. Give it the address of the Ghost site, such as https://example.org.'
    }

    $key = & $read 'API_KEY'
    if (-not $key) {
        $fork = 'A pull request from a fork does not get the secrets of a repository, so it cannot run this action.'
        throw "The input api-key is empty. Give it the Admin API key of the site, as a secret. $fork"
    }
    $secureKey = [securestring]::new()
    foreach ($character in $key.ToCharArray()) {
        $secureKey.AppendChar($character)
    }
    $secureKey.MakeReadOnly()

    $content = [ordered]@{
        Theme = & $read 'THEME'
        Tags  = & $read 'TAGS'
        Pages = & $read 'PAGES'
        Posts = & $read 'POSTS'
    }
    if (-not ($content.Values | Where-Object { $_ })) {
        throw 'There is nothing to deploy. Give at least one of the inputs theme, tags, pages and posts.'
    }

    $limitText = & $read 'DELETE_LIMIT'
    $limit = 10
    if ($limitText) {
        if (-not [int]::TryParse($limitText, [ref] $limit) -or $limit -lt 0) {
            throw "The input delete-limit has to be a whole number of zero or more. It is '$limitText'."
        }
    }

    $version = & $read 'MODULE_VERSION'
    $modulePath = & $read 'MODULE_PATH'
    if (-not $version -and -not $modulePath) {
        throw 'The input module-version is empty. Leave it out to use the version this action was tested with.'
    }

    [pscustomobject]@{
        ApiUrl        = $url
        ApiKey        = $secureKey
        Theme         = $content['Theme']
        ThemeName     = & $read 'THEME_NAME'
        Tags          = $content['Tags']
        Pages         = $content['Pages']
        Posts         = $content['Posts']
        Delete        = & $readSwitch 'DELETE' 'delete'
        DeleteLimit   = $limit
        BaseRef       = & $read 'BASE_REF'
        DryRun        = & $readSwitch 'DRY_RUN' 'dry-run'
        ModuleVersion = $version
        ModulePath    = $modulePath
    }
}
