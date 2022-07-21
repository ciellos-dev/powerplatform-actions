# Copyright (c) Microsoft Corporation. All rights reserved.

[CmdletBinding()]
param()

function Get-LatestManualBackup {
    [CmdletBinding()]
    param (
        [parameter (Mandatory = $true)][guid]$EnvironmentName
    )
    begin {
        $Parameters = . Get-ParameterValue
    }
    process {
        $response = Get-PowerAppEnvironmentBackups @Parameters
        if ($null -eq $response -or ($null -ne $response -and $response.value.Count -eq 0)) {
            Write-Warning "Cannot find any Manual Backups in the source environment: $EnvironmentName"
            return
        }

        $timeStampUtc = $response.value.GetEnumerator() `
                | Sort-Object -Property backupPointDateTime  -Descending `
                | Select-Object -First 1 `
                | Select-Object -Property backupPointDateTime
    }
    end {
        return $timeStampUtc.backupPointDateTime
    }
}

function Restore-Request {
    [CmdletBinding()]
    param (
        [parameter (Mandatory = $true)][Guid]$SourceEnvironmentId,
        [parameter (Mandatory = $false)][string]$TargetEnvironmentName
    )
    begin{
        $Parameters = . Get-ParameterValue
        $RestorePointDateTime = Get-LatestManualBackup -EnvironmentName $SourceEnvironmentId
        if ($null -eq $RestorePointDateTime) {
            return
        }
        $Parameters.Add('RestorePointDateTime',$RestorePointDateTime)

    }
    process{
        $restoreRequest = [pscustomobject]$Parameters
    }
    end{
        return $restoreRequest
    }
}

function Restore-Environment {
    [CmdletBinding()]
    param (
        [parameter (Mandatory = $true)][Hashtable]$AuthInfo,
        [parameter (Mandatory = $true)][guid]$SourceEnvironmentId,
        [parameter (Mandatory = $true)][PSCustomObject]$TargetEnvironmentInfo,
        [parameter (Mandatory = $true)][string]$TargetEnvironmentUrl,
        [parameter (Mandatory = $true)][bool]$DisableAdminMode
    )
    begin {
        $endpoint = Get-Endpoint -EnvironmentUrl $AuthInfo.EnvironmentUrl
        Add-BapAdminConnection $AuthInfo -endpoint $endpoint

    }
    process {
        $restoreRequest = Restore-Request -SourceEnvironmentId $SourceEnvironmentId `
                            -TargetEnvironmentName $frienldlyName

        Write-Host "Please be patient, the system is processing this request. It will wait for up to 60 min for completion, before failing the operation"
        $response = Restore-PowerAppEnvironment -EnvironmentName $TargetEnvironmentInfo.EnvironmentId `
                -RestoreToRequestDefinition $restoreRequest `
                -WaitUntilFinished $true `
                -TimeoutInMinutes 60 -Verbose

        if ($null -eq $response -or $response.Code -ne '200') {
            Write-Error $response
            Write-Error "Restore environment task failed..."
            return
        }
        Write-Host $response

        if ($DisableAdminMode) {
            $isAdminModeDisabled = Disable-PowerPlatformAdminMode -EnvironmentName  $TargetEnvironmentInfo.EnvironmentId

            if (!$isAdminModeDisabled) {
               Write-Error "The restore environment task is completed. but, the system could not disable the admin mode..."
               return
            }
           Set-EnvironmentInfo -EnvironmentUrl $TargetEnvironmentUrl `
                               -EnvironmentId $TargetEnvironmentInfo.EnvironmentId `
                               -OrganizationId $TargetEnvironmentInfo.OrganizationId `
                               -OrgUniqueName $TargetEnvironmentInfo.UniqueName
        }
    }
    end {
    }
}

