# Copyright (c) Microsoft Corporation. All rights reserved.

[CmdletBinding()]
param()

$InformationPreference = 'Continue'

function Get-RegionKey {
    param (
        [parameter(Mandatory = $true)][string]$Region
    )
    begin {
    }
    process {

        $regionKey = Get-AdminPowerAppEnvironmentLocations | `
                Where-Object { $_.LocationName -eq $Region -or $_.LocationDisplayName -eq $Region } | `
                Select-Object -ExpandProperty LocationName

        if ($null -eq $regionKey) {
            Write-Warning "The region '$Region' cannot be validated; will tentatively continue with environment creation."
            return $Region
        }
    }
    end {
        return $regionKey
    }
}

function Get-LanguageKey {
    param (
        [parameter(Mandatory = $true)][string]$Region,
        [parameter(Mandatory = $true)][string][ValidateNotNullOrEmpty()] $taskJsonFile
    )
    begin {
        $language = Get-VstsInputWithDefault -Name "LanguageName" -taskJsonFile $taskJsonFile
    }
    process {
        $languageKey = Get-AdminPowerAppCdsDatabaseLanguages -LocationName $Region | `
                Where-Object { $_.LanguageName -eq $language -or $_.LanguageDisplayName -eq $language } | `
                Select-Object -ExpandProperty LanguageName

        if ($null -eq $languageKey) {
            Write-Warning "The language '$language' cannot be validated; will tentatively continue with environment creation."
            return $language
        }
    }
    end {
        return $languageKey
    }

}
function Get-CurrencyKey {
    param (
        [parameter(Mandatory = $true)][string]$Region,
        [parameter(Mandatory = $true)][string][ValidateNotNullOrEmpty()] $taskJsonFile
    )
    begin {
        $currency = Get-VstsInputWithDefault -Name "CurrencyName" -taskJsonFile $taskJsonFile
    }
    process {
        $currencyKey = Get-AdminPowerAppCdsDatabaseCurrencies -LocationName $Region | `
                Where-Object { $_.CurrencyCode -eq $currency -or $_.CurrencyName -eq $currency } | `
                Select-Object -ExpandProperty CurrencyCode

        if ($null -eq $currencyKey) {
            Write-Warning "The currency '$currency' cannot be validated; will tentatively continue with environment creation."
            return $currency
        }
    }
    end {
        return $currencyKey
    }
}

function Get-TemplateKeys {
    param (
        [parameter(Mandatory = $true)][string]$Region,
        [parameter(Mandatory = $true)][string][ValidateNotNullOrEmpty()] $taskJsonFile
    )
    begin{
        $appTemplates = Get-VstsInputWithDefault -Name "AppsTemplate" -taskJsonFile $taskJsonFile
    }
    process{

        if ([String]::IsNullOrWhiteSpace($appTemplates)) {
            return
        }

        $tasksTemplates = $appTemplates.Split(",",[System.StringSplitOptions]::RemoveEmptyEntries).Trim()
        # Bug 1993787: Get-AdminPowerAppCdsDatabaseTemplates cmdlet returns less apps as compare PPAC
        $cdsTemplates = Get-AdminPowerAppCdsDatabaseTemplates -LocationName $Region | `
                    Where-Object IsDisabled -EQ $false | `
                    Select-Object TemplateName,TemplateDisplayName

        $templatesKeys = $cdsTemplates| `
                Where-Object {$tasksTemplates -contains $_.TemplateName -or $tasksTemplates -contains $_.TemplateDisplayName } | `
                Select-Object -ExpandProperty TemplateName

        if ($null -eq $templatesKeys -or $templatesKeys.Count -eq 0) {
            Write-Warning "The app(s) '$appTemplates' cannot be validated or authenticated user does not have the required Dynamics 365 licenses to create databases with Dynamics apps. Task will tentatively continue with environment creation."
            return $appTemplates
        }
    }
    end {
        return $templatesKeys
   }
}

function Write-OrganizationLog {
    [CmdletBinding()]
    param (
        [parameter (Mandatory = $true)][Hashtable]$OrgInfo
    )
    begin {
        $decorator = Get-Decorator
        $prefix = Get-LogPrefix
    }
    process {
        Write-Information -MessageData $decorator
        Write-Information -MessageData  "Url and Auth details"
        Write-Information -MessageData $decorator
        Write-Information -MessageData "$prefix Organization Id : $($OrgInfo.OrganizationId)"
        Write-Information -MessageData "$prefix Environment Id  : $($OrgInfo.EnvironmentId)"
        Write-Information -MessageData "$prefix Friendly Name   : $($OrgInfo.FriendlyName)"
        Write-Information -MessageData "$prefix Version         : $($OrgInfo.Version)"
    }
    end{}
}

