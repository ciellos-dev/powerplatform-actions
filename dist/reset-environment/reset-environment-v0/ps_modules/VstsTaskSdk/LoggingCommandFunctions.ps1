$script:loggingCommandPrefix = '##vso['
$script:loggingCommandEscapeMappings = @( # TODO: WHAT ABOUT "="? WHAT ABOUT "%"?
    New-Object psobject -Property @{ Token = ';' ; Replacement = '%3B' }
    New-Object psobject -Property @{ Token = "`r" ; Replacement = '%0D' }
    New-Object psobject -Property @{ Token = "`n" ; Replacement = '%0A' }
    New-Object psobject -Property @{ Token = "]" ; Replacement = '%5D' }
)
# TODO: BUG: Escape % ???
# TODO: Add test to verify don't need to escape "=".

<#
.SYNOPSIS
See https://github.com/Microsoft/vsts-tasks/blob/master/docs/authoring/commands.md

.PARAMETER AsOutput
Indicates whether to write the logging command directly to the host or to the output pipeline.
#>
function Write-AddAttachment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Type,
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [switch]$AsOutput)

    Write-LoggingCommand -Area 'task' -Event 'addattachment' -Data $Path -Properties @{
            'type' = $Type
            'name' = $Name
        } -AsOutput:$AsOutput
}

<#
.SYNOPSIS
See https://github.com/Microsoft/vsts-tasks/blob/master/docs/authoring/commands.md

.PARAMETER AsOutput
Indicates whether to write the logging command directly to the host or to the output pipeline.
#>
function Write-UploadSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [switch]$AsOutput)

    Write-LoggingCommand -Area 'task' -Event 'uploadsummary' -Data $Path -AsOutput:$AsOutput
}

<#
.SYNOPSIS
See https://github.com/Microsoft/vsts-tasks/blob/master/docs/authoring/commands.md

.PARAMETER AsOutput
Indicates whether to write the logging command directly to the host or to the output pipeline.
#>
function Write-SetEndpoint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Id,
        [Parameter(Mandatory = $true)]
        [string]$Field,
        [Parameter(Mandatory = $true)]
        [string]$Key,
        [Parameter(Mandatory = $true)]
        [string]$Value,
        [switch]$AsOutput)

    Write-LoggingCommand -Area 'task' -Event 'setendpoint' -Data $Value -Properties @{
            'id' = $Id
            'field' = $Field
            'key' = $Key
        } -AsOutput:$AsOutput
}

<#
.SYNOPSIS
See https://github.com/Microsoft/vsts-tasks/blob/master/docs/authoring/commands.md

.PARAMETER AsOutput
Indicates whether to write the logging command directly to the host or to the output pipeline.
#>
function Write-AddBuildTag {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value,
        [switch]$AsOutput)

    Write-LoggingCommand -Area 'build' -Event 'addbuildtag' -Data $Value -AsOutput:$AsOutput
}

<#
.SYNOPSIS
See https://github.com/Microsoft/vsts-tasks/blob/master/docs/authoring/commands.md

.PARAMETER AsOutput
Indicates whether to write the logging command directly to the host or to the output pipeline.
#>
function Write-AssociateArtifact {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$Type,
        [hashtable]$Properties,
        [switch]$AsOutput)

    $p = @{ }
    if ($Properties) {
        foreach ($key in $Properties.Keys) {
            $p[$key] = $Properties[$key]
        }
    }

    $p['artifactname'] = $Name
    $p['artifacttype'] = $Type
    Write-LoggingCommand -Area 'artifact' -Event 'associate' -Data $Path -Properties $p -AsOutput:$AsOutput
}

<#
.SYNOPSIS
See https://github.com/Microsoft/vsts-tasks/blob/master/docs/authoring/commands.md

.PARAMETER AsOutput
Indicates whether to write the logging command directly to the host or to the output pipeline.
#>
function Write-LogDetail {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [guid]$Id,
        $ParentId,
        [string]$Type,
        [string]$Name,
        $Order,
        $StartTime,
        $FinishTime,
        $Progress,
        [ValidateSet('Unknown', 'Initialized', 'InProgress', 'Completed')]
        [Parameter()]
        $State,
        [ValidateSet('Succeeded', 'SucceededWithIssues', 'Failed', 'Cancelled', 'Skipped')]
        [Parameter()]
        $Result,
        [string]$Message,
        [switch]$AsOutput)

    Write-LoggingCommand -Area 'task' -Event 'logdetail' -Data $Message -Properties @{
            'id' = $Id
            'parentid' = $ParentId
            'type' = $Type
            'name' = $Name
            'order' = $Order
            'starttime' = $StartTime
            'finishtime' = $FinishTime
            'progress' = $Progress
            'state' = $State
            'result' = $Result
        } -AsOutput:$AsOutput
}

<#
.SYNOPSIS
See https://github.com/Microsoft/vsts-tasks/blob/master/docs/authoring/commands.md

.PARAMETER AsOutput
Indicates whether to write the logging command directly to the host or to the output pipeline.
#>
function Write-SetProgress {
    [CmdletBinding()]
    param(
        [ValidateRange(0, 100)]
        [Parameter(Mandatory = $true)]
        [int]$Percent,
        [string]$CurrentOperation,
        [switch]$AsOutput)

    Write-LoggingCommand -Area 'task' -Event 'setprogress' -Data $CurrentOperation -Properties @{
            'value' = $Percent
        } -AsOutput:$AsOutput
}

<#
.SYNOPSIS
See https://github.com/Microsoft/vsts-tasks/blob/master/docs/authoring/commands.md

