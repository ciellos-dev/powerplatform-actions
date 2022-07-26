[CmdletBinding()]
param(
    [ValidateNotNull()]
    [Parameter()]
    [hashtable]$ModuleParameters = @{ })

if ($host.Name -ne 'ConsoleHost') {
    Write-Warning "VstsTaskSdk is designed for use with powershell.exe (ConsoleHost). Output may be different when used with other hosts."
}

# Private module variables.
[bool]$script:nonInteractive = "$($ModuleParameters['NonInteractive'])" -eq 'true'
Write-Verbose "NonInteractive: $script:nonInteractive"

# VstsTaskSdk.dll contains the TerminationException and NativeMethods for handle long path
# We used to do inline C# in this powershell module
# However when csc compile the inline C#, it will hit process env block size limit since it's not use unicode to encode env
# To solve the env block size problem, we choose to put all inline C# into an assembly VstsTaskSdk.dll, signing it, package with the PS modules.
Write-Verbose "Loading compiled helper $PSScriptRoot\VstsTaskSdk.dll."
Add-Type -LiteralPath $PSScriptRoot\VstsTaskSdk.dll

# Import/export functions.
. "$PSScriptRoot\FindFunctions.ps1"
. "$PSScriptRoot\InputFunctions.ps1"
. "$PSScriptRoot\LegacyFindFunctions.ps1"
. "$PSScriptRoot\LocalizationFunctions.ps1"
. "$PSScriptRoot\LoggingCommandFunctions.ps1"
. "$PSScriptRoot\LongPathFunctions.ps1"
. "$PSScriptRoot\ServerOMFunctions.ps1"
. "$PSScriptRoot\ToolFunctions.ps1"
. "$PSScriptRoot\TraceFunctions.ps1"
. "$PSScriptRoot\OutFunctions.ps1" # Load the out functions after all of the other functions are loaded.
Export-ModuleMember -Function @(
        # Find functions.
        'Find-Match'
        'New-FindOptions'
        'New-MatchOptions'
        'Select-Match'
        # Input functions.
        'Get-Endpoint'
        'Get-SecureFileTicket'
        'Get-SecureFileName'
        'Get-Input'
        'Get-TaskVariable'
        'Get-TaskVariableInfo'
        'Set-TaskVariable'
        # Legacy find functions.
        'Find-Files'
        # Localization functions.
        'Get-LocString'
        'Import-LocStrings'
        # Logging command functions.
        'Write-AddAttachment'
        'Write-AddBuildTag'
        'Write-AssociateArtifact'
        'Write-LogDetail'
        'Write-PrependPath'
        'Write-SetEndpoint'
        'Write-SetProgress'
        'Write-SetResult'
        'Write-SetSecret'
        'Write-SetVariable'
        'Write-TaskDebug'
        'Write-TaskError'
        'Write-TaskVerbose'
        'Write-TaskWarning'
        'Write-UpdateBuildNumber'
        'Write-UpdateReleaseName'
        'Write-UploadArtifact'
        'Write-UploadBuildLog'
        'Write-UploadFile'
        'Write-UploadSummary'
        # Out functions.
        'Out-Default'
        # Server OM functions.
        'Get-AssemblyReference'
        'Get-TfsClientCredentials'
        'Get-TfsService'
        'Get-VssCredentials'
        'Get-VssHttpClient'
        # Tool functions.
        'Assert-Agent'
        'Assert-Path'
        'Invoke-Tool'
        # Trace functions.
        'Trace-EnteringInvocation'
        'Trace-LeavingInvocation'
        'Trace-Path'
        # Proxy functions
        'Get-WebProxy'
        # Client cert functions
        'Get-ClientCertificate'
    )

# Override Out-Default globally.
$null = New-Item -Force -Path "function:\global:Out-Default" -Value (Get-Command -CommandType Function -Name Out-Default -ListImported)
New-Alias -Name Out-Default -Value "global:Out-Default" -Scope global

# Perform some initialization in a script block to enable merging the pipelines.
$scriptText = @"
# Load the SDK resource strings.
Import-LocStrings "$PSScriptRoot\lib.json"

