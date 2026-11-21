<#
.SYNOPSIS
    Runs the unit tests of the action with Pester.

.DESCRIPTION
    Runs the tests in tests/Unit, writes the result as NUnit XML to the folder TestResults and fails when a test
    fails.

    The unit tests need no Ghost site. They run the scripts of the action against a stand-in for the module
    Ghost, and against repositories that they make in a temporary folder. They include the rules of
    PSScriptAnalyzer.

    tests/Invoke-EndToEnd.ps1 is the test against a real Ghost site, on your own machine.

    Needs Pester 6 and PowerShell 7.4 or later.

.EXAMPLE
    ./build/Invoke-RunTests.ps1

    Runs the unit tests.
#>
#Requires -Version 7.4
[CmdletBinding()]
[OutputType([void])]
param(
    # Folder to write the test results to. Defaults to TestResults in the root of the repository.
    [string] $OutputPath
)

$ErrorActionPreference = 'Stop'
$InformationPreference = 'Continue'

$repositoryRoot = Split-Path -Path $PSScriptRoot -Parent
if (-not $OutputPath) {
    $OutputPath = Join-Path -Path $repositoryRoot -ChildPath 'TestResults'
}

Import-Module -Name 'Pester' -MinimumVersion '6.0.0'

$configuration = New-PesterConfiguration
$configuration.Run.Path = Join-Path -Path $repositoryRoot -ChildPath 'tests/Unit'
$configuration.Run.PassThru = $true
$configuration.Output.Verbosity = 'Detailed'
$configuration.TestResult.Enabled = $true
$configuration.TestResult.OutputFormat = 'NUnitXml'
$configuration.TestResult.OutputPath = Join-Path -Path $OutputPath -ChildPath 'Unit.xml'

$result = Invoke-Pester -Configuration $configuration

if ($result.Result -ne 'Passed') {
    throw "The unit tests did not pass: $($result.FailedCount) failed of $($result.TotalCount)."
}
Write-Information -MessageData "The unit tests passed: $($result.PassedCount) passed, $($result.SkippedCount) skipped."
