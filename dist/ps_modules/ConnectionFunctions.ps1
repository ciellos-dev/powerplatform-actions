# Copyright (c) Microsoft Corporation. All rights reserved.
# typically sourced from SharedFunctions.psm1

$InformationPreference = 'Continue'

function Get-ServiceConnection {
    [CmdletBinding()]
    param([string][ValidateNotNullOrEmpty()]$serviceConnectionRef)

    begin { }

    process {
        $serviceConnection = Get-VstsEndpoint -Name $serviceConnectionRef -Require
    }

    end {
        return $serviceConnection
    }
}

function Get-PSCredentialFromServiceConnection {
    [CmdletBinding()]
    param([object][ValidateNotNullOrEmpty()]$serviceConnection)

    begin {
        $user = $serviceConnection.Auth.Parameters.UserName
        $password = $serviceConnection.Auth.Parameters.Password
    }

    process {
        $PSCredential = New-Object System.Management.Automation.PSCredential ($user, (ConvertTo-SecureString $password -AsPlainText -Force))
    }

    end {
        return $PSCredential
    }
}

function Get-SpnInfoServiceConnection {
    [CmdletBinding()]
    param([object][ValidateNotNullOrEmpty()]$serviceConnection)

    begin {
        $tenantId = $serviceConnection.Auth.Parameters.tenantId
        $applicationId = $serviceConnection.Auth.Parameters.applicationId
        $clientSecret = (ConvertTo-SecureString $serviceConnection.Auth.Parameters.clientSecret -AsPlainText -Force)
    }

    process {
        $spnInfo = [PSCustomObject]@{
            Credential  = (New-Object System.Management.Automation.PSCredential ($applicationId, $clientSecret))
            TenantId    = $tenantId
        }
    }

    end {
        return $spnInfo
    }
}

function Get-AuthInfoFromActiveServiceConnection {
    [CmdletBinding()]
    param(
        [string][ValidateNotNullOrEmpty()] $svcConnSelector = "authenticationType",
        [string] $selectedAuthName
    )

    if ([String]::IsNullOrEmpty($selectedAuthName)) {
        $selectedAuthName = Get-VSTSInput -Name $svcConnSelector -Require
    }
    $selectedAuthRef = Get-VSTSInput -Name $selectedAuthName -Require
    $serviceConnection = Get-ServiceConnection -serviceConnectionRef $selectedAuthRef

    $serviceConnection.url = Get-UrlFromEnvironmentVariables $serviceConnection.url

    if ($selectedAuthName -eq "PowerPlatformEnvironment") {
        # Write-Verbose "selected authN using username/password ($($selectedAuthName))."
         return @{
            EnvironmentUrl  = $serviceConnection.url
            Credential      = Get-PSCredentialFromServiceConnection $serviceConnection
            TenantId        = $null
            AuthType        = 'OAuth'
        }
    } elseif ($selectedAuthName -eq "PowerPlatformSPN") {
        # Write-Verbose "selected authN using SPN ($($selectedAuthName))."
        $credInfo = Get-SpnInfoServiceConnection $serviceConnection
        return @{
            EnvironmentUrl  = $serviceConnection.url
            Credential      = $credInfo.Credential
            TenantId        = $credInfo.tenantId
            AuthType        = 'ClientSecret'
        }
    }
 }

