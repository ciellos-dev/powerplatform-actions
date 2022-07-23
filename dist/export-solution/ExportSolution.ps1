# Copyright (c) Microsoft Corporation. All rights reserved.

[CmdletBinding()]
param(
    [parameter (Mandatory = $false)][string]$Username,
    [parameter (Mandatory = $false)][string]$PasswordSecret,
    [parameter (Mandatory = $false)][string]$AppId,
    [parameter (Mandatory = $false)][string]$ClientSecret,
    [parameter (Mandatory = $true)][string]$SolutionName,
    [parameter (Mandatory = $true)][string]$SolutionOutputFile,
    [parameter (Mandatory = $true)][bool]$Managed,
    [parameter (Mandatory = $false)][bool]$ExportAutoNumberingSettings = $false,
    [parameter (Mandatory = $false)][bool]$ExportCalendarSettings = $false,
    [parameter (Mandatory = $false)][bool]$ExportCustomizationSettings = $false,
    [parameter (Mandatory = $false)][bool]$ExportEmailTrackingSettings = $false,
    [parameter (Mandatory = $false)][bool]$ExportGeneralSettings = $false,
    [parameter (Mandatory = $false)][bool]$ExportIsvConfig = $false,
    [parameter (Mandatory = $false)][bool]$ExportMarketingSettings = $false,
    [parameter (Mandatory = $false)][bool]$ExportOutlookSynchronizationSettings = $false,
    [parameter (Mandatory = $false)][bool]$ExportRelationshipRoles = $false,
    [parameter (Mandatory = $false)][bool]$ExportSales = $false,
    [parameter (Mandatory = $true)][bool]$AsyncOperation = $true,
    [parameter (Mandatory = $true)][Timespan]$MaxAsyncWaitTime = (New-TimeSpan -Hours 1)

)

function Invoke-ExportSolution {
    [CmdletBinding()]
    param (
        [parameter (Mandatory = $true)][Hashtable]$authInfo,
        [parameter (Mandatory = $true)][string]$SolutionName,
        [parameter (Mandatory = $true)][string]$SolutionOutputFile,
        [parameter (Mandatory = $true)][bool]$Managed,
        [parameter (Mandatory = $false)][bool]$ExportAutoNumberingSettings = $false,
        [parameter (Mandatory = $false)][bool]$ExportCalendarSettings = $false,
        [parameter (Mandatory = $false)][bool]$ExportCustomizationSettings = $false,
        [parameter (Mandatory = $false)][bool]$ExportEmailTrackingSettings = $false,
        [parameter (Mandatory = $false)][bool]$ExportGeneralSettings = $false,
        [parameter (Mandatory = $false)][bool]$ExportIsvConfig = $false,
        [parameter (Mandatory = $false)][bool]$ExportMarketingSettings = $false,
        [parameter (Mandatory = $false)][bool]$ExportOutlookSynchronizationSettings = $false,
        [parameter (Mandatory = $false)][bool]$ExportRelationshipRoles = $false,
        [parameter (Mandatory = $false)][bool]$ExportSales = $false,
        [parameter (Mandatory = $true)][bool]$AsyncOperation = $true,
        [parameter (Mandatory = $true)][Timespan]$MaxAsyncWaitTime = (New-TimeSpan -Hours 1)
    )

    begin {
         #Setup parameter hash table
        $Parameters = . Get-ParameterValue

        $currentExportAsycMessage = "ExportSolutionAsync is not enabled for this org"
        $currentFileStorageMessage = "FileStorageService is not enabled for this org"
        $futureExportAsycMessage = "Asynchronous solution export requires FCB.ExportSolutionAsync, which is not enabled on this instance. Please retry with *Synchronous* solution export."
        $futureFileStorageMessage = "Asynchronous solution export requires FileStorage, which is not enabled on this instance. Please retry with *Synchronous* solution export."

    }

    process {

        Write-AuthLog -AuthInfo $authInfo
        try {

            $output = Export-Solution @Parameters -InformationAction Continue

        } catch [System.ServiceModel.FaultException] {

            # the following logic and corresponding variables defined in the begin{} should be removed and just write-error $_.Exception.Message once the Solution framework team
            # confirm the below PR changes deployed in all public cloud regions
            # https://dynamicscrm.visualstudio.com/OneCRM/_git/CDS/pullrequest/506153.
            if ($_.Exception.Message -eq $currentExportAsycMessage -or
                $_.Exception.Message -eq $futureExportAsycMessage -or
                $_.Exception.Message -eq $currentFileStorageMessage -or
                $_.Exception.Message -eq $futureFileStorageMessage) {

                    Write-Error "Asynchronous solution export requires FCB.ExportSolutionAsync and FileStorage, which are not enabled on this instance. Please retry with *Synchronous* solution export."
            }
            else
            {
                Write-Error $_.Exception
            }
            return
        }
    }

    end {
        return $output
    }
}

