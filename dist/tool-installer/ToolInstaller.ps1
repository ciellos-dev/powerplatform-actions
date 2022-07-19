# Copyright (c) Microsoft Corporation. All rights reserved.

[CmdletBinding()]
param()


function Install-PowerShellModule {
    [CmdletBinding()]
    param(
        [string][ValidateNotNullOrEmpty()]$RootPath,
        [string][ValidateNotNullOrEmpty()]$ModuleName,
        [string][ValidateNotNullOrEmpty()]$ModuleVersion,
        [string][ValidateNotNullOrEmpty()]$SubPath
    )

    Write-Host "Installing PS module $ModuleName - $ModuleVersion ..."
    $savedModulePath = [IO.Path]::Combine($RootPath, $ModuleName, $ModuleVersion)
    # MAX_PATH limitation could be lifted by prefixing with: '\\?\', but is not compatible with PowerShell
    # see: https://docs.microsoft.com/en-us/windows/win32/fileio/naming-a-file#paths
    # using minified path parts where possible
    $fixedModulePath = [IO.Path]::Combine($RootPath, $SubPath, $ModuleVersion, $ModuleName)

    if (!(Test-Path -Path $fixedModulePath)) {
        Save-Module -Name $ModuleName -Path $RootPath -RequiredVersion $ModuleVersion -Force

        Write-Verbose "Moving module into $fixedModulePath ..."
        $moduleItems = Get-ChildItem -Path $savedModulePath
        New-Item $fixedModulePath -ItemType Directory -Force | Out-Null
        $moduleItems | Move-Item -Destination $fixedModulePath -Force
        Remove-Item -Path ([IO.Path]::GetDirectoryName($($savedModulePath))) -Recurse -Force | Out-Null
    } else {
        Write-Verbose "Found module already installed, nothing to do."
    }

    Set-VstsTaskVariable PowerPlatformTools_$($ModuleName.Replace('.','_')) ([IO.Path]::GetDirectoryName($($fixedModulePath)))
}


function Set-NugetSource {
    [CmdletBinding()]
    param(
        [string][ValidateNotNullOrEmpty()]$NugetConfigFile,
        [string][ValidateNotNullOrEmpty()]$NugetSourceName
    )

    # Hard-code the nuget.config source entries used for PP.BT to only use public nuget.org:
    # Avoid using Register-PackageSource as it can inadvertently configure a nuget.org V3 API,
    # which PowerShell Desktop does not support (it will fail with an XML exception as it can't handle V3's JSON response)
    $nugetV2 ="https://www.nuget.org/api/v2"
    $nugetSource =
@"
<configuration>
  <packageSources>
    <clear />
    <add key="nuget.org" value="$nugetV2" validated="True" />
  </packageSources>
</configuration>
"@
    Set-Content -Path $NugetConfigFile -Value $nugetSource
    if ((Get-PackageSource -Name $NugetSourceName -ErrorAction SilentlyContinue) -eq $null) {
        Register-PackageSource -Name $NugetSourceName -Location $nugetV2 -ProviderName NuGet -Force
        Set-PackageSource -Name $NugetSourceName -Location $nugetV2 -ProviderName NuGet -Force
    }
}

function Install-NuGetPackage {
    [CmdletBinding()]
    param(
        [string][ValidateNotNullOrEmpty()]$RootPath,
        [string][ValidateNotNullOrEmpty()]$PackageName,
        [string][ValidateNotNullOrEmpty()]$PackageVersion,
        [string][ValidateNotNullOrEmpty()]$NugetConfigFile,
        [string][ValidateNotNullOrEmpty()]$NugetSourceName
    )

    Write-Host "Installing nuget pkg $PackageName - $PackageVersion ..."
    $savedPackagePath = Join-Path $RootPath "$PackageName.$PackageVersion"
    if (!(Test-Path -Path $savedPackagePath)) {
        Write-Host "Installing nuget pkg $PackageName - $PackageVersion ..."
        Install-Package $PackageName -RequiredVersion $PackageVersion -Destination $RootPath -ConfigFile $NugetConfigFile -Source $NugetSourceName -Force
    } else {
        Write-Verbose "Found package already installed, nothing to do."
    }

    Set-VstsTaskVariable PowerPlatformTools_$($PackageName.Replace('.','_')) $savedPackagePath
}