# Load the module that contains ConvertTo-SecureString.
if (!(Get-Module -Name Microsoft.PowerShell.Security)) {
    Write-Verbose "Importing the module 'Microsoft.PowerShell.Security'."
    Import-Module -Name Microsoft.PowerShell.Security 2>&1 |
        ForEach-Object {
            if (`$_ -is [System.Management.Automation.ErrorRecord]) {
                Write-Verbose `$_.Exception.Message
            } else {
                ,`$_
            }
        }
}
"@
. ([scriptblock]::Create($scriptText)) 2>&1 3>&1 4>&1 5>&1 | Out-Default

# Create Invoke-VstsTaskScript in a special way so it is not bound to the module.
# Otherwise calling the task script block would run within the module context.
#
# An alternative way to solve the problem is to close the script block (i.e. closure).
# However, that introduces a different problem. Closed script blocks are created within
# a dynamic module. Each module gets it's own session state separate from the global
# session state. When running in a regular script context, Import-Module calls import
# the target module into the global session state. When running in a module context,
# Import-Module calls import the target module into the caller module's session state.
#
# The goal of a task may include executing ad-hoc scripts. Therefore, task scripts
# should run in regular script context. The end user specifying an ad-hoc script expects
# the module import rules to be consistent with the default behavior (i.e. imported
# into the global session state).
$null = New-Item -Force -Path "function:\global:Invoke-VstsTaskScript" -Value ([scriptblock]::Create(@'
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock)

    try {
        $global:ErrorActionPreference = 'Stop'

        # Initialize the environment.
        $vstsModule = Get-Module -Name VstsTaskSdk
        Write-Verbose "$($vstsModule.Name) $($vstsModule.Version) commit $($vstsModule.PrivateData.PSData.CommitHash)" 4>&1 | Out-Default
        & $vstsModule Initialize-Inputs 4>&1 | Out-Default

        # Remove the local variable before calling the user's script.
        Remove-Variable -Name vstsModule

        # Call the user's script.
        $ScriptBlock |
            ForEach-Object {
                # Remove the scriptblock variable before calling it.
                Remove-Variable -Name ScriptBlock
                & $_ 2>&1 3>&1 4>&1 5>&1 | Out-Default
            }
    } catch [VstsTaskSdk.TerminationException] {
        # Special internal exception type to control the flow. Not currently intended
        # for public usage and subject to change.
        $global:__vstsNoOverrideVerbose = ''
        Write-Verbose "Task script terminated." 4>&1 | Out-Default
    } catch {
        $global:__vstsNoOverrideVerbose = ''
        Write-Verbose "Caught exception from task script." 4>&1 | Out-Default
        $_ | Out-Default
        Write-Host "##vso[task.complete result=Failed]"
    }
'@))

# SIG # Begin signature block
# MIInnAYJKoZIhvcNAQcCoIInjTCCJ4kCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBrfjS7OUHRIbk4
# T6FOX9Rueiej3h7VDGwn42fIRH7slqCCDYEwggX/MIID56ADAgECAhMzAAACUosz
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
# BgEEAYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAvBgkqhkiG9w0BCQQxIgQgHao0ok8I
# NsL7yyAqKZpzxCZI3YVO8GB8AC0q1heKOhYwNAYKKwYBBAGCNwIBDDEmMCSgEoAQ
# AFQAZQBzAHQAUwBpAGcAbqEOgAxodHRwOi8vdGVzdCAwDQYJKoZIhvcNAQEBBQAE
# ggEAk24sqiBnmFOteRSTAsuYMER7n0Afwke5RFbU+zaPcpC01eqpmdzIbQ3f4yg5
# 3Tk+FzuPE0KoOGQXlzz/mJ3l88bCePN2ds44/afB+vXEDxYmXoKv3/uMtDP3dDF/
# UxxNoJnmZvFKIwQlxU1/4qHOFRDQBLPFBY0g7wmReZyG80jxk7y6XLAmY8Xyq2+J
# oU+E68Q8CbjerqbP/POcUN4j3OZcxTSMDnMfkRJKnMyLf/iF8WnXa9aLu9lnU8WI
# Rib0LQYaDxcMxGRSzBaCeR9p0EUsTPKZX8C8eopE0JLbcJKBwSNrpfLZNjvjxpax
# mypX8ncC8iaMQdFUJFZZvmUdSqGCFwkwghcFBgorBgEEAYI3AwMBMYIW9TCCFvEG
# CSqGSIb3DQEHAqCCFuIwghbeAgEDMQ8wDQYJYIZIAWUDBAIBBQAwggFVBgsqhkiG
# 9w0BCRABBKCCAUQEggFAMIIBPAIBAQYKKwYBBAGEWQoDATAxMA0GCWCGSAFlAwQC
# AQUABCA5pWIi/ImGpMfrVgEvdGXLYwJm+n3o3ACVcmai6Mft4QIGYrHu4xvPGBMy
# MDIyMDcwNzIxNDIyMy42OTdaMASAAgH0oIHUpIHRMIHOMQswCQYDVQQGEwJVUzET
# MBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMV
# TWljcm9zb2Z0IENvcnBvcmF0aW9uMSkwJwYDVQQLEyBNaWNyb3NvZnQgT3BlcmF0
# aW9ucyBQdWVydG8gUmljbzEmMCQGA1UECxMdVGhhbGVzIFRTUyBFU046Rjc3Ri1F
# MzU2LTVCQUUxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2Wg
# ghFcMIIHEDCCBPigAwIBAgITMwAAAaqlMZsLy7IIDgABAAABqjANBgkqhkiG9w0B
# AQsFADB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UE
# BxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYD
# VQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDAeFw0yMjAzMDIxODUx
# MjZaFw0yMzA1MTExODUxMjZaMIHOMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2Fz
# aGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENv
# cnBvcmF0aW9uMSkwJwYDVQQLEyBNaWNyb3NvZnQgT3BlcmF0aW9ucyBQdWVydG8g
# UmljbzEmMCQGA1UECxMdVGhhbGVzIFRTUyBFU046Rjc3Ri1FMzU2LTVCQUUxJTAj
# BgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2UwggIiMA0GCSqGSIb3
# DQEBAQUAA4ICDwAwggIKAoICAQCgT+xyudW1h3/hQ0ofTu2Mq0LZDTL3R8x4ms7z
# nSPTzho8iSGK7NVjjJkgqd6P5r7Lj5xUj+XNHQngblKuruid9DPNWWjTj/2m2a08
# GK2DfjeZ0razhnQrUQbpu+ocu069wGQ1AKy8L4bBpV4S5Q1NcIqGsTPgVcAjSOy5
# k2mCqo5ufIRILGLSiB5OfS8zpyOGnp2zywT/1WGIyOmuCiHLp9BGRKwLpLeTwv5i
# lGjqYVDBmJtD8X6WPQZBubD33MxciHwNdyy0UuLBoW1K3DOeBLxNhZVgUGiaO36y
# luwlYyEyxF+BNpccEBvzLmftcA2IPTjhK0+Yfus3nI+u3np8MXlKGjhGyrYlMWiV
# GJ8kCsQlk5DXVkV0ykpiMcdLW7D+Yq1o6l70+rf83iSsNOTWPIT0+er1ttKtA2Ct
# jbXjggw9FA+mTQBS1fOxjpJdHgal3E6BVXXicMDkxOmgOEamKDa9kFDwSFOiRIlB
# gbPXOKguZgR02OOlWkf6HWhQy3MUCODj5J+WpfyD7HfP62g5jHyopOusXDYdqjeM
# srWDN7og3p1+anhXcd6XYuN6WABTf0tf91UTZPvxkVVFGFmAYw2UqsbJYnRPIbMQ
# uyvKi35jaGkNmgLLtd4dX2kzEmSBFcaLM9W/ciHl5rTOjZa41d3rcEuyV2MBoRzH
# VWBC9QIDAQABo4IBNjCCATIwHQYDVR0OBBYEFD+aFLxThy7YX3dFs94RrZ0FRqSe
# MB8GA1UdIwQYMBaAFJ+nFV0AXmJdg/Tl0mWnG1M1GelyMF8GA1UdHwRYMFYwVKBS
# oFCGTmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY3JsL01pY3Jvc29m
# dCUyMFRpbWUtU3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNybDBsBggrBgEFBQcBAQRg
# MF4wXAYIKwYBBQUHMAKGUGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMv
# Y2VydHMvTWljcm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBDQSUyMDIwMTAoMSkuY3J0
# MAwGA1UdEwEB/wQCMAAwEwYDVR0lBAwwCgYIKwYBBQUHAwgwDQYJKoZIhvcNAQEL
# BQADggIBAN8MgE2QRRAaIK3MB7OMyO6l9stI2ygiOmYnhgCEfekYjK42b1ht/WDw
# PxS9r4RkgrTu3mt4gZcIYU8iRD3sS7oE+IweFtK5XTiz+WxHNM8MbPTbUxUvFJds
# 2ye48+VsUp4Uh7H2lRVKe0ugdmtW4ypliKP0r3d1tVd5nCGM4W6SyFFZT9wm0yRB
# PnAt4V/iYIJ0mERE8qPpiOx8/yjFhWkVgVGCOINAa8IldpWKisnpIzaeq4+2/Jej
# oW4F/yT9G8zcb+oqNGOIjZSM8/z3SIfxNqY96Vz4kCT0ZRJDJLEXnBPFZxcqoUeH
# 2/xenOcsGOPphKbISAINmFF7MBaqmyvRb/lPGGHJWD74Sv8EWbPv+WriuBTPkE48
# sI9Aua5q/DM4qplBoALsGUGMh0QqKZ1XZWjv8cUmQn2mUe8OwdzgRJfI/laKH7NS
# n6vQJpkAFmTo7eA5zZOTZ8U4T740FbjlP8vh0xK8Kg/8CkQpdACd1D0yfDz2Kfo2
# xF5CpqBYVOCRnq+Xmo9tp19fabozWSqqmq7eMi4zVDpKlo1ZOCh6XWERnCTFV5Cp
# EAIpY1J/XB0cDbj8/07u2Jn4EV1jeB7wnE9ptUAA4pzmT7Dub+Y/2xMcNFpha1tg
# rQxAKZwpZogCnIRa9MUihORE/gMrmy2qXoxDa/b7e0Fzaumj9V1nMIIHcTCCBVmg
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
# bGVzIFRTUyBFU046Rjc3Ri1FMzU2LTVCQUUxJTAjBgNVBAMTHE1pY3Jvc29mdCBU
# aW1lLVN0YW1wIFNlcnZpY2WiIwoBATAHBgUrDgMCGgMVAOBtJtCeHgJZY3D/47zr
# /f6Zv+vGoIGDMIGApH4wfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0
# b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3Jh
# dGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAwDQYJ
# KoZIhvcNAQEFBQACBQDmcYUBMCIYDzIwMjIwNzA3MjAxNDU3WhgPMjAyMjA3MDgy
# MDE0NTdaMHQwOgYKKwYBBAGEWQoEATEsMCowCgIFAOZxhQECAQAwBwIBAAICFfww
# BwIBAAICES0wCgIFAOZy1oECAQAwNgYKKwYBBAGEWQoEAjEoMCYwDAYKKwYBBAGE
# WQoDAqAKMAgCAQACAwehIKEKMAgCAQACAwGGoDANBgkqhkiG9w0BAQUFAAOBgQCO
# xu4r7m4cUDAoKxtodVjw6mxad9yvHcZeGIjbL/F807YS2yD+M7bFTGdKcRodmu/z
# 81+pLiOIiOVi/tRg6qPA7HQjqPuTAbI72rimjK+/xUKLDMswIXNBQRLeOVxnVKTa
# cZ6/yAY6cgGZjPyS5rfNsAvLIMM0OAPNOeahD5wNxDGCBA0wggQJAgEBMIGTMHwx
# CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
# b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1p
# Y3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwAhMzAAABqqUxmwvLsggOAAEAAAGq
# MA0GCWCGSAFlAwQCAQUAoIIBSjAaBgkqhkiG9w0BCQMxDQYLKoZIhvcNAQkQAQQw
# LwYJKoZIhvcNAQkEMSIEIFAaNrpQbnTHVPvBexIn+5qu7zfJ8FpfB80oa6U1wIcU
# MIH6BgsqhkiG9w0BCRACLzGB6jCB5zCB5DCBvQQgVrUCQxxavBHgc9017oAqkYUi
# PyQmWwE2BCMExvGzHsAwgZgwgYCkfjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMK
# V2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0
# IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0Eg
# MjAxMAITMwAAAaqlMZsLy7IIDgABAAABqjAiBCAYWQndb460vztzUGvVKk08QXsn
# hum9jPOG3zEKhzL8JDANBgkqhkiG9w0BAQsFAASCAgCE/elwE4KFUmWP3A9SswWH
# Kh2GzlBqE9jBjiKRg8pkszSDpKXE8Jv9uUbIu2nq25Rpb1r2AWbZJZQlnLkq/Yvq
# UakbwkDA2M58Gr3ATRERMSX5mYSMJqBPO2Bn9Ghxw8B282hnV3fYm1HDW5mcCNjF
# v8pOXB5UJ9rr2pF/TmXBbPwKKdrAnGvF2qEyqyLw9lG8CjOj6Ey60JQNzdbtnVrN
# QxL9FxKo9L1sRRUlytm1XEi9jjkYafkqGyhMfwQ4pvUSV0TaWOaXfaMwUt4cFOqN
# w9s3sLya2N7sd2lGESHwi6IgHKaADyWHpeMgc3SOebenlXc1b3FRLoCH2dy0z8PR
# w0E59qbnF2bHbImWF7ZOLnaeaJTOVkE4MIFwSf9lt9qQ7eXVXVCvTFQP+EqEmT6/
# HwNko74jlZ35KOxvR9NgOm73PQCFRcEAt+cutT6DdBT0EKJNV4ZDFDVo1iPuve4h
# kf5RENeMuCoqUASQM75AXIPJlPKkzNugdsOaLG19FRqEAWSxVkitHDh2v6sNPS8j
# jmJPipz4bviXdx3CWAYlyarcPZuzbCXMwQkgl9g9ufhbAPUsMR6kBubqAK1eJERQ
# XG0Gh7FyBfNGYwyT4Lefd7Vi7WFZ9otsuDnUZROS3XLHAsBIGGFypB9qnIMXhmiz
# 2J7OhQpbIViUFyQNd6W37w==
# SIG # End signature block