try {
    # Load shared functions and other dependencies
    ("..\ps_modules\VstsTaskSdk", "..\ps_modules\SharedFunctions.psm1", "..\ps_modules\Get-ParameterValue.ps1") `
        | %{ Join-Path -Path $PSScriptRoot $_ } | Import-Module
    $redirector = Get-BindingRedirector
    Import-PowerPlatformToolsPowerShellModule -ModuleName "Microsoft.Xrm.WebApi.PowerShell"

    # Get input parameters and credentials
    $authInfo = '' 

    $PSCredential = New-Object System.Management.Automation.PSCredential ($Username, (ConvertTo-SecureString $PasswordSecret -AsPlainText -Force))
    #if ($selectedAuthName -eq "PowerPlatformEnvironment") {
    if(-not ($ClientSecret -eq "")){
         $authInfo = @{
            EnvironmentUrl  = $EnvironmentUrl
            Credential      = $PSCredential
            TenantId        = $null
            AuthType        = 'OAuth'
        }
    }
    #} elseif ($selectedAuthName -eq "PowerPlatformSPN") {
    else{
        $authInfo = @{
            EnvironmentUrl  = $EnvironmentUrl
            Credential      = $PSCredential
            TenantId        = $TenantId
            AuthType        = 'ClientSecret'
        }
    }

    Write-Verbose "ExportSolution from org: $($authInfo.EnvironmentUrl)..."
    Invoke-ExportSolution $authInfo `
        -SolutionName $SolutionName -SolutionOutputFile $SolutionOutputFile -Managed $Managed `
        -ExportAutoNumberingSettings $ExportAutoNumberingSettings -ExportCalendarSettings $ExportCalendarSettings `
        -ExportCustomizationSettings $ExportCustomizationSettings -ExportEmailTrackingSettings $ExportEmailTrackingSettings `
        -ExportGeneralSettings $ExportGeneralSettings -ExportIsvConfig $ExportIsvConfig `
        -ExportMarketingSettings $ExportMarketingSettings -ExportOutlookSynchronizationSettings $ExportOutlookSynchronizationSettings `
        -ExportRelationshipRoles $ExportRelationshipRoles -ExportSales $ExportSales `
        -AsyncOperation $AsyncOperation  -MaxAsyncWaitTime $MaxAsyncWaitTime

} finally {
    if ($null -ne $redirector) {
        $redirector.Dispose()
    }
}