.PARAMETER AsOutput
Indicates whether to write the logging command directly to the host or to the output pipeline.
#>
function Write-SetResult {
    [CmdletBinding(DefaultParameterSetName = 'AsOutput')]
    param(
        [ValidateSet("Succeeded", "SucceededWithIssues", "Failed", "Cancelled", "Skipped")]
        [Parameter(Mandatory = $true)]
        [string]$Result,
        [string]$Message,
        [Parameter(ParameterSetName = 'AsOutput')]
        [switch]$AsOutput,
        [Parameter(ParameterSetName = 'DoNotThrow')]
        [switch]$DoNotThrow)

    Write-LoggingCommand -Area 'task' -Event 'complete' -Data $Message -Properties @{
            'result' = $Result
        } -AsOutput:$AsOutput
    if ($Result -eq 'Failed' -and !$AsOutput -and !$DoNotThrow) {
        # Special internal exception type to control the flow. Not currently intended
        # for public usage and subject to change.
        throw (New-Object VstsTaskSdk.TerminationException($Message))
    }
}

<#
.SYNOPSIS
See https://github.com/Microsoft/vsts-tasks/blob/master/docs/authoring/commands.md

.PARAMETER AsOutput
Indicates whether to write the logging command directly to the host or to the output pipeline.
#>
function Write-SetSecret {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value,
        [switch]$AsOutput)

    Write-LoggingCommand -Area 'task' -Event 'setsecret' -Data $Value -AsOutput:$AsOutput
}

<#
.SYNOPSIS
See https://github.com/Microsoft/vsts-tasks/blob/master/docs/authoring/commands.md

.PARAMETER AsOutput
Indicates whether to write the logging command directly to the host or to the output pipeline.
#>
function Write-SetVariable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [string]$Value,
        [switch]$Secret,
        [switch]$AsOutput)

    Write-LoggingCommand -Area 'task' -Event 'setvariable' -Data $Value -Properties @{
            'variable' = $Name
            'issecret' = $Secret
        } -AsOutput:$AsOutput
}

<#
.SYNOPSIS
See https://github.com/Microsoft/vsts-tasks/blob/master/docs/authoring/commands.md

.PARAMETER AsOutput
Indicates whether to write the logging command directly to the host or to the output pipeline.
#>
function Write-TaskDebug {
    [CmdletBinding()]
    param(
        [string]$Message,
        [switch]$AsOutput)

    Write-TaskDebug_Internal @PSBoundParameters
}

<#
.SYNOPSIS
See https://github.com/Microsoft/vsts-tasks/blob/master/docs/authoring/commands.md

.PARAMETER AsOutput
Indicates whether to write the logging command directly to the host or to the output pipeline.
#>
function Write-TaskError {
    [CmdletBinding()]
    param(
        [string]$Message,
        [string]$ErrCode,
        [string]$SourcePath,
        [string]$LineNumber,
        [string]$ColumnNumber,
        [switch]$AsOutput)

    Write-LogIssue -Type error @PSBoundParameters
}

<#
.SYNOPSIS
See https://github.com/Microsoft/vsts-tasks/blob/master/docs/authoring/commands.md

.PARAMETER AsOutput
Indicates whether to write the logging command directly to the host or to the output pipeline.
#>
function Write-TaskVerbose {
    [CmdletBinding()]
    param(
        [string]$Message,
        [switch]$AsOutput)

    Write-TaskDebug_Internal @PSBoundParameters -AsVerbose
}

<#
.SYNOPSIS
See https://github.com/Microsoft/vsts-tasks/blob/master/docs/authoring/commands.md

.PARAMETER AsOutput
Indicates whether to write the logging command directly to the host or to the output pipeline.
#>
function Write-TaskWarning {
    [CmdletBinding()]
    param(
        [string]$Message,
        [string]$ErrCode,
        [string]$SourcePath,
        [string]$LineNumber,
        [string]$ColumnNumber,
        [switch]$AsOutput)

    Write-LogIssue -Type warning @PSBoundParameters
}

<#
.SYNOPSIS
See https://github.com/Microsoft/vsts-tasks/blob/master/docs/authoring/commands.md

.PARAMETER AsOutput
Indicates whether to write the logging command directly to the host or to the output pipeline.
#>
function Write-UploadFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [switch]$AsOutput)

    Write-LoggingCommand -Area 'task' -Event 'uploadfile' -Data $Path -AsOutput:$AsOutput
}

<#
.SYNOPSIS
See https://github.com/Microsoft/vsts-tasks/blob/master/docs/authoring/commands.md

.PARAMETER AsOutput
Indicates whether to write the logging command directly to the host or to the output pipeline.
#>
function Write-PrependPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [switch]$AsOutput)

    Write-LoggingCommand -Area 'task' -Event 'prependpath' -Data $Path -AsOutput:$AsOutput
}

<#
.SYNOPSIS
See https://github.com/Microsoft/vsts-tasks/blob/master/docs/authoring/commands.md

.PARAMETER AsOutput
Indicates whether to write the logging command directly to the host or to the output pipeline.
#>
function Write-UpdateBuildNumber {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value,
        [switch]$AsOutput)

    Write-LoggingCommand -Area 'build' -Event 'updatebuildnumber' -Data $Value -AsOutput:$AsOutput
}

<#
.SYNOPSIS
See https://github.com/Microsoft/vsts-tasks/blob/master/docs/authoring/commands.md

.PARAMETER AsOutput
Indicates whether to write the logging command directly to the host or to the output pipeline.
#>
function Write-UploadArtifact {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ContainerFolder,
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [switch]$AsOutput)

    Write-LoggingCommand -Area 'artifact' -Event 'upload' -Data $Path -Properties @{
            'containerfolder' = $ContainerFolder
            'artifactname' = $Name
        } -AsOutput:$AsOutput
}

<#
.SYNOPSIS
See https://github.com/Microsoft/vsts-tasks/blob/master/docs/authoring/commands.md

