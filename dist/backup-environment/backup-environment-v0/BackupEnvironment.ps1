# Copyright (c) Microsoft Corporation. All rights reserved.

[CmdletBinding()]
param()

function Backup-Request {
    [CmdletBinding()]
    param (
        [parameter (Mandatory = $true)][string]$Label,
        [parameter (Mandatory = $true)][string]$Notes
    )
    begin{
        $Parameters = . Get-ParameterValue
    }
    process{
        $backupRequest = [pscustomobject]$Parameters
    }
    end{
        Remove-Module Get-ParameterValue
        return $backupRequest
    }
}
function Backup-Environment {
    [CmdletBinding()]
    param (
        [parameter (Mandatory = $true)][Hashtable]$AuthInfo,
        [parameter (Mandatory = $true)][string]$Label,
        [parameter (Mandatory = $true)][string]$Notes
    )
    begin {
        # Get Organization Information
        Write-AuthLog -AuthInfo $authInfo
        $organizationInfo = Get-OrgInfo @AuthInfo -InformationAction Continue

        $endpoint = Get-Endpoint -EnvironmentUrl $AuthInfo.EnvironmentUrl
        Add-BapAdminConnection $AuthInfo -endpoint $endpoint
    }
    process {
        $backupRequest = Backup-Request -Label $label -Notes $label
        $response = Backup-PowerAppEnvironment -EnvironmentName $organizationInfo.EnvironmentId `
                     -BackupRequestDefinition $BackupRequest
        #TODO: Need to disucss with BAP team for possible error code
        if ($null -eq $response -or $response.psobject.properties.name -notcontains 'backupPointDateTime') {
            Write-Error  $response
            Write-Error "The backup environment task failed..."
            return
        }
        Write-Verbose $response
    }
    end {
    }
}

Trace-VstsEnteringInvocation $MyInvocation
try {
    # Load shared functions and other dependencies
    ("SharedFunctions.psm1", "Get-ParameterValue.ps1") `
        | %{ Join-Path -Path $PSScriptRoot $_ } | Import-Module
    $redirector = Get-BindingRedirector

    Import-PowerPlatformToolsPowerShellModule -ModuleName "Microsoft.PowerApps.Administration.PowerShell"
    Import-PowerPlatformToolsPowerShellModule -ModuleName "Microsoft.Xrm.WebApi.PowerShell"

    # Get input parameters and credentials
    $authInfo = Get-AuthInfoFromActiveServiceConnection

    $taskJson = Join-Path -Path $PSScriptRoot "task.json"
    $label = Get-VstsInputWithDefault -Name "BackupLabel" -taskJsonFile $taskJson

    # Execute the backup function
    Backup-Environment $authInfo -Label $label -Notes $label

} finally {
    if ($null -ne $redirector) {
        $redirector.Dispose()
    }
    Trace-VstsLeavingInvocation $MyInvocation
}

# SIG # Begin signature block
# MIInnAYJKoZIhvcNAQcCoIInjTCCJ4kCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCD+lpicunjqH9qQ
# nSTGCFk3SP9LoG51mdKyjcR3jTCu8KCCDYEwggX/MIID56ADAgECAhMzAAACUosz
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
# BgEEAYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAvBgkqhkiG9w0BCQQxIgQg+WDErbN/
# yGm7yyuX9bionxHhlLLgn3nHbEpDONDsX0AwNAYKKwYBBAGCNwIBDDEmMCSgEoAQ
# AFQAZQBzAHQAUwBpAGcAbqEOgAxodHRwOi8vdGVzdCAwDQYJKoZIhvcNAQEBBQAE
# ggEAMb+hmjausvfeogk+RLquDT/vy25XUFCJkcI5NawsT2TyG81IiYhf2ksq3kda
# FbCqMBk7l1N20jKRLk0NhIdKAhG8YxDE7YUV+dyrFZynGnUqU1rhOg+GIYVNNam/
# 1Zemj85c4G0HTbFeYs006jwvYW3yDmDosMvY5Pthy3LTyH6Uqz0IQ91sw8gbk+u1
# xgfRftdNp7vdbzabFGIztHLcvWDTEawrfp2oCq/n2Y57j1M1HAs04stdbJQ2Pxy0
# 9t/j3oYx+jT9rnPLuHU/SWC+SIXzznPJEjIj5cX50GigdjHuZcbJeHt2xRY3m5iU
# I7ZYJy7ribvsma4wFdviPajIpKGCFwkwghcFBgorBgEEAYI3AwMBMYIW9TCCFvEG
# CSqGSIb3DQEHAqCCFuIwghbeAgEDMQ8wDQYJYIZIAWUDBAIBBQAwggFVBgsqhkiG
# 9w0BCRABBKCCAUQEggFAMIIBPAIBAQYKKwYBBAGEWQoDATAxMA0GCWCGSAFlAwQC
# AQUABCDrfOuTMNVhnl1CRcok5UGju/VMKw4w14NGmOFF/wZIcAIGYrIsJNVWGBMy
# MDIyMDcwNzIxNDIyMy4xMDhaMASAAgH0oIHUpIHRMIHOMQswCQYDVQQGEwJVUzET
# MBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMV
# TWljcm9zb2Z0IENvcnBvcmF0aW9uMSkwJwYDVQQLEyBNaWNyb3NvZnQgT3BlcmF0
# aW9ucyBQdWVydG8gUmljbzEmMCQGA1UECxMdVGhhbGVzIFRTUyBFU046Rjg3QS1F
# Mzc0LUQ3QjkxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2Wg
# ghFcMIIHEDCCBPigAwIBAgITMwAAAa6qC1yzNKWVGgABAAABrjANBgkqhkiG9w0B
# AQsFADB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UE
# BxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYD
# VQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDAeFw0yMjAzMDIxODUx
# MzdaFw0yMzA1MTExODUxMzdaMIHOMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2Fz
# aGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENv
# cnBvcmF0aW9uMSkwJwYDVQQLEyBNaWNyb3NvZnQgT3BlcmF0aW9ucyBQdWVydG8g
# UmljbzEmMCQGA1UECxMdVGhhbGVzIFRTUyBFU046Rjg3QS1FMzc0LUQ3QjkxJTAj
# BgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2UwggIiMA0GCSqGSIb3
# DQEBAQUAA4ICDwAwggIKAoICAQCTjBrxITUMCx2nLc5z6WPCYOaiPELIKdJoZdht
# s7VT6J6uILDjHubvaeX9ezyDNSl41GijZd3Y53KtvS4qpqp2ijkYIDxzRJO0PrWp
# eSMnPkvJP0d9YAhreKr0FagS0DYr8TrpFH2qRuNS03Sx3jOLsCJ5PkKxkB9iuMIz
# bYlKYqxdj3QnG5F8gCxKck9ka8MyZs3Jm3QrHGNDd0R8azHlkN5O7DbeNTQWTk/u
# KQppMPFJICokiVzMyrN/DMVKsfzpUvNHSw0x3fmXotUtf6mwrUxszZtG4+qn5JVD
# NyRQBdSS18ML6oGUXQ0FOttuMLRp8GpU2jiNEdHl/nK3D6VxgduxCIGFPtJaNmh+
# /Uja7D1hHHQSAndMn4RVNp4lSXqRs5F3rSb2xcVt4je7HIy38P0ulFxe8LRM3TjV
# 1YiOT9lDO+/T+hCGfoPNRNjFl/F4y1cryLL88nJCeBRYvodcjxPr83JD8cxzrIi2
# mn7nLMjIwGgDPFsGvtNgboxDspXy0spNIr/SL0iPWZCVv4C70ONlNPlNN+WYVIQq
# myhFhDCK9smtq2Ka1DBCnF3+Efey1TwX7CZ25DVLm6VAOCtYu4o0NaZFJbfmEP9+
# JrRMu3kooFaVc56n6zVXqwrxxuSMH3hVYTzWwMCupQRENvZzGI0V4+EC8r5ikZqj
# iTP8NQIDAQABo4IBNjCCATIwHQYDVR0OBBYEFNMwb9+/KGCKwamtdP787WQ6YVHu
# MB8GA1UdIwQYMBaAFJ+nFV0AXmJdg/Tl0mWnG1M1GelyMF8GA1UdHwRYMFYwVKBS
# oFCGTmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY3JsL01pY3Jvc29m
# dCUyMFRpbWUtU3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNybDBsBggrBgEFBQcBAQRg
# MF4wXAYIKwYBBQUHMAKGUGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMv
# Y2VydHMvTWljcm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBDQSUyMDIwMTAoMSkuY3J0
# MAwGA1UdEwEB/wQCMAAwEwYDVR0lBAwwCgYIKwYBBQUHAwgwDQYJKoZIhvcNAQEL
# BQADggIBAF2/kfD9VQBEDjytMwMQAyFz+HCUJmq7Y1RSzBJC2Id/TxbVW7fOEb9E
# NRkk2JoT/H/zjr55guXo8NzXNVUYu+K1hlCE79fFqq/HgbwEneHgwMRWwPJJzjpv
# 2ckpDAw2HW+u9/GkNMr6n+wFnIYD57QnP54TWqUiZo81JHuxL4wfHotAZ2NMZfgE
# HEsSRv1Z7JvSMDnq/BNZolS2Hz5/XyA3Wmr9W6vYvoJ2X9YUu2qRqcW4rQia9Shg
# +IyMgAZMR4XqDzoYbUJtbs5xO25SsR/KVO1tgPnqoILDZDN1QdJ680WQapuEpgUj
# YTj88t6Hzpi3ESv2paDgK+p3oYvIuZYZk4NS5DgMQoS8B75bogmPSvtryKbePIqC
# v4frc+UYFXW/kvMcJ+9vJTfCj5JAdkWuYonK77YAOecElHYehRcV8Xkvm7IAWsp+
# 2cmn06QzOwUDgWMGqHbLlX+V4Bq8hsfOJOEefJj8Ad0NPQkQBrN+TTrek6z16nMp
# Tbumc/MU0A3GiaeeKSsjqFuYiAxY6S53l0xI7VghQoAKOM26fQjSE6feyj53N4GV
# WjLxKVPEqe1WcDfXJEdlgysjow4ISHH7hSUyznZDrjCxrFj3Z2OonbVnNm1A0Gtk
# G85jUmchbYRKa8ENhpoGhmxirmFValI/2LdtRw9DwXgyOTGpfEnMMIIHcTCCBVmg
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
# bGVzIFRTUyBFU046Rjg3QS1FMzc0LUQ3QjkxJTAjBgNVBAMTHE1pY3Jvc29mdCBU
# aW1lLVN0YW1wIFNlcnZpY2WiIwoBATAHBgUrDgMCGgMVALyasJP8Z8nIFeRncuW+
# CMBP01rjoIGDMIGApH4wfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0
# b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3Jh
# dGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAwDQYJ
# KoZIhvcNAQEFBQACBQDmccJIMCIYDzIwMjIwNzA4MDAzNjI0WhgPMjAyMjA3MDkw
# MDM2MjRaMHQwOgYKKwYBBAGEWQoEATEsMCowCgIFAOZxwkgCAQAwBwIBAAICCqUw
# BwIBAAICEccwCgIFAOZzE8gCAQAwNgYKKwYBBAGEWQoEAjEoMCYwDAYKKwYBBAGE
# WQoDAqAKMAgCAQACAwehIKEKMAgCAQACAwGGoDANBgkqhkiG9w0BAQUFAAOBgQAh
# w6CLWfb4Y5UI7WlktYu/NVP0VDn4phjNuKsMINKBkvK6buPz+V5lwOej5RK4KvkY
# 06t6H+m8tUcY+MhmQI4Xzz0hlZ3kTaGSm/RBFjwSD2AZ791AYsp7cPy+6lvPgCs3
# /uWrzQ+SmaFAYJ8S+6MtQj+VDNrC6VdehzP+OxaSHjGCBA0wggQJAgEBMIGTMHwx
# CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
# b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1p
# Y3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwAhMzAAABrqoLXLM0pZUaAAEAAAGu
# MA0GCWCGSAFlAwQCAQUAoIIBSjAaBgkqhkiG9w0BCQMxDQYLKoZIhvcNAQkQAQQw
# LwYJKoZIhvcNAQkEMSIEIFiPCyadqALo6Ezyq4UkZ/vUlGb4WsSXL9VU5L9Ql33E
# MIH6BgsqhkiG9w0BCRACLzGB6jCB5zCB5DCBvQQgSSgdPriMw1qh7p9PZqk1PLjo
# OrXsNMrtbkNIlPxSb2gwgZgwgYCkfjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMK
# V2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0
# IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0Eg
# MjAxMAITMwAAAa6qC1yzNKWVGgABAAABrjAiBCCZTHE8B4SxfhZ9EPr+c510YYOF
# TXOpjRivPcsmCdGy6jANBgkqhkiG9w0BAQsFAASCAgCP6GDFBaWANXiYeWKDXNI8
# +i3TXJDIe3iKvE+ghMHDfYlKmQ2jcOFpW2APSKn8ldvH6ROKHj0NE2dJNAFs8pFb
# MfcXTh+NT/tfQS4PuvRZLmN5U3Yi20J0PDXmdCO1byGOLT0qzVvJl4ZVZxqL+epw
# 0xGcbR+zESETk1g0K30uvKJhm5+IMnS31mmP1JBsUq2qLihRMEZ1LmIpEs5L+fsn
# xjxoai6s+iJKj/RC06ytmUZvMIrpjTK12opFR9o3knKI6UI8r6QfHzV1aOTi0Hfh
# qPzNl6se1fBTISyA2vxUgeoLik4szJepyVsky3EmxholNiK9GoNwY08SnpG6NW8l
# jjU5dQqhD6l5ct04gbtAEhN+SGtCXTYHaJH4Om/WqbIG6CNH9OUsx3hXuSKpwfdm
# Y921GDSGnUc6tBHwL+N1KQ1hSltx10OSZhe5SvmEq6/eEZDlbLg66myd7NpoVrwC
# XSRqIA713OJQGdEhWQJMBrIBn7lmvIQif4+32ObomtId8CumSDsXWBRrpBGj7Uue
# CkFtpqiha7156ngAYmtFDLDTFgCDqEq2SueI5tB6b9iwP9YLKLCH/iir7wMqVk8H
# rW3KhQJTadtX/akDDzBFYoUng0ILpQjP1eQ/RhAjFoTCyAlQ+EcsqPiIgKogHMO4
# C7YrqJzsHDllo4S5Vh7VbA==
# SIG # End signature block