function Add-BapAdminConnection {
    [CmdletBinding()]
    param (
        [parameter(Mandatory = $true)][Hashtable]$authInfo,
        [parameter(Mandatory = $false)][string]$endpoint = "prod"
    )
    if ($authInfo.AuthType -eq "ClientSecret") {
        # fixing a breaking change in MS.PA.Admin.PS module that removed the -SecureClientSecret parameter
        $clientSecret = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($authInfo.Credential.Password))
        Add-PowerAppsAccount -ApplicationId $authInfo.Credential.UserName `
                            -ClientSecret $clientSecret `
                            -TenantID $authInfo.TenantId `
                            -Endpoint $endpoint
    } else {
        Add-PowerAppsAccount -Username $authInfo.Credential.UserName `
                            -Password $authInfo.Credential.Password `
                            -Endpoint $endpoint
    }
}

function Write-AuthLog {
    [CmdletBinding()]
    param (
        [parameter (Mandatory = $true)][Hashtable]$AuthInfo,
        [parameter (Mandatory = $false)][string]$TargetEnvironmentUrl
    )
    begin {

        $urlFrom = "BuildTools.EnvironmentUrl(pipeline variable)"
        if ([string]::IsNullOrWhiteSpace($TargetEnvironmentUrl)) {
            $TargetEnvironmentUrl = $AuthInfo.EnvironmentUrl
            $urlFrom = "Service Connection"
        }
        $prefix = Get-LogPrefix
        $decorator = Get-Decorator
    }
    process {
        Write-Information -MessageData $decorator
        Write-Information -MessageData "Url and Auth details"
        Write-Information -MessageData $decorator
        Write-Information -MessageData "$prefix Url read from       : $urlFrom"
        Write-Information -MessageData "$prefix Organization Url    : $TargetEnvironmentUrl"
        Write-Information -MessageData "$prefix User                : $($AuthInfo.Credential.UserName)"
        if ($AuthInfo.AuthType -eq 'OAuth') {
            Write-Information -MessageData "$prefix Authentication type : username and password"
        } else {
            Write-Information -MessageData "$prefix Authentication type : service principal and client secret"
        }
    }
    end{}
}

# SIG # Begin signature block
# MIInnAYJKoZIhvcNAQcCoIInjTCCJ4kCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCAIxIbUCDz326Hd
# +pgc+PAwKj3+NORYbQD8wIndvVEDnKCCDYEwggX/MIID56ADAgECAhMzAAACUosz
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
# BgEEAYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAvBgkqhkiG9w0BCQQxIgQg6xqBuTwH
# btnrqm9pIRI2gopupk9pD/enq8WXbixQ+uswNAYKKwYBBAGCNwIBDDEmMCSgEoAQ
# AFQAZQBzAHQAUwBpAGcAbqEOgAxodHRwOi8vdGVzdCAwDQYJKoZIhvcNAQEBBQAE
# ggEAv8oMn61knoyb3dC0g5XL40t7E+JqZSemgwGHIZHIlVy3jg2SjG1vtpHc5j5o
# CgLMIwBHpttFBB7ZDDJi64lNlR18ULyEH40Hvyy/wCI3JyLvAZFxXC1BrW9KOezj
# c84aWsYaFX4utb+L95BC+Yd7lmFcjA+n08pQyicCCVk6hRkyEUCXepL0H5lZ4W/t
# uYknWSkCrpbrTkUf89dvurLRmfv/n95lipLXPnHdDygsJkv80Cc/f5VJMzfLGyh5
# VylR61DSBLQxzOAOj+Ik2XA1LzwmK87oj+UkFsi5dZ82VnZTRNBMe41tWbPVoagp
# Agd5q/mgMkq4d1VP8dVVQrnwQ6GCFwkwghcFBgorBgEEAYI3AwMBMYIW9TCCFvEG
# CSqGSIb3DQEHAqCCFuIwghbeAgEDMQ8wDQYJYIZIAWUDBAIBBQAwggFVBgsqhkiG
# 9w0BCRABBKCCAUQEggFAMIIBPAIBAQYKKwYBBAGEWQoDATAxMA0GCWCGSAFlAwQC
# AQUABCBpFvTXJg5/uXvCt7FJUJe0VbNlpFBkiaqy5v6kihIDjwIGYrIU9AsqGBMy
# MDIyMDcwNzIxNDIyMy41MzdaMASAAgH0oIHUpIHRMIHOMQswCQYDVQQGEwJVUzET
# MBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMV
# TWljcm9zb2Z0IENvcnBvcmF0aW9uMSkwJwYDVQQLEyBNaWNyb3NvZnQgT3BlcmF0
# aW9ucyBQdWVydG8gUmljbzEmMCQGA1UECxMdVGhhbGVzIFRTUyBFU046RDlERS1F
# MzlBLTQzRkUxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2Wg
# ghFcMIIHEDCCBPigAwIBAgITMwAAAaxmvIciXd49ewABAAABrDANBgkqhkiG9w0B
# AQsFADB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UE
# BxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYD
# VQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDAeFw0yMjAzMDIxODUx
# MjlaFw0yMzA1MTExODUxMjlaMIHOMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2Fz
# aGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENv
# cnBvcmF0aW9uMSkwJwYDVQQLEyBNaWNyb3NvZnQgT3BlcmF0aW9ucyBQdWVydG8g
# UmljbzEmMCQGA1UECxMdVGhhbGVzIFRTUyBFU046RDlERS1FMzlBLTQzRkUxJTAj
# BgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2UwggIiMA0GCSqGSIb3
# DQEBAQUAA4ICDwAwggIKAoICAQDHeAtQxRdi7sdxzCvABJTHUxeIhvUTsikFhXoU
# 13vhF9UDq0wRZ4TACjRyEFqMZCtVutv6EEEJrSB6PLKYTLdVqZCzbwpty2vLHVS9
# 7fwQMe1FpJn77oydyg2koLd3JXObjT1I+3t9lOJ/xKfaDnPj7/xB3O1xh9Xxkby0
# WM8KMT9cZCpXrrGyM0/2ip+lgtgYID84x14p/ShO5K4grqgPiTYbJJHnUxyUCKLW
# 5Ufq2XLHsU0pozvme0dJn3h4lPA57b2b2f/WnfV1IQ8FCRSmfGWb8Z6p2V8BWJAy
# jWoGPINOgRdbw7pW5QLOgOIbj9Xu6bShaaQdVWZC1AJiFtccSRrN5HonQE1iFcdt
# rBlcnpmk9vTX7Q6f40bA8P2ocL9TZL+lr8pKLytJAzyGPUwlvXEW71HhJZPvglTO
# 3CKq5fEGN5oBEPKIuOVcxAV7mNOGNSoo2xi2ERTVMqVzEQwKVfpHIxvLkk9d5kgn
# 9ojIVkUS8/f48iMHu5Zl8+M1MmHJK/tjZvBq0quX1QD7ISDvAG/2jqOv6Htxt2Pn
# IpfIskSSyTcWzGMYkCSmb28ZQiKfqRiJ2g9d+9zOyjzxf8l3k+IRtC6lyr3pZILZ
# ac3nz65lFbqY2E4Hhn7qVMBc8pkpOCUTTtbYUQdGwygyMjTFahLr1dVMXXK4nFdK
# I4HiRwIDAQABo4IBNjCCATIwHQYDVR0OBBYEFFgRn3cEyx9AZ0o8fElamFrAQI5N
# MB8GA1UdIwQYMBaAFJ+nFV0AXmJdg/Tl0mWnG1M1GelyMF8GA1UdHwRYMFYwVKBS
# oFCGTmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY3JsL01pY3Jvc29m
# dCUyMFRpbWUtU3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNybDBsBggrBgEFBQcBAQRg
# MF4wXAYIKwYBBQUHMAKGUGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMv
# Y2VydHMvTWljcm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBDQSUyMDIwMTAoMSkuY3J0
# MAwGA1UdEwEB/wQCMAAwEwYDVR0lBAwwCgYIKwYBBQUHAwgwDQYJKoZIhvcNAQEL
# BQADggIBAHnQtQJYVVxwpXZPLaCMwFvUMiE3EXsoVKbNbg+u8wgt9PH0c2BREv9r
# zF+6NDmyYMwsU9Z4tL5HLPFhtjFCLJPdUQjyHg800CLSKY/WU8/YdLbn3Chpt2oZ
# J0bNYaFddo0RZHGqlyaNX7MrqCoA/hU09pTr6xLDYyYecBLIvjwf5lZofyWtFbvI
# 4VCXNYawVEOWIrEODdNLJ2cITqAnj123Q+hxrNXJrF2W65E/LzT2FfC5yOJcbif2
# GmEttKkK+mPQyBxQzWMWW05bEHl7Pyo54UTXRYghqAHCx1sHlnkbM4dolITH2Nf+
# /Xe7KJn48emciT2Tq+HxNFE9pf6wWgU66D6Qzr6WjrGOhP7XiyzH8p6+lDkHhOJU
# YsOfbIlRsgBqqUwU23cwBSwRR+NLm6+1RJXZo4h2teBJGcWL3IMysSqrm+Mqymn6
# P4/WlG8C6y9lTB1nKWtfCYb+syI3dNSBpFHY91CfiSkDQM+Xsj8kEmT7fcLPG8p6
# HRpTOZ2JBwcu6z74+Ocvmc+46y4I4L2SIsRrM8KisiieOwDx8ax/BowkLrG71vTR
# eCwGCqGWRo+z8JkAPl5sA+bX1ENCrszERZjKTlM7YkwICY0H/UzLnN6WJqRVhK/J
# LGHcK463VmACwlwPyEFxHQIrEMI+WM07IeEMU1Kvr0UsbPd8gd5yMIIHcTCCBVmg
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
# bGVzIFRTUyBFU046RDlERS1FMzlBLTQzRkUxJTAjBgNVBAMTHE1pY3Jvc29mdCBU
# aW1lLVN0YW1wIFNlcnZpY2WiIwoBATAHBgUrDgMCGgMVALEa0hOwuLBJ/egDIYzZ
# F2dGNYqgoIGDMIGApH4wfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0
# b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3Jh
# dGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAwDQYJ
# KoZIhvcNAQEFBQACBQDmcaq8MCIYDzIwMjIwNzA3MjI1NTU2WhgPMjAyMjA3MDgy
# MjU1NTZaMHQwOgYKKwYBBAGEWQoEATEsMCowCgIFAOZxqrwCAQAwBwIBAAICIuww
# BwIBAAICEPwwCgIFAOZy/DwCAQAwNgYKKwYBBAGEWQoEAjEoMCYwDAYKKwYBBAGE
# WQoDAqAKMAgCAQACAwehIKEKMAgCAQACAwGGoDANBgkqhkiG9w0BAQUFAAOBgQB6
# 6kMVQKdNcfbE2GHzfnbRJpx4hjCvAiRwv2Aat9+bbd3FNDaRuFE6kme3sBQXXDlI
# udpF8xAoSAVbZJMFF6AciC7q4ndDwPoFl6evDbLrGHIzXbTUcBYIDYQiV/fPi6yY
# dxMYh8qI4Ut/IkNuelZNM/FIKrhczoXS6pmivcWz7DGCBA0wggQJAgEBMIGTMHwx
# CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
# b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1p
# Y3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwAhMzAAABrGa8hyJd3j17AAEAAAGs
# MA0GCWCGSAFlAwQCAQUAoIIBSjAaBgkqhkiG9w0BCQMxDQYLKoZIhvcNAQkQAQQw
# LwYJKoZIhvcNAQkEMSIEIIKFycXNY+Ius5a/S1VGtb2ltBb34ck6cekYV+xAAJdO
# MIH6BgsqhkiG9w0BCRACLzGB6jCB5zCB5DCBvQQg+bcBkoM4LwlxAHK1c+epu/T6
# fm0CX/tPi4Nn2gQswvUwgZgwgYCkfjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMK
# V2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0
# IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0Eg
# MjAxMAITMwAAAaxmvIciXd49ewABAAABrDAiBCC+McKASpsUbsZAwo3b3vHbsCFI
# Gj6BiFqCzi7RiumeaTANBgkqhkiG9w0BAQsFAASCAgBRTApx63MSdr7EaOde8cQZ
# HMHqStnlJXnGjBKiuTG0J4A1poWVb9LcpJbVAWqKQkQeGxRhZZW/mLJSbQpbb1OK
# SPslXnEQ1mLCY6tLoek3yXr5Xn588rZmUAurFzW+u/duf3YCuAc6+nOgVF0Hd7Xz
# sbcogtm5zO5/SqFMroF0BMIuSM0jDXtD4cKN6yVvhZEljalgTV/hq3d0lFFVqbxP
# 4ZSIwv9nENvlkfrtlM3T3HxpPR2346u7Hi+9IL8sKOxQRPBVwp3aCfhMuVRlvMS2
# V8B/wLyshoOpInO378jCdxzY3Jl0lyfFDDiN6THh1FobeewiKPpF66xnw02SrLWF
# F5vsHSUsrRrI2JQvZD4Y1MeD6wAXMgrnfWejRQLDrR5bkdt5p9KpV7CQKdd1vNrf
# hvTyEOe8xzyJLdJeKl4KFIF6ct8nOYPAIdh1SNYcLQGiep83o/tcsMqazX2Nw9OQ
# pBPdf9Qozwe/Hg33EBqkSnT995zGDmHemHt24K8ZHb7m2ChvvZ0VzvUUg/rhzmpM
# mZwSZUqpV5ngqqD6a2PeIgpjx0rTXLAcgvSGrXpTFa+qhMgasZPIkqhfiaUofFDH
# u8Kf0dK1j8zOiyOM8MiKwMNshobKP5ZbcGCVDUPH2MzA/MnOXSyd6Q5D8KWiAjsY
# vXT8S/A+OGVdINQXs5Y1cQ==
# SIG # End signature block
