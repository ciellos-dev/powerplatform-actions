# Copyright (c) Microsoft Corporation. All rights reserved.

[CmdletBinding()]
param()

function Reset-Environment {
    [CmdletBinding()]
    param (
        # Shared Parameters
        [parameter (Mandatory = $true)][Hashtable]$authInfo,
        [parameter (Mandatory = $true)][string]$Language,
        [parameter (Mandatory = $false)][string]$DomainName,
        [parameter (Mandatory = $false)][string]$FriendlyName
    )

    begin {

        $organizationInfo = Get-OrgInfo @authInfo -InformationAction Continue
        $resetRequest = [pscustomobject]@{
            BaseLanguageCode = $Language
        }

        $endpoint = Get-Endpoint -EnvironmentUrl $authInfo.EnvironmentUrl
        Add-BapAdminConnection $authInfo -endpoint $endpoint
    }

    process {

        # Create Reset Instance job
        $EnvironmentURL = $authInfo.EnvironmentUrl
        Write-Host "Starting reset instance operation for $EnvironmentURL..."
        $opTime = [Diagnostics.Stopwatch]::StartNew()

        if (![String]::IsNullOrEmpty($FriendlyName)) {
            $resetRequest | Add-Member -MemberType NoteProperty -Name 'FriendlyName' -Value $FriendlyName
        }
        if (![String]::IsNullOrEmpty($DomainName)) {
            $resetRequest | Add-Member -MemberType NoteProperty -Name 'DomainName' -Value $DomainName
        }

        $response = Reset-PowerAppEnvironment -EnvironmentName $organizationInfo.EnvironmentId -ResetRequestDefinition $resetRequest -WaitUntilFinished $true

        if ($null -eq $response -or $response.Code -ne '200') {
            Write-Error $response
            return
        }

        $isAdminModeDisabled = Disable-PowerPlatformAdminMode -EnvironmentName $organizationInfo.EnvironmentId

        if (!$isAdminModeDisabled) {
            Write-Warning "The reset environment task is completed. but, the system could not disable the admin mode..."
        }

        $existingDomianName = Get-DomainNameFromUrl -Url $EnvironmentURL
        if ($existingDomianName -ne $DomainName) {
            $EnvironmentURL = $EnvironmentURL.Replace($existingDomianName, $DomainName)
            $authInfo["EnvironmentUrl"] = $EnvironmentURL
        }

        Set-EnvironmentInfo -EnvironmentUrl $EnvironmentURL `
                            -EnvironmentId $organizationInfo.EnvironmentId `
                            -OrganizationId $organizationInfo.OrganizationId `
                            -OrgUniqueName $organizationInfo.UniqueName

        Write-Verbose "Total time for resetting environment: $($opTime.Elapsed.TotalSeconds) sec"
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
    $language = Get-VSTSInputWithDefault  -Name "Language" -taskJsonFile $taskJson

    $overrideDomainName = Get-VSTSInputWithDefault  -Name "OverrideDomainName" -taskJsonFile $taskJson -AsBool

    if (!$overrideDomainName) {
        $domainName = Get-VSTSInputWithDefault  -Name "DomainName" -taskJsonFile $taskJson
    }

    $overrideFriendlyName = Get-VSTSInputWithDefault  -Name "OverrideFriendlyName" -taskJsonFile $taskJson -AsBool
    if (!$overrideFriendlyName) {
        $friendlyName = Get-VSTSInputWithDefault  -Name "FriendlyName" -taskJsonFile $taskJson
    }

    $waitForEnvironmentAvailability = Get-VSTSInputWithDefault  -Name "WaitForEnvironmentAvailability" -taskJsonFile $taskJson -AsBool
    if (!$waitForEnvironmentAvailability) {
        Write-Warning "OBSOLETE: This task parameter will go away in the future; for now, it is being ignored. Reset Environment will always wait for completion"
    }

    Reset-Environment $authInfo `
        -Language $language -DomainName $domainName -FriendlyName $friendlyName

} finally {
    if ($null -ne $redirector) {
        $redirector.Dispose()
    }
    Trace-VstsLeavingInvocation $MyInvocation
}

# SIG # Begin signature block
# MIInnwYJKoZIhvcNAQcCoIInkDCCJ4wCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCA8ds8nHQqwyeY9
# dlNn7pLSh+0PYe1BjExien51AQWFuqCCDYEwggX/MIID56ADAgECAhMzAAACUosz
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
# BgEEAYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAvBgkqhkiG9w0BCQQxIgQgTsE+grFW
# WZbd2rcsSjC4CLz1INlksCxSWlNgp6QL1GAwNAYKKwYBBAGCNwIBDDEmMCSgEoAQ
# AFQAZQBzAHQAUwBpAGcAbqEOgAxodHRwOi8vdGVzdCAwDQYJKoZIhvcNAQEBBQAE
# ggEAU7sG7p5E1ri3rfB1gpMcEdwt5XYHvxjTDcFWUSfhiv5V8yp49n3dkPisUJwH
# /qv92sEjwlT3BGfHAkf/kJlV5iuX1qcWrzgFJP88KQ/lmgzt5EcoxZeMIbgRicF8
# 2LfIw4UzhJYfLKX60kY4/KO7OAhbK1jTpkBvHc5JkgH8BbUezBTDGqgZXUBs0UlR
# 0gHzPcLig6SuufXjBzjLyd45QUeN+ILgimMysQyO7hymjlo5QElnIpSsuxco9sNR
# UmReqpoe8iOJmlMwBh5i29ye0+WJl0g7dmShg+vgNbcP/itY2claBVYcxV9PyKUA
# /x/9OCaUUF90VfwXvlBD3Mfi4aGCFwwwghcIBgorBgEEAYI3AwMBMYIW+DCCFvQG
# CSqGSIb3DQEHAqCCFuUwghbhAgEDMQ8wDQYJYIZIAWUDBAIBBQAwggFVBgsqhkiG
# 9w0BCRABBKCCAUQEggFAMIIBPAIBAQYKKwYBBAGEWQoDATAxMA0GCWCGSAFlAwQC
# AQUABCDAwKjXEaOvN29tZqqj/llwa5n3EooN/lJTtLATy0lQIQIGYrGiRtdeGBMy
# MDIyMDcwNzIxNDIyMy41MjdaMASAAgH0oIHUpIHRMIHOMQswCQYDVQQGEwJVUzET
# MBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMV
# TWljcm9zb2Z0IENvcnBvcmF0aW9uMSkwJwYDVQQLEyBNaWNyb3NvZnQgT3BlcmF0
# aW9ucyBQdWVydG8gUmljbzEmMCQGA1UECxMdVGhhbGVzIFRTUyBFU046NDYyRi1F
# MzE5LTNGMjAxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2Wg
# ghFfMIIHEDCCBPigAwIBAgITMwAAAaQHz+OPo7pv1gABAAABpDANBgkqhkiG9w0B
# AQsFADB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UE
# BxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYD
# VQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDAeFw0yMjAzMDIxODUx
# MThaFw0yMzA1MTExODUxMThaMIHOMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2Fz
# aGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENv
# cnBvcmF0aW9uMSkwJwYDVQQLEyBNaWNyb3NvZnQgT3BlcmF0aW9ucyBQdWVydG8g
# UmljbzEmMCQGA1UECxMdVGhhbGVzIFRTUyBFU046NDYyRi1FMzE5LTNGMjAxJTAj
# BgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2UwggIiMA0GCSqGSIb3
# DQEBAQUAA4ICDwAwggIKAoICAQDAR44A+hT8vNT1IXDiFRoeGzkmqut+GPk41toT
# RfQZZ1sSyQhLjIlemBecemEzO09WSzOjZx9MIT8qYs921WUZsIBsk1ESn1cjyfPU
# d1mmfxzL3ACWZwjIC/pjqcRPeIMECQ/6qPFKrjqwigmP33I3IcVfMjJHyKj+vR51
# n1tK2rZPiNhmRdiEhckbbxLsSb2nCBQxZEF49x/l8vSB8zaqovoOeIkIzgDerN7O
# vJouq6r+vg/Qz1T4NXr+sKKyNxZWM6zywiLp7G7WLd18N2hyjHwPkh/AleIqif3h
# GVD9bhSU+dDADzUJSMFhEWunHHElQeZjdmIB3/Mw1KkFOJNvw1sPteIi5MK4DZX3
# Wd/Fd8ZsQvZmXPWJ8BXN9sYtHMz8zdeQvMImRCKgnXcW8IpnPtC7Tymp3UV5NoTH
# 8INF6WWicQ3y04L2I1VOT104AddJoVgAP2KLIGwfCs7wMVz56xJ2IN1y1pIAWfpT
# qx76orM5RQhkAvayj1RTwgrHst+elYX3F5b8ACWrgJO1dJy1U4MIv+SC8h33xLmW
# A568emvrJ6g0xy/2akbAeRx6tFwaP4uwVbjF50kl5RQqNzp/CDpfCTikOAqyJa4v
# aliWDMbEiArHKLYDg6GDjuJZl5bSjgdJdCAIRF8EkiiA+UAGvcE6SGoHmtoc4yOk
# lGNVvwIDAQABo4IBNjCCATIwHQYDVR0OBBYEFOLQE5+s+AgS9sWUHdI4zekp4yTC
# MB8GA1UdIwQYMBaAFJ+nFV0AXmJdg/Tl0mWnG1M1GelyMF8GA1UdHwRYMFYwVKBS
# oFCGTmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY3JsL01pY3Jvc29m
# dCUyMFRpbWUtU3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNybDBsBggrBgEFBQcBAQRg
# MF4wXAYIKwYBBQUHMAKGUGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMv
# Y2VydHMvTWljcm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBDQSUyMDIwMTAoMSkuY3J0
# MAwGA1UdEwEB/wQCMAAwEwYDVR0lBAwwCgYIKwYBBQUHAwgwDQYJKoZIhvcNAQEL
# BQADggIBAAlWHFDRDJck7jwwRoYmdVOePLLBeidoPUBJVhG9nGeHS9PuRvO9tf4I
# kbUz74MUIQxeayQoxxo/JxUqjhPH52M/b4G9mHJWB75KCllCTg8Y4VkvktOmS0f5
# w0vOR3gwA9BRnbgAPNEO7xs5Jylto8aDR02++CkBDFolCtTNjwzfniEj1z4T7nRl
# Ri2yBAJNRqI+VY820LiyoZtk5OGttq5F5HhPfIMjaIx5QYR22+53sd8xgUwRpFbc
# Ldrne6jdq3KbiYbCf7y/9F2C7cjpO3kkGXX8ntE09f6o9fIklx7CFw4RzrkyqgYo
# mraKOFJ8JO7hsjNJb9/Gba/mKWo0j/qdDxDER/UXX6ykZuGx1eQpjkyMwJnOPWGb
# eNIYZVcJQpRQODPs593Mi5hBsHzag+vd4Q+Vt73KZ4X98YWW1Vk1aSR9Qjxk5keM
# uVPZMcMrCvFZXwhUcGFGueuNCrICL9bSYRfS13pliDxJ7sPSZ8x2d4ksOXW00l6f
# R5nTiSM7Dvv7Y0MGVgUhap2smhr92PMNSmIkCUvHCiYcJ4RoAT28mp/hOQ/U8mPX
# SpWdxYpLLcDOISmBhFJYN7amlhIpVsGvUmjXrTcY0n4Goe/Nqs2400IcA4HOiX9O
# xdmpNGDJzSRR7AW9TT8O+3YZqPZIvL6yzgfvnehptmf4w6QzkrLfMIIHcTCCBVmg
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
# bGVzIFRTUyBFU046NDYyRi1FMzE5LTNGMjAxJTAjBgNVBAMTHE1pY3Jvc29mdCBU
# aW1lLVN0YW1wIFNlcnZpY2WiIwoBATAHBgUrDgMCGgMVADQcKOKTa3xC+g1aPrcP
# erxiby6foIGDMIGApH4wfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0
# b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3Jh
# dGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAwDQYJ
# KoZIhvcNAQEFBQACBQDmcTg/MCIYDzIwMjIwNzA3MTQ0NzI3WhgPMjAyMjA3MDgx
# NDQ3MjdaMHcwPQYKKwYBBAGEWQoEATEvMC0wCgIFAOZxOD8CAQAwCgIBAAICCHwC
# Af8wBwIBAAICESwwCgIFAOZyib8CAQAwNgYKKwYBBAGEWQoEAjEoMCYwDAYKKwYB
# BAGEWQoDAqAKMAgCAQACAwehIKEKMAgCAQACAwGGoDANBgkqhkiG9w0BAQUFAAOB
# gQBHzMc+kQjCnbOcKwGSCyCvSnIGmiZ6ZI4qlqFnHKrVPUmFsYwFo+X+xG72I40X
# 3wU1VXQSskzCHq5O20llLzSM23LASFs2p569rpVQO+EKxpy3MtIwxiw4WMNk8fx1
# WziNlKtPBXI++Y+XwRhbgPvZAPBujSfJ1vw8Fe4DlzjUdTGCBA0wggQJAgEBMIGT
# MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdS
# ZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMT
# HU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwAhMzAAABpAfP44+jum/WAAEA
# AAGkMA0GCWCGSAFlAwQCAQUAoIIBSjAaBgkqhkiG9w0BCQMxDQYLKoZIhvcNAQkQ
# AQQwLwYJKoZIhvcNAQkEMSIEIMMUeA+32l3jDwQGYVaj2thyZ/pIsWMDL45io//t
# hnJ7MIH6BgsqhkiG9w0BCRACLzGB6jCB5zCB5DCBvQQgBfzgoyEmcKTASfDCd1sD
# Ahd6jmuWBxRuieLh42rqefgwgZgwgYCkfjB8MQswCQYDVQQGEwJVUzETMBEGA1UE
# CBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9z
# b2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQ
# Q0EgMjAxMAITMwAAAaQHz+OPo7pv1gABAAABpDAiBCAsqvl7OL7gRXGT3rIFdGKC
# 9HV+I73nShHjNWg0TL5RVzANBgkqhkiG9w0BAQsFAASCAgArdBdMmxqVPGLTXPkm
# FbAdalSRar4X24AhS4Mcqzznn0ivNsNGtRCDvbnZTHqxxYTym5XUtXIKF1WdZmeR
# euBD4PIrwFdr9c5P8865ouNu4XKmFPIFkeOuN3i4PrPuHVrlnnz8OJcDws7s1YSD
# Tzi0e6kRq+Ah7sYAAS9BicMHRochY/ymMbDOZGP9Axc5Ey3E1Qrs5p6D/8OC/THg
# XhOSkv90pbaoaruwZ/ZJHE1LW1RvTWhvpQtIH0MmdfKjPcoVp8sCklK36k7gYVDo
# I80hYVJPATAxYE6Lz5k3hbJAjLeH5TUbLUJ8H0KJK/UeJ+7iGWDpZboPKlUvIlcU
# Q2QIzvcRisAcedV5f/vdrDlGdd6v056mjfiFbC7ryM0W8Jw8gvcA+hYw2d9LcTJl
# UtLzPKXHkC/45KMQH23tMniwIUry/MvKdNWgmslZDFn6A6TTzYJAxQfzXw1nQpP9
# rVaOjHeNZSzEa7BvXNEn4TFia+QFwqrvaEcit7Vm9KYifevbvdhgRQHdf0oi0A9i
# VdHfLELpTaN+AREzkCSecWdTD6D5mCE/LGU1Fjz3tTCZSglKwJ+iuPFCI5sMKyv0
# Ze553ANr7b+z97IjAt2/bS0Ju20Onq0CScNhtWuWvOZfhfSfF3LcabJajKTl3Q78
# gvONvJaTHqMjAymrD8+LgSBRew==
# SIG # End signature block
