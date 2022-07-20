# Copyright (c) Microsoft Corporation. All rights reserved.

. (Join-Path -Path $PSScriptRoot "ConnectionFunctions.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot "PipelineVariables.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot "TaskInputs.ps1" -Resolve)

function Get-DomainNameFromUrl {
    [CmdletBinding()]
    param([string][ValidateNotNullOrEmpty()]$Url)

    begin {
        $uri = [System.Uri]$Url
    }

    process {
        $domainName = $uri.Host.Split('.')[0]
    }

    end {
        return $domainName
    }
}
function Get-Endpoint {
    [CmdletBinding()]
    param ([parameter(Mandatory = $true)][string][ValidateNotNullOrEmpty()]$EnvironmentUrl)

    $region = (([System.Uri]$EnvironmentUrl).DnsSafeHost) -split "\."
    $region[1] -match 'crm(?<suffix>\d+)' | Out-Null

    # TODO: logic to identify US Govt DOD and US GOVT HIGH
    if ($matches.suffix -eq '10') {
            return 'tip1'
    }
    return 'prod'
}

function Import-PowerPlatformToolsPowerShellModule {
    [CmdletBinding()]
    param([string][ValidateNotNullOrEmpty()]$ModuleName)

    begin {
        $taskVariable = "PowerPlatformTools_$($ModuleName.Replace('.','_'))"
    }

    process {
        
        Get-VstsTaskVariable -Name $taskVariable
        Write-Host $taskVariable
        $newModulePath = Get-ActionInput -Name $taskVariable
        if ([string]::IsNullOrWhiteSpace($newModulePath)) {
            throw "$taskVariable is not defined. Please add the 'Power Platform Tool Installer' task before adding any other 'Power Platform' tasks in your pipeline"
        }

        Write-Verbose "Importing PowerPlatform tools PowerShell Module: $($ModuleName) from: $newModulePath"
        if ($env:PSModulePath.IndexOf($newModulePath, [StringComparison]::OrdinalIgnoreCase) -lt 0) {
            Write-Verbose("Adding $newModulePath to PSModulePath")
            $env:PSModulePath += ";$newModulePath"
            Write-Verbose "PSModPath: $env:PSModulePath"
        }
        Import-Module (Join-Path -Path $newModulePath $ModuleName)
    }

    end {}
}

function Get-BindingRedirector {
    Import-PowerPlatformToolsPowerShellModule -ModuleName "Microsoft.Xrm.InProcBindingRedirect.PS"
    return Get-Redirector
}

function Get-OutputDirectory {
    param (
        [parameter(Mandatory = $true)][string]$subFolderName
    )
    # Establish output directory
    # different variables are predefined depending on type of pipeline (build vs. release) and classic vs. yaml
    # https://docs.microsoft.com/en-us/azure/devops/pipelines/build/variables?view=azure-devops&tabs=yaml#agent-variables
    $hasArtifactFolder = $false
    if (Test-Path Env:BUILD_ARTIFACTSTAGINGDIRECTORY) {
        $baseOutDir = $Env:BUILD_ARTIFACTSTAGINGDIRECTORY
        $hasArtifactFolder = $true
    }
    elseif (Test-Path Env:PIPELINE_WORKSPACE) {
        $baseOutDir = $Env:PIPELINE_WORKSPACE
    }
    elseif (Test-Path Env:AGENT_BUILDDIRECTORY) {
        $baseOutDir = $Env:AGENT_BUILDDIRECTORY
    } else {
        $baseOutDir = Get-Location
    }
    $outputDirectory = Join-Path $baseOutDir $subFolderName
    New-Item $outputDirectory -ItemType Directory -Force | Out-Null
    return @{
        path                = $outputDirectory
        hasArtifactFolder   = $hasArtifactFolder
    }
}

function Disable-AdminMode {
    [CmdletBinding()]
    param (
        [parameter (Mandatory = $true)][uri]$ApiUrl,
        [parameter (Mandatory = $true)][Hashtable]$authInfo,
        [parameter (Mandatory = $true)][Guid]$InstanceId
    )
    begin {
        $adminModeSetting = New-CrmAdminModeSetting -AllowBackgroundOperations $true
    }
    process {
        $response = Disable-CrmAdminMode -AdminModeSettings $adminModeSetting `
                            -ApiUrl $ApiUrl `
                            -Credential $authInfo.Credential `
                            -TenantId $authInfo.TenantId `
                            -InstanceId $InstanceId
    }
    end {
        return $response
    }
}