function Get-EnvironmentInfoFromResponse {
    [CmdletBinding()]
    param (
        [parameter(Mandatory = $true)] $Response
    )
    begin {}
    Process {
        if ($Response.PSObject.Properties['Code'] -and $Response.Code -ge 400) {
            Write-Error "environment is not created. error: $($Response)"
        }
        elseif ($Response.PSObject.Properties['EnvironmentName']) {
            $orgInfo = @{
                EnvironmentUrl = $Response.Internal.Properties.LinkedEnvironmentMetadata.instanceUrl
                FriendlyName = $Response.Internal.Properties.LinkedEnvironmentMetadata.friendlyName
                EnvironmentId = $Response.EnvironmentName
                OrganizationId = $Response.Internal.Properties.LinkedEnvironmentMetadata.resourceId
                version = $Response.Internal.Properties.LinkedEnvironmentMetadata.version
                UniqueName = $Response.Internal.Properties.linkedEnvironmentMetadata.uniqueName
            }
            if ([string]::IsNullOrWhiteSpace($orgInfo.EnvironmentUrl)) {
                Write-Error "environment url is not found in the linked environment meta data: $($Response.Internal.properties)"
            }
        }
        else {
            Write-Error "unhandled response: $Response"
        }
    }

    end{
        return $orgInfo
    }
}
function New-PowerAppEnvironment {
    [CmdletBinding()]
    param (
        [parameter (Mandatory = $true)][string]$LocationName,
        [parameter (Mandatory = $true)][string]$EnvironmentSku,
        [parameter (Mandatory = $true)][string]$DisplayName,
        [parameter (Mandatory = $false)][switch]$ProvisionDatabase,
        [parameter (Mandatory = $false)][string]$CurrencyName,
        [parameter (Mandatory = $false)][string]$LanguageName,
        [parameter (Mandatory = $false)][string[]]$Templates,
        [parameter (Mandatory = $false)][string]$SecurityGroupId,
        [parameter (Mandatory = $false)][string]$DomainName,
        [parameter (Mandatory = $false)][boolean]$WaitUntilFinished
    )

    begin {
        #Setup parameter hash table
        $Parameters = . Get-ParameterValue
    }

    process {
        $response = New-AdminPowerAppEnvironment -Verbose @Parameters
        $orgInfo = Get-EnvironmentInfoFromResponse -Response $response
        Set-EnvironmentInfo -EnvironmentUrl $orgInfo.EnvironmentUrl `
                            -EnvironmentId $orgInfo.EnvironmentId `
                            -OrganizationId $orgInfo.OrganizationId `
                            -OrgUniqueName $OrgInfo.UniqueName
        Write-Host $response
    }

    end {
        Remove-Module Get-ParameterValue
        return $orgInfo
    }
}

Trace-VstsEnteringInvocation $MyInvocation
try {
    # Load shared functions and other dependencies
    ("..\ps_modules\SharedFunctions.psm1", "..\ps_modules\Get-ParameterValue.ps1") `
        | %{ Join-Path -Path $PSScriptRoot $_ } | Import-Module
    $redirector = Get-BindingRedirector
    Import-PowerPlatformToolsPowerShellModule -ModuleName "Microsoft.PowerApps.Administration.PowerShell"

    # Get input parameters and credentials
    $authInfo = Get-AuthInfoFromActiveServiceConnection

    $taskJson = Join-Path -Path $PSScriptRoot "task.json"
    $locationName = Get-VstsInputWithDefault -Name "LocationName" -taskJsonFile $taskJson
    $environmentSku = Get-VstsInputWithDefault -Name "EnvironmentSku" -taskJsonFile $taskJson
    $displayName = Get-VstsInputWithDefault -Name "DisplayName" -taskJsonFile $taskJson
    $domainName = Get-VstsInputWithDefault -Name "DomainName" -taskJsonFile $taskJson

    #Establish the connection
    Write-AuthLog -AuthInfo $authInfo
    if ($locationName -eq 'tip1') {
        Add-BapAdminConnection $authInfo -endpoint $locationName
        $locationName = 'unitedstates'
    }
    else {
        Add-BapAdminConnection $authInfo
        $locationName = Get-RegionKey -Region $locationName
    }

    $currencyName = Get-CurrencyKey -Region $locationName -taskJsonFile $taskJson
    $languageName = Get-LanguageKey -Region $locationName -taskJsonFile $taskJson

    if ($environmentSku -eq "Production" -or $environmentSku -eq "Sandbox") {
        $templates =  Get-TemplateKeys -Region $locationName -taskJsonFile $taskJson
    }

    $orgInfo = New-PowerAppEnvironment -DisplayName $displayName -LocationName $locationName -EnvironmentSku $environmentSku `
                            -CurrencyName $currencyName -LanguageName $languageName -ProvisionDatabase:$true `
                            -DomainName $domainName -Templates $templates
    Write-OrganizationLog -OrgInfo $orgInfo

} finally {
    if ($null -ne $redirector) {
        $redirector.Dispose()
    }
    Trace-VstsLeavingInvocation $MyInvocation
}

# SIG # Begin signature block
# MIInnwYJKoZIhvcNAQcCoIInkDCCJ4wCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCAH+M0Cp7mza8cr
# bpNw81dSIEXn7OOPK+p5291ESrCbRaCCDYEwggX/MIID56ADAgECAhMzAAACUosz
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
# BgEEAYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAvBgkqhkiG9w0BCQQxIgQgHNL34aBQ
# fpk/6aSlJ1lBWOr1V8nZGjOBPnLCF/uQXIQwNAYKKwYBBAGCNwIBDDEmMCSgEoAQ
# AFQAZQBzAHQAUwBpAGcAbqEOgAxodHRwOi8vdGVzdCAwDQYJKoZIhvcNAQEBBQAE
# ggEAcSOvcub55mfmxwK8HI0iMY0WXrEhL15p0FRKt7cQ9q6dgvg2FWrJLh5SRd2s
# I8t7tlSAfTjQ8waLvKZp8jaIjeSnDI5QFXL1wZyYWLO5nQOgnYf30Yr5Jh+/z/hL
# zKKRQUAa6m7XWGtFe7xXFdwHZwqOdUUzLmlfh558tAsERIw8nGoXJZ7m9Jdgpnre
# x5ui2QSynD8dzyhED7CEMyUMDQ1Yz/oPjR/Icuv1pmXV9oGYJ9eX5WRQltZGFKpZ
# Ra4eld6mqSDaD1DqsKAFxoQhxK6toh8vwqNhaaUQLM0NXL7B6Vq74o/egYkl5fuB
# nlvOVZoE95VH24LI8DrmjkAc+aGCFwwwghcIBgorBgEEAYI3AwMBMYIW+DCCFvQG
# CSqGSIb3DQEHAqCCFuUwghbhAgEDMQ8wDQYJYIZIAWUDBAIBBQAwggFVBgsqhkiG
# 9w0BCRABBKCCAUQEggFAMIIBPAIBAQYKKwYBBAGEWQoDATAxMA0GCWCGSAFlAwQC
# AQUABCDZQuuDSk7yf5alCqtnDPfQlos9BEia/C4j66/O8BeWUwIGYrG43MdSGBMy
# MDIyMDcwNzIxNDIyMy41NjlaMASAAgH0oIHUpIHRMIHOMQswCQYDVQQGEwJVUzET
# MBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMV
# TWljcm9zb2Z0IENvcnBvcmF0aW9uMSkwJwYDVQQLEyBNaWNyb3NvZnQgT3BlcmF0
# aW9ucyBQdWVydG8gUmljbzEmMCQGA1UECxMdVGhhbGVzIFRTUyBFU046MEE1Ni1F
# MzI5LTRENEQxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2Wg
# ghFfMIIHEDCCBPigAwIBAgITMwAAAac1uy7CZIVQKQABAAABpzANBgkqhkiG9w0B
# AQsFADB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UE
# BxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYD
# VQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDAeFw0yMjAzMDIxODUx
# MjJaFw0yMzA1MTExODUxMjJaMIHOMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2Fz
# aGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENv
# cnBvcmF0aW9uMSkwJwYDVQQLEyBNaWNyb3NvZnQgT3BlcmF0aW9ucyBQdWVydG8g
# UmljbzEmMCQGA1UECxMdVGhhbGVzIFRTUyBFU046MEE1Ni1FMzI5LTRENEQxJTAj
# BgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2UwggIiMA0GCSqGSIb3
# DQEBAQUAA4ICDwAwggIKAoICAQDtIzjGHVAF3nAlpuVek0aEGeIbDy3tFaegsMRY
# kwOZfOu3wGw8sZys3XwbH/9FyVV8yJHL8whEl6JJbzAwQ2ve0hL/grixCKKDGxQR
# 9VnmIJi1TvU22y0rSYpTSE5kEEOBQeaszBLA36ZmmWTFloHTo6EkHnfVK445nLlr
# ErJJ7YmlA/1UHUHCzJ6XlBnOwkLAGKPR3CDG9R/A03Ge8gHt2jmH++uj9jk+ed/+
# IXZyfSm6fxXw3lAFWLhHNcGZZmz3UWv7gseIil6bfNP+cKABkg5fL0jRcYuLplyg
# pMFh5vBng2d7TiszCHCGP+uBbaXaqTcG6hmtxpCU6BBT0eg+lydFsqnm2bzmYzEB
# HiwiSK0pxeC25JH5F+A+LHIys/dpSPS0bq4TD0wREOqcN4hrBD2Pia3MfwyZskFq
# m6TdxbJFrvcYYM2KGLEborAm+RSDEoYmpZcxM7pucSxOFOX7sRG8JNLmPWVQzVXx
# IYIkHnXEgHdxlr1TN+oLWMukCX4sQ+5bcI0pubFWtb6AX9lmYAgt6+ERO1Z6L5am
# wnd5x8l7+fvFBky6u6kXUUEGgUF3pE/VI1Lm3DUvGWHmcCvHdnrQ/fJkiODKl3DM
# kkSlCfTmVUDVsyNy8kufgoyLLAR3b9fWjOgo10LmZJJpWTrTKpC0YNbZoYCOtchQ
# vo8QdwIDAQABo4IBNjCCATIwHQYDVR0OBBYEFB9suH8FmC4whW/hDkID8/T6WkWD
# MB8GA1UdIwQYMBaAFJ+nFV0AXmJdg/Tl0mWnG1M1GelyMF8GA1UdHwRYMFYwVKBS
# oFCGTmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY3JsL01pY3Jvc29m
# dCUyMFRpbWUtU3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNybDBsBggrBgEFBQcBAQRg
# MF4wXAYIKwYBBQUHMAKGUGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMv
# Y2VydHMvTWljcm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBDQSUyMDIwMTAoMSkuY3J0
# MAwGA1UdEwEB/wQCMAAwEwYDVR0lBAwwCgYIKwYBBQUHAwgwDQYJKoZIhvcNAQEL
# BQADggIBAE8S+jHz2ToUfdQx0oZc2pewfLzglL85b21YWtFM4WX7yHGQP2091012
# 0Dy5yA1pUXY0F+zxpDkYV/5qY2QguSe3w90yTJ/WUEPDF5ydLMd/0CSJTYD1WjqZ
# PWJNWBKsiLTsjx69zpt7/6vYeX+ag5NCDFdrWqLM3tCRpTNzOc+2xpA5cvk34R/Z
# SNNw/xcy4481vBLb3Kpph+vEB3U7JfODVhpHdnVJVRdmgVjFKa2/B/RIT1EHAXKX
# 9dSAI/n9OMgd53EC4fj/j0ktpMTSy3kYPQlm5rLoKZWD9Q+cFvmh9pncgZT12TCG
# hESRb2VGcg/EXyfALBN7lNyUneNPEAQ2lw1H/eCot8BF07ZfCUCLRnN4sUWFjSII
# a2iOId3f/tuujgendFDNogV0qsM/LXY/sUkk+hu2WKsWrRM7fNOk9QQR3vbWf5q9
# kudlIyYAFUAYAkIooosTTtu4OUMuAg0veL0+J3wtpV8C5YawHDapwCSpkaivHoSO
# dE0yGRjjYXYRnDOcVFXh5nkcvRurn1Ogejm9K1ui12Nqky174Lff8f1xIdQq57ln
# gVmvRN9OwG3j2gaKbvPlp1418ujdNY/wFQatU8ip0F9Z0jI1PYGdxGhvKEv8zTOf
# RyvyIZwM1nlXHQWK6v4bLvSTLwaRfmREGNmVqWxCZuxC5fwrkSDwMIIHcTCCBVmg
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
# bGVzIFRTUyBFU046MEE1Ni1FMzI5LTRENEQxJTAjBgNVBAMTHE1pY3Jvc29mdCBU
# aW1lLVN0YW1wIFNlcnZpY2WiIwoBATAHBgUrDgMCGgMVAMB+7x4pkgM3gyzdKs1j
# W9qdr0R/oIGDMIGApH4wfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0
# b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3Jh
# dGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAwDQYJ
# KoZIhvcNAQEFBQACBQDmcU7lMCIYDzIwMjIwNzA3MTYyNDA1WhgPMjAyMjA3MDgx
# NjI0MDVaMHcwPQYKKwYBBAGEWQoEATEvMC0wCgIFAOZxTuUCAQAwCgIBAAICHHsC
# Af8wBwIBAAICEW8wCgIFAOZyoGUCAQAwNgYKKwYBBAGEWQoEAjEoMCYwDAYKKwYB
# BAGEWQoDAqAKMAgCAQACAwehIKEKMAgCAQACAwGGoDANBgkqhkiG9w0BAQUFAAOB
# gQA4kfkmY/H6eNFhjXcpTq2l9L0Cj1YkCrX7qbxxRFjfs05l3lEAzfWH5reyTqIO
# YseDCg894x45aBr0kWHncKVKdJHkciX2TSogsVxJ6dmhHZl6RD18cOq+BNAmOuVT
# PFPqbSr8+iKv6x+wrG4ESl50zaXLd/qgpUsTfa3b4YJqVzGCBA0wggQJAgEBMIGT
# MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdS
# ZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMT
# HU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwAhMzAAABpzW7LsJkhVApAAEA
# AAGnMA0GCWCGSAFlAwQCAQUAoIIBSjAaBgkqhkiG9w0BCQMxDQYLKoZIhvcNAQkQ
# AQQwLwYJKoZIhvcNAQkEMSIEIMozIUOJqBL5l/0ofxnjpq4rNboiXhOx7w0XiXkg
# yY96MIH6BgsqhkiG9w0BCRACLzGB6jCB5zCB5DCBvQQgR/B/5wmVAuC9GKm897B9
# 8OZM4cCeEagpF1ysTT7ajhswgZgwgYCkfjB8MQswCQYDVQQGEwJVUzETMBEGA1UE
# CBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9z
# b2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQ
# Q0EgMjAxMAITMwAAAac1uy7CZIVQKQABAAABpzAiBCBLYs4Mxw0x1QobngL5MBEn
# rJLRJS6uO/rwCR96UeW+HzANBgkqhkiG9w0BAQsFAASCAgB5ZLH6lIW9tcB5CHRc
# ZIuBktHgoeEfrUR+jRS1yOjHj7X6NpLkPoAB0UW4RUPt6KyQZ128dMoKSE/Mv7Gp
# YJ9L2Ge7OvBoGHR3jpgfA4KTE6n2VPcl/ezTKppoWvn0zRe8O9GSuptEiOZlQHYe
# 5NvPP5Q84jTLGODIY9OOkyKavsVWdg7MVbCqtneuja5DRPtWK18ipCzVuJRd3oNq
# pvDEqGp5FKVh+wtIQ8hYrHa1Fz11y0O2hV5pefM3Nuc6HTgRJxl/bNAMDTvbTBGv
# lSHOtjx+wG8lUZ4ff4KvkCfFamY1hQM/psUOgXVz91Bxaw+hCR0JeFhNjQphf7px
# UA0ldEAJ8wRjjZXarbbWiQoTAJrxPlNuk2CJGufBT/rD8NCc8TojOzAMnYlZves0
# NI/XCRiSYBTkm+Ce97hZGPupdr9zPBUxMPHuWV1REZRPILpDMCPfilqIC9bf6P6H
# rwYjyiLRYeX7MujJ1MfTuN73MzvyrsupKZtp/CLOpGpdE5WAqETXv80OW6wxEkbR
# J7P5Bk2QmGPjfvA4IDYd/A5pxsb1CKFXZGXGBjILLnz6BSxOUhu5YmeJFHPL8i1Q
# 5WrINB2IrgUd4ZYDmiNWKpD84EuExyXt6UZ/c3WHLTqqxf0GWy8d5bgen0AYgalK
# Qp5d4/b1H95+sUDsqOeeEM2KoA==
# SIG # End signature block