.PARAMETER AsOutput
Indicates whether to write the logging command directly to the host or to the output pipeline.
#>
function Write-UploadBuildLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [switch]$AsOutput)

    Write-LoggingCommand -Area 'build' -Event 'uploadlog' -Data $Path -AsOutput:$AsOutput
}

<#
.SYNOPSIS
See https://github.com/Microsoft/vsts-tasks/blob/master/docs/authoring/commands.md

.PARAMETER AsOutput
Indicates whether to write the logging command directly to the host or to the output pipeline.
#>
function Write-UpdateReleaseName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [switch]$AsOutput)

    Write-LoggingCommand -Area 'release' -Event 'updatereleasename' -Data $Name -AsOutput:$AsOutput
}

########################################
# Private functions.
########################################
function Format-LoggingCommandData {
    [CmdletBinding()]
    param([string]$Value, [switch]$Reverse)

    if (!$Value) {
        return ''
    }

    if (!$Reverse) {
        foreach ($mapping in $script:loggingCommandEscapeMappings) {
            $Value = $Value.Replace($mapping.Token, $mapping.Replacement)
        }
    } else {
        for ($i = $script:loggingCommandEscapeMappings.Length - 1 ; $i -ge 0 ; $i--) {
            $mapping = $script:loggingCommandEscapeMappings[$i]
            $Value = $Value.Replace($mapping.Replacement, $mapping.Token)
        }
    }

    return $Value
}

function Format-LoggingCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Area,
        [Parameter(Mandatory = $true)]
        [string]$Event,
        [string]$Data,
        [hashtable]$Properties)

    # Append the preamble.
    [System.Text.StringBuilder]$sb = New-Object -TypeName System.Text.StringBuilder
    $null = $sb.Append($script:loggingCommandPrefix).Append($Area).Append('.').Append($Event)

    # Append the properties.
    if ($Properties) {
        $first = $true
        foreach ($key in $Properties.Keys) {
            [string]$value = Format-LoggingCommandData $Properties[$key]
            if ($value) {
                if ($first) {
                    $null = $sb.Append(' ')
                    $first = $false
                } else {
                    $null = $sb.Append(';')
                }

                $null = $sb.Append("$key=$value")
            }
        }
    }

    # Append the tail and output the value.
    $Data = Format-LoggingCommandData $Data
    $sb.Append(']').Append($Data).ToString()
}

function Write-LoggingCommand {
    [CmdletBinding(DefaultParameterSetName = 'Parameters')]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Parameters')]
        [string]$Area,
        [Parameter(Mandatory = $true, ParameterSetName = 'Parameters')]
        [string]$Event,
        [Parameter(ParameterSetName = 'Parameters')]
        [string]$Data,
        [Parameter(ParameterSetName = 'Parameters')]
        [hashtable]$Properties,
        [Parameter(Mandatory = $true, ParameterSetName = 'Object')]
        $Command,
        [switch]$AsOutput)

    if ($PSCmdlet.ParameterSetName -eq 'Object') {
        Write-LoggingCommand -Area $Command.Area -Event $Command.Event -Data $Command.Data -Properties $Command.Properties -AsOutput:$AsOutput
        return
    }

    $command = Format-LoggingCommand -Area $Area -Event $Event -Data $Data -Properties $Properties
    if ($AsOutput) {
        $command
    } else {
        Write-Host $command
    }
}

function Write-LogIssue {
    [CmdletBinding()]
    param(
        [ValidateSet('warning', 'error')]
        [Parameter(Mandatory = $true)]
        [string]$Type,
        [string]$Message,
        [string]$ErrCode,
        [string]$SourcePath,
        [string]$LineNumber,
        [string]$ColumnNumber,
        [switch]$AsOutput)

    $command = Format-LoggingCommand -Area 'task' -Event 'logissue' -Data $Message -Properties @{
            'type' = $Type
            'code' = $ErrCode
            'sourcepath' = $SourcePath
            'linenumber' = $LineNumber
            'columnnumber' = $ColumnNumber
        }
    if ($AsOutput) {
        return $command
    }

    if ($Type -eq 'error') {
        $foregroundColor = $host.PrivateData.ErrorForegroundColor
        $backgroundColor = $host.PrivateData.ErrorBackgroundColor
        if ($foregroundColor -isnot [System.ConsoleColor] -or $backgroundColor -isnot [System.ConsoleColor]) {
            $foregroundColor = [System.ConsoleColor]::Red
            $backgroundColor = [System.ConsoleColor]::Black
        }
    } else {
        $foregroundColor = $host.PrivateData.WarningForegroundColor
        $backgroundColor = $host.PrivateData.WarningBackgroundColor
        if ($foregroundColor -isnot [System.ConsoleColor] -or $backgroundColor -isnot [System.ConsoleColor]) {
            $foregroundColor = [System.ConsoleColor]::Yellow
            $backgroundColor = [System.ConsoleColor]::Black
        }
    }

    Write-Host $command -ForegroundColor $foregroundColor -BackgroundColor $backgroundColor
}

function Write-TaskDebug_Internal {
    [CmdletBinding()]
    param(
        [string]$Message,
        [switch]$AsVerbose,
        [switch]$AsOutput)

    $command = Format-LoggingCommand -Area 'task' -Event 'debug' -Data $Message
    if ($AsOutput) {
        return $command
    }

    if ($AsVerbose) {
        $foregroundColor = $host.PrivateData.VerboseForegroundColor
        $backgroundColor = $host.PrivateData.VerboseBackgroundColor
        if ($foregroundColor -isnot [System.ConsoleColor] -or $backgroundColor -isnot [System.ConsoleColor]) {
            $foregroundColor = [System.ConsoleColor]::Cyan
            $backgroundColor = [System.ConsoleColor]::Black
        }
    } else {
        $foregroundColor = $host.PrivateData.DebugForegroundColor
        $backgroundColor = $host.PrivateData.DebugBackgroundColor
        if ($foregroundColor -isnot [System.ConsoleColor] -or $backgroundColor -isnot [System.ConsoleColor]) {
            $foregroundColor = [System.ConsoleColor]::DarkGray
            $backgroundColor = [System.ConsoleColor]::Black
        }
    }

    Write-Host -Object $command -ForegroundColor $foregroundColor -BackgroundColor $backgroundColor
}