function Disable-PowerPlatformAdminMode {
    [CmdletBinding()]
    param (
        [parameter(Mandatory = $true)][guid]$EnvironmentName,
        [parameter(Mandatory = $false)] $SecondsDelay = 30
    )
    begin {
        $OperationTimeout = 3600
        $waitTimer = [Diagnostics.Stopwatch]::StartNew()
        $percentChunk = [Math]::Max(($SecondsDelay / $OperationTimeout * 100),1)
        $percentTotal = 0
    }
    process{
        do {
            # Bug 8047625: Set-AdminPowerAppEnvironmentRuntimeState: User with system admin role unable to disable the admin mode for 10 to 15 min right after copy or restore operation.
            # Tenant Admins can able to disable admin mode immediately right after restore, and copy process whereas System Admins
            # unable to disable for 10 to 15 min. getting 403 exception(Status Code: '403'. Error Code: 'UserMissingRequiredPermission')
            # Note: the process runs infinitely(observed few times)even admin mode disabled successfully
            $response = Set-AdminPowerAppEnvironmentRuntimeState -EnvironmentName $EnvironmentName `
                -RuntimeState 'Enabled' -WaitUntilFinished $true -Verbose

            if ($response.Code -eq '200') {
                Write-Verbose "Enabled admin mode successfully!!!"
                return $true
            }
            if ($waitTimer.Elapsed.TotalSeconds -gt $OperationTimeout) {
                Write-Error $response
                Write-Error "Set Admin mode failed to complete within the timeout window."
                return $false
            }
            [int]$percentTotal = [Math]::Min(($percentTotal + $percentChunk), 99)
            Write-VstsSetProgress -Percent $percentTotal
            Start-Sleep -Seconds $SecondsDelay

        } while ($true)
    }
    end {}
}
function Get-LogPrefix {
    $prefix = -join([System.DateTime]::UtcNow.ToString(), " | INFO |")
    return $prefix
}

function Get-Decorator {
    return "*" * 100
}

# SIG # Begin signature block
# MIInnAYJKoZIhvcNAQcCoIInjTCCJ4kCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCD2+Y0qaihimoKy
# 5aSk8xOhS/IRoqoLKKbL+YGBCfzU86CCDYEwggX/MIID56ADAgECAhMzAAACUosz
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
# BgEEAYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAvBgkqhkiG9w0BCQQxIgQgc15uLL7f
# 7TZ+wL46z16i7fj1CA9N1B51U/BV+PL4yXEwNAYKKwYBBAGCNwIBDDEmMCSgEoAQ
# AFQAZQBzAHQAUwBpAGcAbqEOgAxodHRwOi8vdGVzdCAwDQYJKoZIhvcNAQEBBQAE
# ggEAxyG90tGvf0oGwzEemPFzwXvvdz7vFLTmdWC7RDDJsmx4vEm162BwsM4ug7Il
# 47VXO7aJiLIOATrtr7cRTpF+25s+KVoj8uS9v92y96+PLwsdkELEbG7F/OTZddWY
# VRrPH2x/4XKHW6iLk60YTj/2ct+Zgrws3FJJ04llOo9e0ZfCVTjskZoVDTy37Wb+
# NTZgDd2Lu1z3NpKdvD9L5VUQSdk0kw/t8H1yHzdNgdovT/4NjCqjgeDRbnXYW6Ue
# 4BLF+Nlt0VCCPZko84EQi7mTmPeRQqX6EG7ZuxCb9A7VhGdFX05slEHLizTNjV2Y
# LoCszdfa+Cg/5UP/T3UHGbIdfaGCFwkwghcFBgorBgEEAYI3AwMBMYIW9TCCFvEG
# CSqGSIb3DQEHAqCCFuIwghbeAgEDMQ8wDQYJYIZIAWUDBAIBBQAwggFVBgsqhkiG
# 9w0BCRABBKCCAUQEggFAMIIBPAIBAQYKKwYBBAGEWQoDATAxMA0GCWCGSAFlAwQC
# AQUABCCgoxKSVzENuBVkVUkSNmg6oBpRd2BiO8zu0lHbTxINfQIGYrIKmQeoGBMy
# MDIyMDcwNzIxNDIyMy4yOTFaMASAAgH0oIHUpIHRMIHOMQswCQYDVQQGEwJVUzET
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
# LwYJKoZIhvcNAQkEMSIEIF2NfEasn0XU1bIY7/1A6r1T8LLgxUqCyNNHrfG1xWTd
# MIH6BgsqhkiG9w0BCRACLzGB6jCB5zCB5DCBvQQgDhyv+rCFYBFUlQ9wK75OjskC
# r0cRRysq2lM2zdfwClcwgZgwgYCkfjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMK
# V2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0
# IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0Eg
# MjAxMAITMwAAAasJCe+rY9ToqQABAAABqzAiBCCnELJ2vYTT8gFyy6t9WkIF01Lx
# I4DL2AnB3AwFWut5CzANBgkqhkiG9w0BAQsFAASCAgCUkLjuioQK2Wl+DAzGxpK/
# +QldWxdEvUxBWRHmIVGAYysZxRvKvmVowYGKB9TB6BEed61fbs/1qGS7PVL+SACb
# Wx7eET6Db5SA95GWAOSoeMUHEFFgFnokNSoZUKrpVfapvaeD7i5UtQMj70+4eTE/
# f3H/GU+vA9DJkDRI7cuIzsv/4ObF8T2QEVflxQtI7h7C6cawM4XuAGo7GmPQ82Ze
# C3DGIC154jTucqNqmlM5sfEizICOZtbGYjj85S7ysRDGzDbfLsCASLgBZ892fp4T
# ZJFSHBmrECU8yMu+j+pMriZdUx8Iaq/iEs7QM0n9OO3SPUgdziVvmQQwL08v1DXR
# A0zqje2BfsAsc4nrs/THvYz/L9RDiAEXsfbZldEDqpWrXSFP4hEoTByrFiepg7zk
# 8ElwRA4/xp8V2vICArLl538SkwUv198ItET+wp+8fbWQWWBX0pX1+zOSvV/F4Ck5
# zMxleiYG9Cts0cU/Kuy8Ij1Y2AJ3YT1cuLRCsGErgGoSdGzicyT4+t8l7fSUQab9
# BbLMOceBfM2YgjoAg2QvRJq19w65l1s1r9DXWlAp4JV2UKW+jGX8cWAJBWBeL5nZ
# LIMepwrwX69MNY5luOnlK6rwdSN8lmXkjY5oKjnuf1jA5VdyJ4cp7t4IqhrSXPG3
# GUJsc42plFIfRIh2m0GDOw==
# SIG # End signature block
