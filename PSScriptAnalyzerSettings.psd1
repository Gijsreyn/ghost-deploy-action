@{
    # Every default rule of PSScriptAnalyzer applies, at every severity. The rules below are the ones that are
    # off by default or need settings. tests/Unit/PSScriptAnalyzer.Tests.ps1 fails on any finding.
    Rules = @{
        PSAlignAssignmentStatement                = @{
            Enable         = $true
            CheckHashtable = $true
        }
        PSAvoidExclaimOperator                    = @{
            Enable = $true
        }
        PSAvoidLongLines                          = @{
            Enable            = $true
            MaximumLineLength = 120
        }
        PSAvoidSemicolonsAsLineTerminators        = @{
            Enable = $true
        }
        PSAvoidUsingDoubleQuotesForConstantString = @{
            Enable = $true
        }
        PSPlaceCloseBrace                         = @{
            Enable             = $true
            IgnoreOneLineBlock = $true
            NewLineAfter       = $true
            NoEmptyLineBefore  = $true
        }
        PSPlaceOpenBrace                          = @{
            Enable             = $true
            IgnoreOneLineBlock = $true
            NewLineAfter       = $true
            OnSameLine         = $true
        }
        PSProvideCommentHelp                      = @{
            Enable                  = $true
            BlockComment            = $true
            ExportedOnly            = $false
            Placement               = 'begin'
            VSCodeSnippetCorrection = $false
        }
        PSUseConsistentIndentation                = @{
            Enable              = $true
            IndentationSize     = 4
            Kind                = 'space'
            PipelineIndentation = 'IncreaseIndentationForFirstPipeline'
        }
        PSUseConsistentWhitespace                 = @{
            Enable                                  = $true
            CheckInnerBrace                         = $true
            CheckOpenBrace                          = $true
            CheckOpenParen                          = $true
            CheckOperator                           = $true
            CheckParameter                          = $true
            CheckPipe                               = $true
            CheckPipeForRedundantWhitespace         = $true
            CheckSeparator                          = $true
            IgnoreAssignmentOperatorInsideHashTable = $true
        }
        # The casing of keywords and operators is checked. That of command and parameter names is not. That part
        # of the rule looks commands up in a way that makes PSScriptAnalyzer 1.25 fail at random with a
        # NullReferenceException, which would break the build without a finding to fix.
        PSUseCorrectCasing                        = @{
            Enable        = $true
            CheckCommands = $false
            CheckKeyword  = $true
            CheckOperator = $true
        }
    }
}