# SIG # Begin signature block
# MIInnAYJKoZIhvcNAQcCoIInjTCCJ4kCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCB0+boANff5ASRR
# lhXMjVOuhUVZV+d7kPDe8VZeK1FniqCCDYEwggX/MIID56ADAgECAhMzAAACUosz
# qviV8znbAAAAAAJSMA0GCSqGSIb3DQEBCwUAMH4xCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNpZ25p
# bmcgUENBIDIwMTEwHhcNMjEwOTAyMTgzMjU5WhcNMjIwOTAxMTgzMjU5WjB0MQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
# ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMR4wHAYDVQQDExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIB
# AQDQ5M+Ps/X7BNuv5B/0I6uoDwj0NJOo1KrVQqO7ggRXccklyTrWL4xMShjIou2I
# sbYnF67wXzVAq5Om4oe+LfzSDOzjcb6ms00gBo0OQaqwQ1BijyJ7NvDf80I1fW9O
# L76Kt0Wpc2zrGhzcHdb7upPrvxvSNNUvxK3sgw7YTt31410vpEp8yfBEl/hd8ZzA
# v47DCgJ5j1zm295s1RVZHNp6MoiQFVOECm4AwK2l28i+YER1JO4IplTH44uvzX9o
# RnJHaMvWzZEpozPy4jNO2DDqbcNs4zh7AWMhE1PWFVA+CHI/En5nASvCvLmuR/t8
# q4bc8XR8QIZJQSp+2U6m2ldNAgMBAAGjggF+MIIBejAfBgNVHSUEGDAWBgorBgEE
# AYI3TAgBBggrBgEFBQcDAzAdBgNVHQ4EFgQUNZJaEUGL2Guwt7ZOAu4efEYXedEw
# UAYDVR0RBEkwR6RFMEMxKTAnBgNVBAsTIE1pY3Jvc29mdCBPcGVyYXRpb25zIFB1
# ZXJ0byBSaWNvMRYwFAYDVQQFEw0yMzAwMTIrNDY3NTk3MB8GA1UdIwQYMBaAFEhu
# ZOVQBdOCqhc3NyK1bajKdQKVMFQGA1UdHwRNMEswSaBHoEWGQ2h0dHA6Ly93d3cu
# bWljcm9zb2Z0LmNvbS9wa2lvcHMvY3JsL01pY0NvZFNpZ1BDQTIwMTFfMjAxMS0w
# Ny0wOC5jcmwwYQYIKwYBBQUHAQEEVTBTMFEGCCsGAQUFBzAChkVodHRwOi8vd3d3
# Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL01pY0NvZFNpZ1BDQTIwMTFfMjAx
# MS0wNy0wOC5jcnQwDAYDVR0TAQH/BAIwADANBgkqhkiG9w0BAQsFAAOCAgEAFkk3
# uSxkTEBh1NtAl7BivIEsAWdgX1qZ+EdZMYbQKasY6IhSLXRMxF1B3OKdR9K/kccp
# kvNcGl8D7YyYS4mhCUMBR+VLrg3f8PUj38A9V5aiY2/Jok7WZFOAmjPRNNGnyeg7
# l0lTiThFqE+2aOs6+heegqAdelGgNJKRHLWRuhGKuLIw5lkgx9Ky+QvZrn/Ddi8u
# TIgWKp+MGG8xY6PBvvjgt9jQShlnPrZ3UY8Bvwy6rynhXBaV0V0TTL0gEx7eh/K1
# o8Miaru6s/7FyqOLeUS4vTHh9TgBL5DtxCYurXbSBVtL1Fj44+Od/6cmC9mmvrti
# yG709Y3Rd3YdJj2f3GJq7Y7KdWq0QYhatKhBeg4fxjhg0yut2g6aM1mxjNPrE48z
# 6HWCNGu9gMK5ZudldRw4a45Z06Aoktof0CqOyTErvq0YjoE4Xpa0+87T/PVUXNqf
# 7Y+qSU7+9LtLQuMYR4w3cSPjuNusvLf9gBnch5RqM7kaDtYWDgLyB42EfsxeMqwK
# WwA+TVi0HrWRqfSx2olbE56hJcEkMjOSKz3sRuupFCX3UroyYf52L+2iVTrda8XW
# esPG62Mnn3T8AuLfzeJFuAbfOSERx7IFZO92UPoXE1uEjL5skl1yTZB3MubgOA4F
# 8KoRNhviFAEST+nG8c8uIsbZeb08SeYQMqjVEmkwggd6MIIFYqADAgECAgphDpDS
# AAAAAAADMA0GCSqGSIb3DQEBCwUAMIGIMQswCQYDVQQGEwJVUzETMBEGA1UECBMK
# V2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0
# IENvcnBvcmF0aW9uMTIwMAYDVQQDEylNaWNyb3NvZnQgUm9vdCBDZXJ0aWZpY2F0
# ZSBBdXRob3JpdHkgMjAxMTAeFw0xMTA3MDgyMDU5MDlaFw0yNjA3MDgyMTA5MDla
# MH4xCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdS
# ZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMT
# H01pY3Jvc29mdCBDb2RlIFNpZ25pbmcgUENBIDIwMTEwggIiMA0GCSqGSIb3DQEB
# AQUAA4ICDwAwggIKAoICAQCr8PpyEBwurdhuqoIQTTS68rZYIZ9CGypr6VpQqrgG
# OBoESbp/wwwe3TdrxhLYC/A4wpkGsMg51QEUMULTiQ15ZId+lGAkbK+eSZzpaF7S
# 35tTsgosw6/ZqSuuegmv15ZZymAaBelmdugyUiYSL+erCFDPs0S3XdjELgN1q2jz
# y23zOlyhFvRGuuA4ZKxuZDV4pqBjDy3TQJP4494HDdVceaVJKecNvqATd76UPe/7
# 4ytaEB9NViiienLgEjq3SV7Y7e1DkYPZe7J7hhvZPrGMXeiJT4Qa8qEvWeSQOy2u
# M1jFtz7+MtOzAz2xsq+SOH7SnYAs9U5WkSE1JcM5bmR/U7qcD60ZI4TL9LoDho33
# X/DQUr+MlIe8wCF0JV8YKLbMJyg4JZg5SjbPfLGSrhwjp6lm7GEfauEoSZ1fiOIl
# XdMhSz5SxLVXPyQD8NF6Wy/VI+NwXQ9RRnez+ADhvKwCgl/bwBWzvRvUVUvnOaEP
# 6SNJvBi4RHxF5MHDcnrgcuck379GmcXvwhxX24ON7E1JMKerjt/sW5+v/N2wZuLB
# l4F77dbtS+dJKacTKKanfWeA5opieF+yL4TXV5xcv3coKPHtbcMojyyPQDdPweGF
# RInECUzF1KVDL3SV9274eCBYLBNdYJWaPk8zhNqwiBfenk70lrC8RqBsmNLg1oiM
# CwIDAQABo4IB7TCCAekwEAYJKwYBBAGCNxUBBAMCAQAwHQYDVR0OBBYEFEhuZOVQ
# BdOCqhc3NyK1bajKdQKVMBkGCSsGAQQBgjcUAgQMHgoAUwB1AGIAQwBBMAsGA1Ud
# DwQEAwIBhjAPBgNVHRMBAf8EBTADAQH/MB8GA1UdIwQYMBaAFHItOgIxkEO5FAVO
# 4eqnxzHRI4k0MFoGA1UdHwRTMFEwT6BNoEuGSWh0dHA6Ly9jcmwubWljcm9zb2Z0
# LmNvbS9wa2kvY3JsL3Byb2R1Y3RzL01pY1Jvb0NlckF1dDIwMTFfMjAxMV8wM18y
# Mi5jcmwwXgYIKwYBBQUHAQEEUjBQME4GCCsGAQUFBzAChkJodHRwOi8vd3d3Lm1p
# Y3Jvc29mdC5jb20vcGtpL2NlcnRzL01pY1Jvb0NlckF1dDIwMTFfMjAxMV8wM18y
# Mi5jcnQwgZ8GA1UdIASBlzCBlDCBkQYJKwYBBAGCNy4DMIGDMD8GCCsGAQUFBwIB
# FjNodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2RvY3MvcHJpbWFyeWNw
# cy5odG0wQAYIKwYBBQUHAgIwNB4yIB0ATABlAGcAYQBsAF8AcABvAGwAaQBjAHkA
# XwBzAHQAYQB0AGUAbQBlAG4AdAAuIB0wDQYJKoZIhvcNAQELBQADggIBAGfyhqWY
# 4FR5Gi7T2HRnIpsLlhHhY5KZQpZ90nkMkMFlXy4sPvjDctFtg/6+P+gKyju/R6mj
# 82nbY78iNaWXXWWEkH2LRlBV2AySfNIaSxzzPEKLUtCw/WvjPgcuKZvmPRul1LUd
# d5Q54ulkyUQ9eHoj8xN9ppB0g430yyYCRirCihC7pKkFDJvtaPpoLpWgKj8qa1hJ
# Yx8JaW5amJbkg/TAj/NGK978O9C9Ne9uJa7lryft0N3zDq+ZKJeYTQ49C/IIidYf
# wzIY4vDFLc5bnrRJOQrGCsLGra7lstnbFYhRRVg4MnEnGn+x9Cf43iw6IGmYslmJ
# aG5vp7d0w0AFBqYBKig+gj8TTWYLwLNN9eGPfxxvFX1Fp3blQCplo8NdUmKGwx1j
# NpeG39rz+PIWoZon4c2ll9DuXWNB41sHnIc+BncG0QaxdR8UvmFhtfDcxhsEvt9B
# xw4o7t5lL+yX9qFcltgA1qFGvVnzl6UJS0gQmYAf0AApxbGbpT9Fdx41xtKiop96
# eiL6SJUfq/tHI4D1nvi/a7dLl+LrdXga7Oo3mXkYS//WsyNodeav+vyL6wuA6mk7
# r/ww7QRMjt/fdW1jkT3RnVZOT7+AVyKheBEyIXrvQQqxP/uozKRdwaGIm1dxVk5I
# RcBCyZt2WwqASGv9eZ/BvW1taslScxMNelDNMYIZcTCCGW0CAQEwgZUwfjELMAkG
# A1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQx
# HjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEoMCYGA1UEAxMfTWljcm9z
# b2Z0IENvZGUgU2lnbmluZyBQQ0EgMjAxMQITMwAAAlKLM6r4lfM52wAAAAACUjAN
# BglghkgBZQMEAgEFAKCBoDAZBgkqhkiG9w0BCQMxDAYKKwYBBAGCNwIBBDAcBgor
# BgEEAYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAvBgkqhkiG9w0BCQQxIgQgEBqSDxfW
# lNRkvLkUxleUdnu/DkuTi+LMcmLcXzsGWKcwNAYKKwYBBAGCNwIBDDEmMCSgEoAQ
# AFQAZQBzAHQAUwBpAGcAbqEOgAxodHRwOi8vdGVzdCAwDQYJKoZIhvcNAQEBBQAE
# ggEAdqGdPt1i1M+zOD3QjJoqe1YcbkgQNUJm4oBrfhchRVgVKIuGwn8sx+v+tyEs
# jFUg4XsnoYr0rF4PpSZp0bBkA53JwDx5Mmxx0KBf8krta2dNpzSPRyeJ7K/gBquq
# bwjFa+xFm8S66vwgBonZDqoswZ2XKUQWxzhhGUCIOu4IsPTW0c3W63d42O61rw2q
# ziKhspqxH5DzkoEC1+Au8FelBv0YSoUTyeTPBZkt9V9xFBPQmQEQ7gPR04sexu1h
# k2/5c8xNMp8FuLn11i7L4A3ZnbkqGfaxpNzwS8PfR3UUjCpWnkj6U9FPaVziyRRZ
# hKQYfPJNLMyj0XKXTQc517At4qGCFwkwghcFBgorBgEEAYI3AwMBMYIW9TCCFvEG
# CSqGSIb3DQEHAqCCFuIwghbeAgEDMQ8wDQYJYIZIAWUDBAIBBQAwggFVBgsqhkiG
# 9w0BCRABBKCCAUQEggFAMIIBPAIBAQYKKwYBBAGEWQoDATAxMA0GCWCGSAFlAwQC
# AQUABCDMP/2ezfaH9M+9sQtYEENkUZfMZ+EIzD5k2rNrb2h6kAIGYrIKmQeuGBMy
# MDIyMDcwNzIxNDIyMy44OTdaMASAAgH0oIHUpIHRMIHOMQswCQYDVQQGEwJVUzET
# MBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMV
# TWljcm9zb2Z0IENvcnBvcmF0aW9uMSkwJwYDVQQLEyBNaWNyb3NvZnQgT3BlcmF0
# aW9ucyBQdWVydG8gUmljbzEmMCQGA1UECxMdVGhhbGVzIFRTUyBFU046ODk3QS1F
# MzU2LTE3MDExJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2Wg
# ghFcMIIHEDCCBPigAwIBAgITMwAAAasJCe+rY9ToqQABAAABqzANBgkqhkiG9w0B
# AQsFADB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UE
# BxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYD
# VQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDAeFw0yMjAzMDIxODUx
# MjhaFw0yMzA1MTExODUxMjhaMIHOMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2Fz
# aGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENv
# cnBvcmF0aW9uMSkwJwYDVQQLEyBNaWNyb3NvZnQgT3BlcmF0aW9ucyBQdWVydG8g
# UmljbzEmMCQGA1UECxMdVGhhbGVzIFRTUyBFU046ODk3QS1FMzU2LTE3MDExJTAj
# BgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2UwggIiMA0GCSqGSIb3
# DQEBAQUAA4ICDwAwggIKAoICAQDJnUtaOXXoQElLLHC6ssdsJv1oqzVH6pBgcpgy
# LWMxJ6CrZIa3e8DbCbOIPgbjN7gV/NVpztu9JZKwtHtZpg6kLeNtE5m/JcLI0CjO
# phGjUCH1w66J61Td2sNZcfWwH+1WRAN5BxapemADt5I0Oj37QOIlR19yVb/fJ7Y5
# G7asyniTGjVnfHQWgA90QpYjKGo0wxm8mDSk78QYViC8ifFmHSfzQQ6aj80JfqcZ
# umWVUngUACDrm2Y1NL36RAsRwubyNRK66mqRvtKAYYTjfoJZVZJTwFmb9or9JoIw
# k4+2DSl+8i9sdk767x1auRjzWuXzW6ct/beXL4omKjH9UWVWXHHa/trwKZOYm+Wu
# DvEogID0lMGBqDsG2RtaJx4o9AEzy5IClH4Gj8xX3eSWUm0Zdl4N+O/y41kC0fio
# wMgAhW9Om6ls7x7UCUzQ/GNI+WNkgZ0gqldszR0lbbOPmlH5FIbCkvhgF0t4+V1I
# GAO0jDaIO+jZ7LOZdNZxF+7Bw3WMpGIc7kCha0+9F1U2Xl9ubUgX8t1WnM2HdSUi
# P/cDhqmxVOdjcq5bANaopsTobLnbOz8aPozt0Y1f5AvgBDqFWlw3Zop7HNz7ZQQl
# Yf7IGJ6PQFMpm5UkZnntYMJZ5WSdLohyiPathxYGVjNdMjxuYFbdKa15yRYtVsZp
# oPgR/wIDAQABo4IBNjCCATIwHQYDVR0OBBYEFBRbzvKNXjXEgiEGTL6hn3TS/qaq
# MB8GA1UdIwQYMBaAFJ+nFV0AXmJdg/Tl0mWnG1M1GelyMF8GA1UdHwRYMFYwVKBS
# oFCGTmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY3JsL01pY3Jvc29m
# dCUyMFRpbWUtU3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNybDBsBggrBgEFBQcBAQRg
# MF4wXAYIKwYBBQUHMAKGUGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMv
# Y2VydHMvTWljcm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBDQSUyMDIwMTAoMSkuY3J0
# MAwGA1UdEwEB/wQCMAAwEwYDVR0lBAwwCgYIKwYBBQUHAwgwDQYJKoZIhvcNAQEL
# BQADggIBAMpLlIE3NSjLMzILB24YI4BBr/3QhxX9G8vfQuOUke+9P7nQjTXqpU+t
# dBIc9d8RhVOh3Ivky1D1J4b1J0rs+8ZIlka7uUY2WZkqJxFb/J6Wt89UL3lH54Lc
# otCXeqpUspKBFSerQ7kdSsPcVPcr7YWVoULP8psjsIfpsbdAvcG3iyfdnq9r3PZc
# tdqRcWwjQyfpkO7+dtIQL63lqmdNhjiYcNEeHNYj9/YjQcxzqM/g7DtLGI8IWs/R
# 672DBMzg9TCXSz1n1BbGf/4k3d48xMpJNNlo52TcyHthDX5kPym5Rlx3knvCWKop
# kxcZeZHjHy1BC4wIdJoUNbywiWdtAcAuDuexIO8jv2LgZ6PuEa1dAg9oKeATtdCh
# VtkkPzIb0Viux24Eugc7e9K5CHklLaO6UZBzKq54bmyE3F3XZMuhrWbJsDN4b6l7
# krTHlNVuTTdxwPMqYzy3f26Jnxsfeh7sPDq37XEL5O7YXTbuCYQMilF1D+3SjAiX
# 6znaZYNI9bRNGohPqQ00kFZj8xnswi+NrJcjyVV6buMcRNIaQAq9rmtCx7/ywekV
# eQuAjuDLP6X2pf/xdzvoSWXuYsXr8yjZF128TzmtUfkiK1v6x2TOkSAy0ycUxhQz
# NYUA8mnxrvUv2u7ppL4pYARzcWX5NCGBO0UViXBu6ImPhRncdXLNMIIHcTCCBVmg
# AwIBAgITMwAAABXF52ueAptJmQAAAAAAFTANBgkqhkiG9w0BAQsFADCBiDELMAkG
# A1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQx
# HjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEyMDAGA1UEAxMpTWljcm9z
# b2Z0IFJvb3QgQ2VydGlmaWNhdGUgQXV0aG9yaXR5IDIwMTAwHhcNMjEwOTMwMTgy
# MjI1WhcNMzAwOTMwMTgzMjI1WjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2Fz
# aGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENv
# cnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAx
# MDCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBAOThpkzntHIhC3miy9ck
# eb0O1YLT/e6cBwfSqWxOdcjKNVf2AX9sSuDivbk+F2Az/1xPx2b3lVNxWuJ+Slr+
# uDZnhUYjDLWNE893MsAQGOhgfWpSg0S3po5GawcU88V29YZQ3MFEyHFcUTE3oAo4
# bo3t1w/YJlN8OWECesSq/XJprx2rrPY2vjUmZNqYO7oaezOtgFt+jBAcnVL+tuhi
# JdxqD89d9P6OU8/W7IVWTe/dvI2k45GPsjksUZzpcGkNyjYtcI4xyDUoveO0hyTD
# 4MmPfrVUj9z6BVWYbWg7mka97aSueik3rMvrg0XnRm7KMtXAhjBcTyziYrLNueKN
# iOSWrAFKu75xqRdbZ2De+JKRHh09/SDPc31BmkZ1zcRfNN0Sidb9pSB9fvzZnkXf
# tnIv231fgLrbqn427DZM9ituqBJR6L8FA6PRc6ZNN3SUHDSCD/AQ8rdHGO2n6Jl8
# P0zbr17C89XYcz1DTsEzOUyOArxCaC4Q6oRRRuLRvWoYWmEBc8pnol7XKHYC4jMY
# ctenIPDC+hIK12NvDMk2ZItboKaDIV1fMHSRlJTYuVD5C4lh8zYGNRiER9vcG9H9
# stQcxWv2XFJRXRLbJbqvUAV6bMURHXLvjflSxIUXk8A8FdsaN8cIFRg/eKtFtvUe
# h17aj54WcmnGrnu3tz5q4i6tAgMBAAGjggHdMIIB2TASBgkrBgEEAYI3FQEEBQID
# AQABMCMGCSsGAQQBgjcVAgQWBBQqp1L+ZMSavoKRPEY1Kc8Q/y8E7jAdBgNVHQ4E
# FgQUn6cVXQBeYl2D9OXSZacbUzUZ6XIwXAYDVR0gBFUwUzBRBgwrBgEEAYI3TIN9
# AQEwQTA/BggrBgEFBQcCARYzaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9w
# cy9Eb2NzL1JlcG9zaXRvcnkuaHRtMBMGA1UdJQQMMAoGCCsGAQUFBwMIMBkGCSsG
# AQQBgjcUAgQMHgoAUwB1AGIAQwBBMAsGA1UdDwQEAwIBhjAPBgNVHRMBAf8EBTAD
# AQH/MB8GA1UdIwQYMBaAFNX2VsuP6KJcYmjRPZSQW9fOmhjEMFYGA1UdHwRPME0w
# S6BJoEeGRWh0dHA6Ly9jcmwubWljcm9zb2Z0LmNvbS9wa2kvY3JsL3Byb2R1Y3Rz
# L01pY1Jvb0NlckF1dF8yMDEwLTA2LTIzLmNybDBaBggrBgEFBQcBAQROMEwwSgYI
# KwYBBQUHMAKGPmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2kvY2VydHMvTWlj
# Um9vQ2VyQXV0XzIwMTAtMDYtMjMuY3J0MA0GCSqGSIb3DQEBCwUAA4ICAQCdVX38
# Kq3hLB9nATEkW+Geckv8qW/qXBS2Pk5HZHixBpOXPTEztTnXwnE2P9pkbHzQdTlt
# uw8x5MKP+2zRoZQYIu7pZmc6U03dmLq2HnjYNi6cqYJWAAOwBb6J6Gngugnue99q
# b74py27YP0h1AdkY3m2CDPVtI1TkeFN1JFe53Z/zjj3G82jfZfakVqr3lbYoVSfQ
# JL1AoL8ZthISEV09J+BAljis9/kpicO8F7BUhUKz/AyeixmJ5/ALaoHCgRlCGVJ1
# ijbCHcNhcy4sa3tuPywJeBTpkbKpW99Jo3QMvOyRgNI95ko+ZjtPu4b6MhrZlvSP
# 9pEB9s7GdP32THJvEKt1MMU0sHrYUP4KWN1APMdUbZ1jdEgssU5HLcEUBHG/ZPkk
# vnNtyo4JvbMBV0lUZNlz138eW0QBjloZkWsNn6Qo3GcZKCS6OEuabvshVGtqRRFH
# qfG3rsjoiV5PndLQTHa1V1QJsWkBRH58oWFsc/4Ku+xBZj1p/cvBQUl+fpO+y/g7
# 5LcVv7TOPqUxUYS8vwLBgqJ7Fx0ViY1w/ue10CgaiQuPNtq6TPmb/wrpNPgkNWcr
# 4A245oyZ1uEi6vAnQj0llOZ0dFtq0Z4+7X6gMTN9vMvpe784cETRkPHIqzqKOghi
# f9lwY1NNje6CbaUFEMFxBmoQtB1VM1izoXBm8qGCAs8wggI4AgEBMIH8oYHUpIHR
# MIHOMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMH
# UmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSkwJwYDVQQL
# EyBNaWNyb3NvZnQgT3BlcmF0aW9ucyBQdWVydG8gUmljbzEmMCQGA1UECxMdVGhh
# bGVzIFRTUyBFU046ODk3QS1FMzU2LTE3MDExJTAjBgNVBAMTHE1pY3Jvc29mdCBU
# aW1lLVN0YW1wIFNlcnZpY2WiIwoBATAHBgUrDgMCGgMVAFuoev9uFgqO1mc+ghFQ
# Hi87XJg+oIGDMIGApH4wfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0
# b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3Jh
# dGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAwDQYJ
# KoZIhvcNAQEFBQACBQDmcaBHMCIYDzIwMjIwNzA3MjIxMTE5WhgPMjAyMjA3MDgy
# MjExMTlaMHQwOgYKKwYBBAGEWQoEATEsMCowCgIFAOZxoEcCAQAwBwIBAAICDGgw
# BwIBAAICEVswCgIFAOZy8ccCAQAwNgYKKwYBBAGEWQoEAjEoMCYwDAYKKwYBBAGE
# WQoDAqAKMAgCAQACAwehIKEKMAgCAQACAwGGoDANBgkqhkiG9w0BAQUFAAOBgQA2
# vL2ZItPs3raq7JnyIfW7l6ydS/UB48O9WY66DzdI5W4CJipzEwmTU853WEtkPOE3
# MWpGHG/ThsEuf926Gy13bguuloaivZCXup9j6+EsSFGpIAp4k2IPeAvlLgDD0/6D
# 043veNxl1jLK3qbkpV+dVt5eO9tF5fQSC3NNpHyqNDGCBA0wggQJAgEBMIGTMHwx
# CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
# b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1p
# Y3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwAhMzAAABqwkJ76tj1OipAAEAAAGr
# MA0GCWCGSAFlAwQCAQUAoIIBSjAaBgkqhkiG9w0BCQMxDQYLKoZIhvcNAQkQAQQw
# LwYJKoZIhvcNAQkEMSIEID6zzacEy9H/UJU2s+mNehz9rNH9LMKmRPhd30J0pQ04
# MIH6BgsqhkiG9w0BCRACLzGB6jCB5zCB5DCBvQQgDhyv+rCFYBFUlQ9wK75OjskC
# r0cRRysq2lM2zdfwClcwgZgwgYCkfjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMK
# V2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0
# IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0Eg
# MjAxMAITMwAAAasJCe+rY9ToqQABAAABqzAiBCCnELJ2vYTT8gFyy6t9WkIF01Lx
# I4DL2AnB3AwFWut5CzANBgkqhkiG9w0BAQsFAASCAgDDt0Ji+ngjagBYSzvpeq/3
# RFfrQZgF9XagdtD2m0sJhDNXS9pwd1uICdeuXmtbLkawjfb3+YsrM7NJ2NbxBuIw
# Q1dQXMPjC70wQ/6sfD2q5O6OZIbqeNSVAPYqoMX6bfvZwitpxGotLUQXUBWXzyjF
# Ac+cdM21EXO7vsn4Up6Td9M7hvlh837V7TkE+5MsE4AD6A11T/XjHd0Yoe0ClTpX
# iF+fAwIcppG/+y+iOwQ/n+st8DQeKy+cB9QJaIQ4jXqb7kbYl4LnA0H5GmpL1PXY
# 06zIp++VYtUcu4WeNbz50fD/aRH1UGnZmS442rSMP+yFMfvbux7LeyUQK8dggONC
# spsjoVDx9E46ZEO/T5Qk5AuTMcFwhAqHxyo2Wt9Z5+iAnzl5rqwoeN2OZ32Odn6f
# cb9yzei2YGwU5F4czpQLJQZT/ittiAtt8yI7irgX+L15q57vzTFGB+cbTmbo/B81
# otxYYpZnatnFxn6+PQ8mESzBOzEKCJh8KKB9H6ZLq1sNmZA8MzPnHEKh8NMidsKA
# 3sNhDvQOaDUTscNw+PDZeJHY3Fv4erloJeVqDpN30iabghZA/HkHPKPmUFwc82jJ
# rnUMCfYQSZDLq26jdnhOqLznwBJ/ykEZqCZl5PAP+vZnwHPWOLzwqb25RQrxW7Ho
# f4yPGVDKWChjOMiLDBoOYw==
# SIG # End signature block