# SIG # Begin signature block
# MIInnwYJKoZIhvcNAQcCoIInkDCCJ4wCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBANhl9IMxdBVgb
# DG0+3c4CpbR/Zxu++PQJ96ePitKbp6CCDYEwggX/MIID56ADAgECAhMzAAACUosz
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
# RcBCyZt2WwqASGv9eZ/BvW1taslScxMNelDNMYIZdDCCGXACAQEwgZUwfjELMAkG
# A1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQx
# HjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEoMCYGA1UEAxMfTWljcm9z
# b2Z0IENvZGUgU2lnbmluZyBQQ0EgMjAxMQITMwAAAlKLM6r4lfM52wAAAAACUjAN
# BglghkgBZQMEAgEFAKCBoDAZBgkqhkiG9w0BCQMxDAYKKwYBBAGCNwIBBDAcBgor
# BgEEAYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAvBgkqhkiG9w0BCQQxIgQg4WLSZT+F
# 0kt7+VuS7CrWz6FTJdGYTocpAZdqJaV10HUwNAYKKwYBBAGCNwIBDDEmMCSgEoAQ
# AFQAZQBzAHQAUwBpAGcAbqEOgAxodHRwOi8vdGVzdCAwDQYJKoZIhvcNAQEBBQAE
# ggEAXuuqiad9b3XnRQ624KhtLDq7fozm3idqcWKkCqBnDkECKt5cH19FPlkBEaYU
# w966ctxe3qkdD6rIlyxqLgGLQ+JSUcfoUJMUGK0PcTx8mXH4evTdo3XHVn1RBco1
# Mmzd/xg1DmFJ/jH1+WDu0rq99IjAyfJKpbANzIc8lFF8JoEX7TCBHmhmpKLXSTqt
# 9FEe84yGrF+0CKwNLGJVhtPp3OkswnmwmU9HDkRChUX0Mox5w3eCdzJ3ZHjpPxm7
# pNBeXkNUsiInxXWhX6wwiM1V0R9mX6pgzXalnAPOeoCr01Yv9tbJ3iMMQNCRTDA3
# BRF3euEEkZct87cfHa8mzNxoqKGCFwwwghcIBgorBgEEAYI3AwMBMYIW+DCCFvQG
# CSqGSIb3DQEHAqCCFuUwghbhAgEDMQ8wDQYJYIZIAWUDBAIBBQAwggFVBgsqhkiG
# 9w0BCRABBKCCAUQEggFAMIIBPAIBAQYKKwYBBAGEWQoDATAxMA0GCWCGSAFlAwQC
# AQUABCCukpP26ZViU3blth32lmPZJLSpiezY1S7VjYMqPvu2CgIGYrH6FztvGBMy
# MDIyMDcwNzIxNDIyNS4wNjlaMASAAgH0oIHUpIHRMIHOMQswCQYDVQQGEwJVUzET
# MBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMV
# TWljcm9zb2Z0IENvcnBvcmF0aW9uMSkwJwYDVQQLEyBNaWNyb3NvZnQgT3BlcmF0
# aW9ucyBQdWVydG8gUmljbzEmMCQGA1UECxMdVGhhbGVzIFRTUyBFU046NEQyRi1F
# M0RELUJFRUYxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2Wg
# ghFfMIIHEDCCBPigAwIBAgITMwAAAbCh44My6I07wAABAAABsDANBgkqhkiG9w0B
# AQsFADB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UE
# BxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYD
# VQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDAeFw0yMjAzMDIxODUx
# NDJaFw0yMzA1MTExODUxNDJaMIHOMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2Fz
# aGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENv
# cnBvcmF0aW9uMSkwJwYDVQQLEyBNaWNyb3NvZnQgT3BlcmF0aW9ucyBQdWVydG8g
# UmljbzEmMCQGA1UECxMdVGhhbGVzIFRTUyBFU046NEQyRi1FM0RELUJFRUYxJTAj
# BgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2UwggIiMA0GCSqGSIb3
# DQEBAQUAA4ICDwAwggIKAoICAQCcxm07DNfSgp0HOUQu1aIJcklzCi7rf8llj0Fg
# +lQJSYAXsVSsdp9c4F96P8QNmYGfzRRnIDQ0Qie5iYjnlu8Xh56DVz5YOxI2FrpX
# 5N6DgI+muzteRr3JKWLLy3MfqPEnvAq3yG+NBCfFtEMeEyF39Mg8ACeP6jveHSf4
# Rmm3iWIOBqdBtLkJocBaLwFkx5Q9XIvrKd+gMU/cCIR6sP+9LczL65wxe45kI2lV
# D54zoDzshVmYla+3uq5EpeGp09bS79t0loV6jLNeMKJb+GXkHFj/OK1dha69Sm8J
# CGtL5R45b+MRvWup5U0X6NAmFEA362TjFwiOSnADdgWen1W9ParQnbFnTTcQdMuJ
# cDI57jZsfORTX8z3DGY5sABfWkVFDCx7+tuiOu7dfnWaFT6Sqn0jZhrVbfQxE1pJ
# g4qZxoOPgXU6Zb4BlavRdymTwxR2m8Wy6Uln11vdDGVzrhR/MgjMwyTVM3sgKsrR
# Rci2Yq94+E9Rse5UXgjlD8Nablc21irKVezKHWY7TfyFFnVSHZNxz6eEDdcMHVb3
# VzrGHYRvJIIxsgGSA+aK+wv++YcikG+RdGfhHtOLmPSvrA2d5d8/E0GVgH2Lq22Q
# jFlp5iVbLuVeD0eTzvlOg+7QLTLzFCzWIm0/frMVWSv1kHq9iSfat2e5YxbOJYKZ
# n3OgFQIDAQABo4IBNjCCATIwHQYDVR0OBBYEFDrfASQ3ASZuHcugEmR61yBH1jY/
# MB8GA1UdIwQYMBaAFJ+nFV0AXmJdg/Tl0mWnG1M1GelyMF8GA1UdHwRYMFYwVKBS
# oFCGTmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY3JsL01pY3Jvc29m
# dCUyMFRpbWUtU3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNybDBsBggrBgEFBQcBAQRg
# MF4wXAYIKwYBBQUHMAKGUGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMv
# Y2VydHMvTWljcm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBDQSUyMDIwMTAoMSkuY3J0
# MAwGA1UdEwEB/wQCMAAwEwYDVR0lBAwwCgYIKwYBBQUHAwgwDQYJKoZIhvcNAQEL
# BQADggIBAN1z4oebDbVHwMi55V6ujGUqQodExfrhvp4SCeOP/3DHEBhFYmdjdutz
# cL60IwhTp4v/qMX++o3JlIXCli15PYYXe73xQYWWc3BeWjbNO1JYoLNuKb3mrBbo
# ZieMvNjmJtRtTkWLBZ3WXbxf/za2BsWl6lDZUR0JbJFf6ZnHKjtzousCx3Dwdf1k
# UyybWGyIosBP7kxRBRC+OcFg/9ZkwjxJBV94ZYlxMqcV83WdZOl6hk8rBgLS11Ae
# yAugh9umMoCkLlxvEI3CQQFBv/Rd8jWTnWxb5+xYp2cjXCFS8ZXe4dGxC30M4SI3
# pY/ubASoS3GhVNL2425n9FhDYBZp8iTYjKy+/9hWDi7IIkA2yceg6ctRH77kRrHS
# +X/o1VXbOaDGiq4cYFe6BKG6wOmeep51mDeO7MMKLrnB39MptQ0Fh8tgxzhUUTe8
# r/vs3rNBkgjo0UWDyu669UHPjt57HetODoJuZ0fUKoTjnNjkE677UoFwUrbubxel
# vAz3LJ7Od3EOIHXEdWPTYOSGBMMQmc82LKvaGpcZR/mR/wOie2THkjSjZK1z8eqa
# RV1MR7gt5OJs1cmTRlj/2YHFDotqldN5uiJsrb4tZHxnumHQod9jzoFnjR/ZXyrf
# ndTPquCISS5l9BNmWSAmBG/UNK6JnjF/BmfnG4bjbBYpiYGv3447MIIHcTCCBVmg
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
# f9lwY1NNje6CbaUFEMFxBmoQtB1VM1izoXBm8qGCAtIwggI7AgEBMIH8oYHUpIHR
# MIHOMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMH
# UmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSkwJwYDVQQL
# EyBNaWNyb3NvZnQgT3BlcmF0aW9ucyBQdWVydG8gUmljbzEmMCQGA1UECxMdVGhh
# bGVzIFRTUyBFU046NEQyRi1FM0RELUJFRUYxJTAjBgNVBAMTHE1pY3Jvc29mdCBU
# aW1lLVN0YW1wIFNlcnZpY2WiIwoBATAHBgUrDgMCGgMVAAKeL5Dd3w+RTQVWGZJW
# XkvyRTwYoIGDMIGApH4wfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0
# b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3Jh
# dGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAwDQYJ
# KoZIhvcNAQEFBQACBQDmcZALMCIYDzIwMjIwNzA3MjEwMjAzWhgPMjAyMjA3MDgy
# MTAyMDNaMHcwPQYKKwYBBAGEWQoEATEvMC0wCgIFAOZxkAsCAQAwCgIBAAICEqwC
# Af8wBwIBAAICET8wCgIFAOZy4YsCAQAwNgYKKwYBBAGEWQoEAjEoMCYwDAYKKwYB
# BAGEWQoDAqAKMAgCAQACAwehIKEKMAgCAQACAwGGoDANBgkqhkiG9w0BAQUFAAOB
# gQALhAbrvvD2SdFXj/NRCh8yDMb/GvCXdXmbQBjR0dYYRfCNMMtDub23zWYf4MB+
# TK+YBycrVNSpvPbk0ckldLgygky0IJr8TF5TfLlsiqP3NRBiVFQoO8NNkXRZPjyj
# 37Pyr0MaBJ8H80ZyNIQiDuCd+j0o1mbss4LAkE42dX1H7jGCBA0wggQJAgEBMIGT
# MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdS
# ZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMT
# HU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwAhMzAAABsKHjgzLojTvAAAEA
# AAGwMA0GCWCGSAFlAwQCAQUAoIIBSjAaBgkqhkiG9w0BCQMxDQYLKoZIhvcNAQkQ
# AQQwLwYJKoZIhvcNAQkEMSIEIHaVJPJ3GXwjwOSm1OzH4cM8GxOuuwu/nX2Gd7lE
# 10LPMIH6BgsqhkiG9w0BCRACLzGB6jCB5zCB5DCBvQQgzQYLQ3fLn/Sk4xn9Ruuy
# HypnDRSZnlk3eopQMucVhKAwgZgwgYCkfjB8MQswCQYDVQQGEwJVUzETMBEGA1UE
# CBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9z
# b2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQ
# Q0EgMjAxMAITMwAAAbCh44My6I07wAABAAABsDAiBCAjuQasZZQFZuIbzjFvmtjE
# +F3YzLuxr4b3h5i8I6kxwDANBgkqhkiG9w0BAQsFAASCAgCRQGbseuuILaArIjLj
# owcA2YYyjRAYBXNHuUTDKi52PMRX/qOrRMTfLhmJWAzQsYwI/k0PHRmJEuZGoiYm
# 3q3D3fnjP0P/+P0o8fJiKB3qtTNT8PesCUwjjjzG6dq1GHYerIzaELM5MTH3cvPJ
# 80vkaR8QO7EJRf3W/ROuDFEZzeg9N07KnLtzXmze6uqZQtFMFGEJPmM5eJEv9Scd
# axi3OvC3o4piCbPNJ74r1fxm+s6/ag4STfVH5gl0SRD/gxnRu/y8DaoPai60Fiuh
# we1h1pSa5qxIWZeuIAeqdZBT1NFh6rorbcCVLSE9a8H6ecE8qHkU3VmgKxZ7a1KC
# aUEn2K+83nD37wrFPJypqY9V9wTC3TDs/R5vLPPFZe1hdB7PtiOvCJAkGh8kZ9dG
# aWmeS0gFvXSXXq58d7S93m9iOY6YJppbnta+PkyC3xGxBeHpmA0J6mqjuX01sUfD
# yGhwDvsTJjh9kE6oAWTqeuLMxDGwr0s11qcb4THbQPS1ThBZyG7xB6NuUXP1fAsS
# 1L3vGZ9LKzs/+cd1yhQVy7jNZdx1THVtx660L29WSHedGz0Kde1rZfzcvdE9gg1C
# FLhzFDWmVjku1rlxiW6669xQLOP3DLrE7QWNZiGbaYYYEjLGH7y86Hmp5Ftn8lYn
# rA4n1exo4CiefmW84Fj4y0a3bQ==
# SIG # End signature block
