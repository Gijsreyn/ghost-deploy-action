<#
.SYNOPSIS
    Checks every script of the repository with PSScriptAnalyzer.

.DESCRIPTION
    Analyzes the scripts in src, build, tests and examples with the rules in PSScriptAnalyzerSettings.psd1 and
    returns one object per file, with the findings for that file.

    tests/Unit/PSScriptAnalyzer.Tests.ps1 runs this script in a process of its own and fails for every file
    with findings.

.EXAMPLE
    ./build/Invoke-Analyzer.ps1 | Where-Object Findings

    Shows the files that have findings.
#>
#Requires -Version 7.4
[CmdletBinding()]
[OutputType([pscustomobject])]
param(
    # Return the result as JSON, for a caller in another process.
    [switch] $AsJson
)

$ErrorActionPreference = 'Stop'

Import-Module -Name 'PSScriptAnalyzer' -MinimumVersion '1.25.0'

$repositoryRoot = Split-Path -Path $PSScriptRoot -Parent
$settingsPath = Join-Path -Path $repositoryRoot -ChildPath 'PSScriptAnalyzerSettings.psd1'

$folders = 'src', 'build', 'tests', 'examples' |
    ForEach-Object { Join-Path -Path $repositoryRoot -ChildPath $_ } |
    Where-Object { Test-Path -LiteralPath $_ }
$files = @(
    Get-ChildItem -Path $folders -Include '*.ps1', '*.psm1', '*.psd1' -File -Recurse
    Get-Item -LiteralPath $settingsPath
)

$result = foreach ($file in $files | Sort-Object -Property FullName) {
    $findings = Invoke-ScriptAnalyzer -Path $file.FullName -Settings $settingsPath

    [pscustomobject]@{
        File     = $file.FullName.Substring($repositoryRoot.Length + 1).Replace('\', '/')
        Findings = @(
            $findings | ForEach-Object { '{0} at line {1}: {2}' -f $_.RuleName, $_.Line, $_.Message }
        )
    }
}

if ($AsJson) {
    ConvertTo-Json -InputObject @($result) -Depth 3 -Compress
}
else {
    $result
}
