#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.0.0' }
<#
    Every script in the repository has to pass PSScriptAnalyzer with the rules in PSScriptAnalyzerSettings.psd1,
    without a single finding.

    The analysis runs in a process of its own, through build/Invoke-Analyzer.ps1. PSScriptAnalyzer is not
    reliable inside a test run, where Pester is loaded: it fails at random with errors of its own. The analysis
    happens during discovery, so that every file gets a test of its own.
#>

BeforeDiscovery {
    $repositoryRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    $arguments = @(
        '-NoProfile'
        '-NonInteractive'
        '-File'
        Join-Path -Path $repositoryRoot -ChildPath 'build/Invoke-Analyzer.ps1'
        '-AsJson'
    )

    $powershell = (Get-Process -Id $PID).Path
    $output = & $powershell @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "build/Invoke-Analyzer.ps1 failed with exit code ${LASTEXITCODE}: $($output | Out-String)"
    }

    $script:Files = @(
        ConvertFrom-Json -InputObject ($output | Out-String) |
            ForEach-Object { $_ } |
            ForEach-Object { @{ File = $_.File; Findings = @($_.Findings) } }
    )
}

Describe 'PSScriptAnalyzer' -Tag 'Unit', 'Analyzer' {
    It 'analyzed the scripts of the repository' -ForEach @{ Analyzed = $script:Files.Count } {
        # Guards against a run that silently analyzed nothing.
        $Analyzed | Should -BeGreaterThan 15
    }

    It '<File> has no findings' -ForEach $script:Files {
        $Findings | Should -BeNullOrEmpty
    }
}