function Declare-EmbeddedModule {
    [CmdletBinding()]
    param(
        [string] $ModuleName
    )

    begin {
        $embeddedModulePath = Join-Path $PSScriptRoot "ps_modules"
    }

    process {
        if (Test-Path (Join-Path $embeddedModulePath $ModuleName)) {
            Set-VstsTaskVariable PowerPlatformTools_$($ModuleName.Replace('.','_')) $embeddedModulePath
        }
        else {
            Write-Error "Embedded module $ModuleName not found on path $embeddedModulePath"
        }
    }
}

function Ensure-PowershellDependencies {
    # base dependency for e.g. PowerShellGet
    Install-PackageProvider -Name "NuGet" -Force -ForceBootstrap -Scope CurrentUser -MinimumVersion 2.8.5.208

    # plain Win10 has older and less robust PackageManagment and PowerShellGet modules by default;
    # update the current user to modern versions that work more reliable with PSGallery and Nuget:
    $dependencies = @(
        @{ Name = "PackageManagement"; Version = [Version]"1.4.8.1" },
        @{ Name = "PowerShellGet"; Version = [Version]"2.2.5" }
    )
    $dependencies | ForEach-Object -Process {
        $moduleName = $_.Name
        $deps = (Get-Module -ListAvailable -Name $moduleName `
            | Sort-Object -Descending -Property Version)
        if ($deps -eq $null) {
            Write-Error "Required module $moduleName not installed!"
            return
        }
        $dep = $deps[0]
        if ($dep.Version -lt $_.Version) {
            Write-Verbose "Module $($moduleName): found $($dep.Version), required >= $($_.Version) - updating..."
            Install-Module -Name $dep.Name -MinimumVersion $_.Version -Scope CurrentUser -Force -AllowClobber
        }
        Import-Module $dep.Name -RequiredVersion $_.Version -Force
    }
}

try {
    ## You interface with the Actions/Workflow system by interacting
    ## with the environment.  The `GitHubActions` module makes this
    ## easier and more natural by wrapping up access to the Workflow
    ## environment in PowerShell-friendly constructions and idioms
    if (-not (Get-Module -ListAvailable GitHubActions)) {
        ## Make sure the GH Actions module is installed from the Gallery
        Install-Module GitHubActions -Force
    }

    ## Load up some common functionality for interacting
    ## with the GitHub Actions/Workflow environment
    Import-Module GitHubActions
    Write-Verbose "PS-Version: $($PSVersionTable.PSVersion) - $($PSVersionTable.PSEdition)"
    ("ps_modules\VstsTaskSdk", "SharedFunctions.psm1") `
        | %{ Join-Path -Path $PSScriptRoot $_ } | Import-Module

    $defaultVersion = Get-VSTSInput -Name "DefaultVersion" -AsBool
    $taskJson = Join-Path -Path $PSScriptRoot "task.json"
    $xrmOnlineManagementApiVersion = Get-VstsInputWithDefault -Name "XrmOnlineManagementApiVersion" -taskJsonFile $taskJson -DefaultValue:$defaultVersion
    if ($xrmOnlineManagementApiVersion -ne '(obsolete)') {
        Write-Warning "OBSOLETE: This version of the BuildTools no longer depends on the OnlineManagement module; any value will be ignored"
    }
    $powerAppsAdminVersion = Get-VstsInputWithDefault -Name "PowerAppsAdminVersion" -taskJsonFile $taskJson -DefaultValue:$defaultVersion -Require
    $xrmToolingPackageDeploymentVersion = Get-VstsInputWithDefault -Name "XrmToolingPackageDeploymentVersion" -taskJsonFile $taskJson -DefaultValue:$defaultVersion -Require
    $microsoftPowerAppsCheckerVersion = Get-VstsInputWithDefault -Name "MicrosoftPowerAppsCheckerVersion" -taskJsonFile $taskJson -DefaultValue:$defaultVersion -Require
    $crmSdkCoreToolsVersion = Get-VstsInputWithDefault -Name "CrmSdkCoreToolsVersion" -taskJsonFile $taskJson  -DefaultValue:$defaultVersion -Require

    $toolsSubFolder = "_t"
    if (Test-Path Env:VSTS_TOOLS_PATH) {
        $toolsPath = $Env:VSTS_TOOLS_PATH
    }
    elseif (Test-Path Env:PIPELINE_WORKSPACE) {
        $toolsPath = Join-Path $Env:PIPELINE_WORKSPACE $toolsSubFolder
    }
    elseif (Test-Path Env:AGENT_BUILDDIRECTORY ) {
        $toolsPath = Join-Path $Env:AGENT_BUILDDIRECTORY $toolsSubFolder
    }
    else {
        $toolsPath = Join-Path (Get-Location) $toolsSubFolder
    }

    $powerPlatformToolsPath = "$toolsPath\PA_BT"
    New-Item $powerPlatformToolsPath -ItemType Directory -Force | Out-Null
    Write-Verbose "tools folder: $powerPlatformToolsPath"

    Ensure-PowershellDependencies
    Install-PowerShellModule -RootPath $powerPlatformToolsPath -ModuleName "Microsoft.PowerApps.Administration.PowerShell" -ModuleVersion $powerAppsAdminVersion -SubPath "pa"
    Install-PowerShellModule -RootPath $powerPlatformToolsPath -ModuleName "Microsoft.Xrm.Tooling.PackageDeployment.Powershell" -ModuleVersion $xrmToolingPackageDeploymentVersion -SubPath "pd"
    Install-PowerShellModule -RootPath $powerPlatformToolsPath -ModuleName "Microsoft.PowerApps.Checker.PowerShell" -ModuleVersion $microsoftPowerAppsCheckerVersion -SubPath "ck"

    Declare-EmbeddedModule "Microsoft.Xrm.WebApi.PowerShell"
    Declare-EmbeddedModule "Microsoft.Xrm.InProcBindingRedirect.PS"

    $nugetConfigFile = Join-Path -Path $powerPlatformToolsPath "nuget.config"
    Write-Verbose "Setting nuget package source in $nugetConfigFile"
    # PS 5.1 (Windows Desktop) uses a relatively old PowerShellGet that only supports nuget v2 API
    # PS Core has v3 support; there's a PowerShellGet v3 in the works but not prod ready: https://github.com/PowerShell/PowerShellGet
    $nugetSourceName = "PP.BT.nuget.org"
    Set-NugetSource -NugetConfigFile $nugetConfigFile $nugetSourceName

    Install-NugetPackage -RootPath $powerPlatformToolsPath -PackageName "Microsoft.CrmSdk.CoreTools" -PackageVersion $crmSdkCoreToolsVersion -NugetConfigFile $nugetConfigFile -NugetSourceName $nugetSourceName

} finally {

}

# SIG # Begin signature block
# MIInngYJKoZIhvcNAQcCoIInjzCCJ4sCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCCGiI6l81y3i0EM
# XpVFGkcV1yIAhR2GPIbCoMBxUIkjGKCCDYEwggX/MIID56ADAgECAhMzAAACUosz
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
# RcBCyZt2WwqASGv9eZ/BvW1taslScxMNelDNMYIZczCCGW8CAQEwgZUwfjELMAkG
# A1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQx
# HjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEoMCYGA1UEAxMfTWljcm9z
# b2Z0IENvZGUgU2lnbmluZyBQQ0EgMjAxMQITMwAAAlKLM6r4lfM52wAAAAACUjAN
# BglghkgBZQMEAgEFAKCBoDAZBgkqhkiG9w0BCQMxDAYKKwYBBAGCNwIBBDAcBgor
# BgEEAYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAvBgkqhkiG9w0BCQQxIgQg01kOxBg9
# MCSZt5p4e0zGqvlGvIFnLaPdIXwesit+hLowNAYKKwYBBAGCNwIBDDEmMCSgEoAQ
# AFQAZQBzAHQAUwBpAGcAbqEOgAxodHRwOi8vdGVzdCAwDQYJKoZIhvcNAQEBBQAE
# ggEA0JmzqTWogETJy5MRdoTJkwszBkoc7tRp2I94y57HzXm3JcpSmOl5o5F8qTtJ
# qsXyWYzVQ+xRl88X4WP4daCUpoe9ye8rduZWn+mDQ/sSb/81+GgcdOz24b0VioaD
# q2SAclyky45dDCReIwZvGnudUDQ6gBnonSy3F+Wu6BslUMDnlKbKH3i+lqf9DE8x
# WWxvdmw7WUy9KP9oXnSHURdQ4z9/Zogrfu32b/X7d8nicEoCYcMwtXKoyQx10q1p
# QucpRrYylDR2t9NdlU7lHsWv1IxLp+7dTbfybbKKtylyIGLMQSnM1jtQgLwEbSDT
# Zl/3cXUr3A9sJniHeVRgLMsa+qGCFwswghcHBgorBgEEAYI3AwMBMYIW9zCCFvMG
# CSqGSIb3DQEHAqCCFuQwghbgAgEDMQ8wDQYJYIZIAWUDBAIBBQAwggFUBgsqhkiG
# 9w0BCRABBKCCAUMEggE/MIIBOwIBAQYKKwYBBAGEWQoDATAxMA0GCWCGSAFlAwQC
# AQUABCD65lSgqWaQNY+YbheqyQRohOUsnwZGuQezSStaeeHR1gIGYrGiRtdhGBIy
# MDIyMDcwNzIxNDIyMy42N1owBIACAfSggdSkgdEwgc4xCzAJBgNVBAYTAlVTMRMw
# EQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVN
# aWNyb3NvZnQgQ29ycG9yYXRpb24xKTAnBgNVBAsTIE1pY3Jvc29mdCBPcGVyYXRp
# b25zIFB1ZXJ0byBSaWNvMSYwJAYDVQQLEx1UaGFsZXMgVFNTIEVTTjo0NjJGLUUz
# MTktM0YyMDElMCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZaCC
# EV8wggcQMIIE+KADAgECAhMzAAABpAfP44+jum/WAAEAAAGkMA0GCSqGSIb3DQEB
# CwUAMHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQH
# EwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNV
# BAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwMB4XDTIyMDMwMjE4NTEx
# OFoXDTIzMDUxMTE4NTExOFowgc4xCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNo
# aW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29y
# cG9yYXRpb24xKTAnBgNVBAsTIE1pY3Jvc29mdCBPcGVyYXRpb25zIFB1ZXJ0byBS
# aWNvMSYwJAYDVQQLEx1UaGFsZXMgVFNTIEVTTjo0NjJGLUUzMTktM0YyMDElMCMG
# A1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZTCCAiIwDQYJKoZIhvcN
# AQEBBQADggIPADCCAgoCggIBAMBHjgD6FPy81PUhcOIVGh4bOSaq634Y+TjW2hNF
# 9BlnWxLJCEuMiV6YF5x6YTM7T1ZLM6NnH0whPypiz3bVZRmwgGyTURKfVyPJ89R3
# WaZ/HMvcAJZnCMgL+mOpxE94gwQJD/qo8UquOrCKCY/fcjchxV8yMkfIqP69HnWf
# W0ratk+I2GZF2ISFyRtvEuxJvacIFDFkQXj3H+Xy9IHzNqqi+g54iQjOAN6s3s68
# mi6rqv6+D9DPVPg1ev6worI3FlYzrPLCIunsbtYt3Xw3aHKMfA+SH8CV4iqJ/eEZ
# UP1uFJT50MAPNQlIwWERa6cccSVB5mN2YgHf8zDUqQU4k2/DWw+14iLkwrgNlfdZ
# 38V3xmxC9mZc9YnwFc32xi0czPzN15C8wiZEIqCddxbwimc+0LtPKandRXk2hMfw
# g0XpZaJxDfLTgvYjVU5PXTgB10mhWAA/YosgbB8KzvAxXPnrEnYg3XLWkgBZ+lOr
# HvqiszlFCGQC9rKPVFPCCsey356VhfcXlvwAJauAk7V0nLVTgwi/5ILyHffEuZYD
# nrx6a+snqDTHL/ZqRsB5HHq0XBo/i7BVuMXnSSXlFCo3On8IOl8JOKQ4CrIlri9q
# WJYMxsSICscotgODoYOO4lmXltKOB0l0IAhEXwSSKID5QAa9wTpIagea2hzjI6SU
# Y1W/AgMBAAGjggE2MIIBMjAdBgNVHQ4EFgQU4tATn6z4CBL2xZQd0jjN6SnjJMIw
# HwYDVR0jBBgwFoAUn6cVXQBeYl2D9OXSZacbUzUZ6XIwXwYDVR0fBFgwVjBUoFKg
# UIZOaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9jcmwvTWljcm9zb2Z0
# JTIwVGltZS1TdGFtcCUyMFBDQSUyMDIwMTAoMSkuY3JsMGwGCCsGAQUFBwEBBGAw
# XjBcBggrBgEFBQcwAoZQaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9j
# ZXJ0cy9NaWNyb3NvZnQlMjBUaW1lLVN0YW1wJTIwUENBJTIwMjAxMCgxKS5jcnQw
# DAYDVR0TAQH/BAIwADATBgNVHSUEDDAKBggrBgEFBQcDCDANBgkqhkiG9w0BAQsF
# AAOCAgEACVYcUNEMlyTuPDBGhiZ1U548ssF6J2g9QElWEb2cZ4dL0+5G8721/giR
# tTPvgxQhDF5rJCjHGj8nFSqOE8fnYz9vgb2YclYHvkoKWUJODxjhWS+S06ZLR/nD
# S85HeDAD0FGduAA80Q7vGzknKW2jxoNHTb74KQEMWiUK1M2PDN+eISPXPhPudGVG
# LbIEAk1Goj5VjzbQuLKhm2Tk4a22rkXkeE98gyNojHlBhHbb7nex3zGBTBGkVtwt
# 2ud7qN2rcpuJhsJ/vL/0XYLtyOk7eSQZdfye0TT1/qj18iSXHsIXDhHOuTKqBiia
# too4Unwk7uGyM0lv38Ztr+YpajSP+p0PEMRH9RdfrKRm4bHV5CmOTIzAmc49YZt4
# 0hhlVwlClFA4M+zn3cyLmEGwfNqD693hD5W3vcpnhf3xhZbVWTVpJH1CPGTmR4y5
# U9kxwysK8VlfCFRwYUa5640KsgIv1tJhF9LXemWIPEnuw9JnzHZ3iSw5dbTSXp9H
# mdOJIzsO+/tjQwZWBSFqnayaGv3Y8w1KYiQJS8cKJhwnhGgBPbyan+E5D9TyY9dK
# lZ3FikstwM4hKYGEUlg3tqaWEilWwa9SaNetNxjSfgah782qzbjTQhwDgc6Jf07F
# 2ak0YMnNJFHsBb1NPw77dhmo9ki8vrLOB++d6Gm2Z/jDpDOSst8wggdxMIIFWaAD
# AgECAhMzAAAAFcXna54Cm0mZAAAAAAAVMA0GCSqGSIb3DQEBCwUAMIGIMQswCQYD
# VQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEe
# MBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMTIwMAYDVQQDEylNaWNyb3Nv
# ZnQgUm9vdCBDZXJ0aWZpY2F0ZSBBdXRob3JpdHkgMjAxMDAeFw0yMTA5MzAxODIy
# MjVaFw0zMDA5MzAxODMyMjVaMHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNo
# aW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29y
# cG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEw
# MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEA5OGmTOe0ciELeaLL1yR5
# vQ7VgtP97pwHB9KpbE51yMo1V/YBf2xK4OK9uT4XYDP/XE/HZveVU3Fa4n5KWv64
# NmeFRiMMtY0Tz3cywBAY6GB9alKDRLemjkZrBxTzxXb1hlDcwUTIcVxRMTegCjhu
# je3XD9gmU3w5YQJ6xKr9cmmvHaus9ja+NSZk2pg7uhp7M62AW36MEBydUv626GIl
# 3GoPz130/o5Tz9bshVZN7928jaTjkY+yOSxRnOlwaQ3KNi1wjjHINSi947SHJMPg
# yY9+tVSP3PoFVZhtaDuaRr3tpK56KTesy+uDRedGbsoy1cCGMFxPLOJiss254o2I
# 5JasAUq7vnGpF1tnYN74kpEeHT39IM9zfUGaRnXNxF803RKJ1v2lIH1+/NmeRd+2
# ci/bfV+AutuqfjbsNkz2K26oElHovwUDo9Fzpk03dJQcNIIP8BDyt0cY7afomXw/
# TNuvXsLz1dhzPUNOwTM5TI4CvEJoLhDqhFFG4tG9ahhaYQFzymeiXtcodgLiMxhy
# 16cg8ML6EgrXY28MyTZki1ugpoMhXV8wdJGUlNi5UPkLiWHzNgY1GIRH29wb0f2y
# 1BzFa/ZcUlFdEtsluq9QBXpsxREdcu+N+VLEhReTwDwV2xo3xwgVGD94q0W29R6H
# XtqPnhZyacaue7e3PmriLq0CAwEAAaOCAd0wggHZMBIGCSsGAQQBgjcVAQQFAgMB
# AAEwIwYJKwYBBAGCNxUCBBYEFCqnUv5kxJq+gpE8RjUpzxD/LwTuMB0GA1UdDgQW
# BBSfpxVdAF5iXYP05dJlpxtTNRnpcjBcBgNVHSAEVTBTMFEGDCsGAQQBgjdMg30B
# ATBBMD8GCCsGAQUFBwIBFjNodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3Bz
# L0RvY3MvUmVwb3NpdG9yeS5odG0wEwYDVR0lBAwwCgYIKwYBBQUHAwgwGQYJKwYB
# BAGCNxQCBAweCgBTAHUAYgBDAEEwCwYDVR0PBAQDAgGGMA8GA1UdEwEB/wQFMAMB
# Af8wHwYDVR0jBBgwFoAU1fZWy4/oolxiaNE9lJBb186aGMQwVgYDVR0fBE8wTTBL
# oEmgR4ZFaHR0cDovL2NybC5taWNyb3NvZnQuY29tL3BraS9jcmwvcHJvZHVjdHMv
# TWljUm9vQ2VyQXV0XzIwMTAtMDYtMjMuY3JsMFoGCCsGAQUFBwEBBE4wTDBKBggr
# BgEFBQcwAoY+aHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraS9jZXJ0cy9NaWNS
# b29DZXJBdXRfMjAxMC0wNi0yMy5jcnQwDQYJKoZIhvcNAQELBQADggIBAJ1Vffwq
# reEsH2cBMSRb4Z5yS/ypb+pcFLY+TkdkeLEGk5c9MTO1OdfCcTY/2mRsfNB1OW27
# DzHkwo/7bNGhlBgi7ulmZzpTTd2YurYeeNg2LpypglYAA7AFvonoaeC6Ce5732pv
# vinLbtg/SHUB2RjebYIM9W0jVOR4U3UkV7ndn/OOPcbzaN9l9qRWqveVtihVJ9Ak
# vUCgvxm2EhIRXT0n4ECWOKz3+SmJw7wXsFSFQrP8DJ6LGYnn8AtqgcKBGUIZUnWK
# NsIdw2FzLixre24/LAl4FOmRsqlb30mjdAy87JGA0j3mSj5mO0+7hvoyGtmW9I/2
# kQH2zsZ0/fZMcm8Qq3UwxTSwethQ/gpY3UA8x1RtnWN0SCyxTkctwRQEcb9k+SS+
# c23Kjgm9swFXSVRk2XPXfx5bRAGOWhmRaw2fpCjcZxkoJLo4S5pu+yFUa2pFEUep
# 8beuyOiJXk+d0tBMdrVXVAmxaQFEfnyhYWxz/gq77EFmPWn9y8FBSX5+k77L+Dvk
# txW/tM4+pTFRhLy/AsGConsXHRWJjXD+57XQKBqJC4822rpM+Zv/Cuk0+CQ1Zyvg
# DbjmjJnW4SLq8CdCPSWU5nR0W2rRnj7tfqAxM328y+l7vzhwRNGQ8cirOoo6CGJ/
# 2XBjU02N7oJtpQUQwXEGahC0HVUzWLOhcGbyoYIC0jCCAjsCAQEwgfyhgdSkgdEw
# gc4xCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdS
# ZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKTAnBgNVBAsT
# IE1pY3Jvc29mdCBPcGVyYXRpb25zIFB1ZXJ0byBSaWNvMSYwJAYDVQQLEx1UaGFs
# ZXMgVFNTIEVTTjo0NjJGLUUzMTktM0YyMDElMCMGA1UEAxMcTWljcm9zb2Z0IFRp
# bWUtU3RhbXAgU2VydmljZaIjCgEBMAcGBSsOAwIaAxUANBwo4pNrfEL6DVo+tw96
# vGJvLp+ggYMwgYCkfjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3Rv
# bjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0
# aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDANBgkq
# hkiG9w0BAQUFAAIFAOZxOD8wIhgPMjAyMjA3MDcxNDQ3MjdaGA8yMDIyMDcwODE0
# NDcyN1owdzA9BgorBgEEAYRZCgQBMS8wLTAKAgUA5nE4PwIBADAKAgEAAgIIfAIB
# /zAHAgEAAgIRLDAKAgUA5nKJvwIBADA2BgorBgEEAYRZCgQCMSgwJjAMBgorBgEE
# AYRZCgMCoAowCAIBAAIDB6EgoQowCAIBAAIDAYagMA0GCSqGSIb3DQEBBQUAA4GB
# AEfMxz6RCMKds5wrAZILIK9KcgaaJnpkjiqWoWccqtU9SYWxjAWj5f7EbvYjjRff
# BTVVdBKyTMIerk7bSWUvNIzbcsBIWzannr2ulVA74QrGnLcy0jDGLDhYw2Tx/HVb
# OI2Uq08Fcj75j5fBGFuA+9kA8G6NJ8nW/DwV7gOXONR1MYIEDTCCBAkCAQEwgZMw
# fDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1Jl
# ZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMd
# TWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTACEzMAAAGkB8/jj6O6b9YAAQAA
# AaQwDQYJYIZIAWUDBAIBBQCgggFKMBoGCSqGSIb3DQEJAzENBgsqhkiG9w0BCRAB
# BDAvBgkqhkiG9w0BCQQxIgQg3F/FPXi4BycM6Kz4yNKLPHumLHV9ZoebUnziXZdM
# WecwgfoGCyqGSIb3DQEJEAIvMYHqMIHnMIHkMIG9BCAF/OCjISZwpMBJ8MJ3WwMC
# F3qOa5YHFG6J4uHjaup5+DCBmDCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQI
# EwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3Nv
# ZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBD
# QSAyMDEwAhMzAAABpAfP44+jum/WAAEAAAGkMCIEICyq+Xs4vuBFcZPesgV0YoL0
# dX4jvedKEeM1aDRMvlFXMA0GCSqGSIb3DQEBCwUABIICACcYqcgjUq5g8B/DfCTR
# u87O10nHDl53eYlYQKBPNoV7Ql7foWc/jpbs2ynLmJDbYibT768hM4001lZGNmxr
# o2s3dJSDhjXYrilcZtxoK7pyGlB0avHIbosvFfj70yeDfmcZ6dCEns9X8zMVuxno
# aBiBLhoeR/aGkKL3XgjHCgiQqjZOMaPj748/O9M6JWJXekEF07kCSpMgfIK52uE9
# u0aePc3alyDNHDVgSOw+WF8/bDWdrI64FtS8t6fSs70ZFZF9jMtoMdXCh2+8lxlt
# ZtOt+7oDSvQ/hE6AUX0eP5WFdlDF6afXq8puzj7bzoCCLKCWq7Vcpkb3hrpbUl4R
# OfqJxuLbes4DyNxaJBWFA5riTCQIZ2eE3gubtcG5q5YYZ88BMHdPW9o+VI2/jJIp
# UoA+cJZePTk6Qa0R2ze8h/NlGdaFWyQ0vTHnZzaFwFXgYfqbctMZBkXkn98bsmuW
# Z28decTim3fspB6KuwbKfDM95Aanv8jnIsDntAxzMLoMkZKA3w8GuALF3ROB7YyV
# ZDm1YmlB0jG/1R0yIE0JcQylp+x8TU7YHFEII7yf/eCcgFxSYlVmz0KKu5SJpteT
# qpq3vVkuGeg0hSYgM6IIRqlsyEyhodSISCPbxYHho4fkCO7/lE5w+D/RhHESMWy0
# BkCAfcYvakqpcBRzDPk1JFq6
# SIG # End signature block