Trace-VstsEnteringInvocation $MyInvocation
try {
    ("SharedFunctions.psm1", "Get-ParameterValue.ps1") `
        | %{ Join-Path -Path $PSScriptRoot $_ } | Import-Module -Force
    $redirector = Get-BindingRedirector

    Import-PowerPlatformToolsPowerShellModule -ModuleName "Microsoft.PowerApps.Administration.PowerShell"
    Import-PowerPlatformToolsPowerShellModule -ModuleName "Microsoft.Xrm.WebApi.PowerShell"

    $authInfo = Get-AuthInfoFromActiveServiceConnection

    $taskJson = Join-Path -Path $PSScriptRoot "task.json"
    $restoreLatestBackup = Get-VstsInputWithDefault -Name "RestoreLatestBackup" -taskJsonFile $taskJson -AsBool
    $targetEnvironmentUrl = Get-VstsInputWithDefault -Name "TargetEnvironmentUrl" -taskJsonFile $taskJson
    $frienldlyName = Get-VstsInputWithDefault -Name "FriendlyName" -taskJsonFile $taskJson
    $disableAdminMode = Get-VstsInputWithDefault -Name "DisableAdminMode" -taskJsonFile $taskJson -AsBool
    if (!$restoreLatestBackup) {
        $restoreTimeUtc = Get-VstsInputWithDefault -Name "RestoreTimeStamp" -taskJsonFile $taskJson
    }

    Write-AuthLog -AuthInfo $authInfo
    $sourceInfo = Get-OrgInfo @authInfo -InformationAction Continue

    Write-AuthLog -AuthInfo $authInfo -TargetEnvironmentUrl $targetEnvironmentUrl
    $targetInfo = Get-OrgInfo -EnvironmentUrl $targetEnvironmentUrl `
                              -Credential $authInfo.Credential `
                              -TenantId $authInfo.TenantId `
                              -AuthType $authInfo.AuthType `
                              -InformationAction Continue

    if ([String]::IsNullOrEmpty($friendlyName)) {
        $frienldlyName = $targetInfo.FriendlyName
    }


    Restore-Environment -AuthInfo $authInfo `
                        -SourceEnvironmentId $sourceInfo.EnvironmentId `
                        -TargetEnvironmentInfo $targetInfo `
                        -TargetEnvironmentUrl $targetEnvironmentUrl `
                        -DisableAdminMode $disableAdminMode

} finally {
    Remove-Module Get-ParameterValue
    Trace-VstsLeavingInvocation $MyInvocation
}

# SIG # Begin signature block
# MIInnwYJKoZIhvcNAQcCoIInkDCCJ4wCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDbmgVpa2E/Ior1
# veVRrbtBNXRX0xk/67p3ULA/NY3ttaCCDYEwggX/MIID56ADAgECAhMzAAACUosz
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
# BgEEAYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAvBgkqhkiG9w0BCQQxIgQg2n+mNxqY
# bjEfxov03xgrAqKdnthn4HlA2NtLO3zkGIswNAYKKwYBBAGCNwIBDDEmMCSgEoAQ
# AFQAZQBzAHQAUwBpAGcAbqEOgAxodHRwOi8vdGVzdCAwDQYJKoZIhvcNAQEBBQAE
# ggEAAYV0+1sqbevN9GwIBH0+aDG7/mcNxCp5xMJzjSoTr8QtLB8A7xIwx3ypXNcW
# IUSzBVtRqz6FosAOvsZN+mL9QmYtkLZUIW2OeGh0fM7Ilq/g086jomQU3LxB7NuU
# SGG1LH9MnzKDpAgdB4BFxkzFi4wJ6sgk178+Pt0Kx8yMQvCsl/kRicr6hDSS2HfS
# UVCS9aWkmXJd3Xra8OJTOXfTjHkDoCGHcz+vg4oAOKjC3eDW9zMzvSflvg/aUEmH
# GzjhA/fUax18+kmj+RzdKeqTQGNktbBra3bf1kKXC3jjuG6mTy4i+WQVTVs50Emv
# rLcxECYaeHx5ZG5N/WSeYfd8KaGCFwwwghcIBgorBgEEAYI3AwMBMYIW+DCCFvQG
# CSqGSIb3DQEHAqCCFuUwghbhAgEDMQ8wDQYJYIZIAWUDBAIBBQAwggFVBgsqhkiG
# 9w0BCRABBKCCAUQEggFAMIIBPAIBAQYKKwYBBAGEWQoDATAxMA0GCWCGSAFlAwQC
# AQUABCCBMpDOkjIH+royyqAPS5aQ7dv+ey8QI2t3kDROoS36+wIGYrGuwKW2GBMy
# MDIyMDcwNzIxNDIyMy41NDZaMASAAgH0oIHUpIHRMIHOMQswCQYDVQQGEwJVUzET
# MBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMV
# TWljcm9zb2Z0IENvcnBvcmF0aW9uMSkwJwYDVQQLEyBNaWNyb3NvZnQgT3BlcmF0
# aW9ucyBQdWVydG8gUmljbzEmMCQGA1UECxMdVGhhbGVzIFRTUyBFU046QzRCRC1F
# MzdGLTVGRkMxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2Wg
# ghFfMIIHEDCCBPigAwIBAgITMwAAAaP7mrOOe4ZDTwABAAABozANBgkqhkiG9w0B
# AQsFADB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UE
# BxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYD
# VQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDAeFw0yMjAzMDIxODUx
# MTZaFw0yMzA1MTExODUxMTZaMIHOMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2Fz
# aGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENv
# cnBvcmF0aW9uMSkwJwYDVQQLEyBNaWNyb3NvZnQgT3BlcmF0aW9ucyBQdWVydG8g
# UmljbzEmMCQGA1UECxMdVGhhbGVzIFRTUyBFU046QzRCRC1FMzdGLTVGRkMxJTAj
# BgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2UwggIiMA0GCSqGSIb3
# DQEBAQUAA4ICDwAwggIKAoICAQDvvU3Ky3sqCnAqi2zbc+zbdiWz9UxM8zIYvOIE
# umCyOwhenVUgOSNWxQh3MOmRdnhfEImn9KNl0l3/46ebIJlGLTGxouJ3gLVkjSuc
# obeIskIQcZ9EyEKhfjYrIgcVvnoTGFhGxSPu3EnV/3VsPv2PPzLvbqt1wiuT9hvm
# Ym1cDlR/efiIkxp5qHMVoHbNKpQaWta2IN25fF1XuS9qk1JiQb50Kcdm1K7u9Jbd
# vx6FOWwWyygIQj6ccuJ5rK3Tkdxr+FG3wJraUJ7T++fDUT4YNWwAh9OhZb2yMj/P
# 7kbN8dt9t3WmhqSUGEKGaQAYOtqxQ0yePntOrbfsW376fDPZaPGtWoH8WUNaSE9V
# ZyXWjvfIFjIjFuuXXhVIlEflp4EFX79oC7L+qO/jnKc8ukR2SJulhBmfSwbee9TX
# wrMec9CJb6+kszdEG2liUyyFm18G1FSmHm61xFRTMoblRkB3rGQflcFd/OoWKJzM
# bNI7zPBqTnMdMS8spuNlwPfVUqbLor0yYOKPGtQAiW0wVRaBAN1axUmMznUOr818
# a8cOov09d/JvlxfsirQBJ4aflHgDIZcO4z/fRAJYBlJdCpHAY02E8/oxMj4Cmna1
# NaH+aBYv6vWA5a1b/R+CbFXvBhzDpD0zaAeNNvI/PDhHuNugbH3Fy5ItKYT6e4q1
# tAG0XQIDAQABo4IBNjCCATIwHQYDVR0OBBYEFFBR+7M8Jgixz00vQaNoqy5yY4uq
# MB8GA1UdIwQYMBaAFJ+nFV0AXmJdg/Tl0mWnG1M1GelyMF8GA1UdHwRYMFYwVKBS
# oFCGTmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY3JsL01pY3Jvc29m
# dCUyMFRpbWUtU3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNybDBsBggrBgEFBQcBAQRg
# MF4wXAYIKwYBBQUHMAKGUGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMv
# Y2VydHMvTWljcm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBDQSUyMDIwMTAoMSkuY3J0
# MAwGA1UdEwEB/wQCMAAwEwYDVR0lBAwwCgYIKwYBBQUHAwgwDQYJKoZIhvcNAQEL
# BQADggIBAFry3qdpl8OorgcRrtD7LLZlyOYC5oD5EykJ44GZbKHoqbLWvaJLtDE1
# cZR1XXHQWxXFRzC0UZFBSJHyp2nJcpeXso9N8Hg+m/6VHxcg2QfAGaRlF4U2CzUf
# D3qTOsg+oPtBNZx9DIThqBOlxbn5G5+niHTUxrlsAXhK9gzYhoQxpcGlB+RC894b
# bsjMligIGBdvAuIssoWHb5RvVTeiZwuJnPxCLedAQh6fGUAJOxwt0TpbYNYLuTYx
# mklXYrGouTiVn+nubGEHQwTWClyXYh3otTeyvi+bNb1fgund07BffgDaYqAQwDhp
# xUmLeD/rrVtdYt+4iyy2/duqQi+C8vvhlNMJc2H5+59tkckJrw9daMomR4ZkbLAw
# arAPp7wlbX5x9fNw3+aAQVbJM2XCU1IwsWmoAyuwKgekANx+5f9khXnqn1/w7XZX
# uAfrz1eJatQgrNANSwfZZs0tL8aEQ7rGPNA0ItdCt0n2StYcsmo/WvKW2RtAbAad
# jcHOMbTgxHgU1qAMxfZKOFendPbhRaSay6FfnvHCVP4U9/kpVu3Z6+XbWL84h06W
# brkb+ClOhdzkMzaR3+3AS6VikV0YxmHVZwBm/Dc1usFk42YzAjXQhRu6ZCizDhna
# jwxXX5PhGBOUUhvcsUu+nD316kSlbSWUnCBeuHo512xSLOW4fCsBMIIHcTCCBVmg
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
# bGVzIFRTUyBFU046QzRCRC1FMzdGLTVGRkMxJTAjBgNVBAMTHE1pY3Jvc29mdCBU
# aW1lLVN0YW1wIFNlcnZpY2WiIwoBATAHBgUrDgMCGgMVAB5f6V5CzAGz2qQsGvhl
# 3N0pQw0ToIGDMIGApH4wfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0
# b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3Jh
# dGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAwDQYJ
# KoZIhvcNAQEFBQACBQDmcUTwMCIYDzIwMjIwNzA3MTU0MTM2WhgPMjAyMjA3MDgx
# NTQxMzZaMHcwPQYKKwYBBAGEWQoEATEvMC0wCgIFAOZxRPACAQAwCgIBAAICIvUC
# Af8wBwIBAAICEiwwCgIFAOZylnACAQAwNgYKKwYBBAGEWQoEAjEoMCYwDAYKKwYB
# BAGEWQoDAqAKMAgCAQACAwehIKEKMAgCAQACAwGGoDANBgkqhkiG9w0BAQUFAAOB
# gQAjeaXueQNCf1kq2VdZkdovB4dKz+umETcP1pXxrqkszoRvRet9qUuf4fokarPc
# qu8v0fKSKqKl3Wb73XG26leIDv+0rCYBH3gAeoylnSHqYN59615AN04A5e8a2CDq
# 5dCdyjRXkMNe/BDP0aaNt03VfrQcZNjUlkd9BS887Yk5LDGCBA0wggQJAgEBMIGT
# MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdS
# ZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMT
# HU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwAhMzAAABo/uas457hkNPAAEA
# AAGjMA0GCWCGSAFlAwQCAQUAoIIBSjAaBgkqhkiG9w0BCQMxDQYLKoZIhvcNAQkQ
# AQQwLwYJKoZIhvcNAQkEMSIEINrT4f+JJfXoFKbWX0OjpvHbzCW8eb7v9MCwkyVO
# 2/ojMIH6BgsqhkiG9w0BCRACLzGB6jCB5zCB5DCBvQQgjPi4sAZxzDKDnf7IG2mM
# acLxCZURGZf6Uz5Jc+nrjf4wgZgwgYCkfjB8MQswCQYDVQQGEwJVUzETMBEGA1UE
# CBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9z
# b2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQ
# Q0EgMjAxMAITMwAAAaP7mrOOe4ZDTwABAAABozAiBCDGIUoGhi6jwTqvteGdxpm8
# IymNw4lLmLYHPoGh0f1JTjANBgkqhkiG9w0BAQsFAASCAgDTiFrvvdzb4m4Fk3SC
# KHN2/zf/Q0wYrG4Yesz2Bqf0+SjXjJUPTngJCjdJVeLnVPuoTeomfDyZUXPuYgD9
# F6ke0TDcCR/LxMsPYaz6Sf94Qbt5JhnVXxykL8ABZPNgeRc69uzNq8xn5GUhs46E
# r7RLbUnNKpXmqk/o07Yu92YuNrdtAruG1UFimC5QJjHdnZpt3w0zQ6/zhSR5cvL3
# VhFh5HhSQQbgY+/StYaArCn3TsP9ax9fVGPNdnwZPZBGcaZRBiA024QL4LzNMOcJ
# WcJkqWikwQZYkNqFRgkYCACfatOkyzBQHPBIEQIUi436TUNnAnctqzw7S47vqqBT
# z+MPHRs3EuPMfTzrXE5FWUQoqW+/uzsF9ZfLz+qf9MkhREnP8SxUTvg7IsLU9nAW
# yq81CV6/+nwYZIwZNVNB2mWz81UXY1DX/5f3hwlk8fOrOcqnIDivyTngzajjbE0Y
# U3/FmFgY/Cc5kVim0apwPOYNQ4LinlNfI7VioLgiX77Yn6GXOfPfO91IDBuP/MNF
# tuZSH4CBEh2VKMsZxU84PiNMW3/rP3YB5AD+gSF6BMNXE6dwa4IV4fuA8UyxWPaL
# uJqKDIgq6W6ASh/cN6Jaug0qf7li/OKLktJ2adXAiq60KLSx4mxF22NQ0UZ1Z2Pw
# u7DggCIDxdKd1RlGkoxxem8Zig==
# SIG # End signature block
