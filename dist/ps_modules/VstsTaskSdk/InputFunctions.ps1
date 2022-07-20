# Hash table of known variable info. The formatted env var name is the lookup key.
#
# The purpose of this hash table is to keep track of known variables. The hash table
# needs to be maintained for multiple reasons:
#  1) to distinguish between env vars and job vars
#  2) to distinguish between secret vars and public
#  3) to know the real variable name and not just the formatted env var name.
$script:knownVariables = @{ }
$script:vault = @{ }

<#
.SYNOPSIS
Gets an endpoint.

.DESCRIPTION
Gets an endpoint object for the specified endpoint name. The endpoint is returned as an object with three properties: Auth, Data, and Url.

The Data property requires a 1.97 agent or higher.

.PARAMETER Require
Writes an error to the error pipeline if the endpoint is not found.
#>
function Get-Endpoint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [switch]$Require)

    $originalErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Stop'

        # Get the URL.
        $description = Get-LocString -Key PSLIB_EndpointUrl0 -ArgumentList $Name
        $key = "ENDPOINT_URL_$Name"
        $url = Get-VaultValue -Description $description -Key $key -Require:$Require

        # Get the auth object.
        $description = Get-LocString -Key PSLIB_EndpointAuth0 -ArgumentList $Name
        $key = "ENDPOINT_AUTH_$Name"
        if ($auth = (Get-VaultValue -Description $description -Key $key -Require:$Require)) {
            $auth = ConvertFrom-Json -InputObject $auth
        }

        # Get the data.
        $description = "'$Name' service endpoint data"
        $key = "ENDPOINT_DATA_$Name"
        if ($data = (Get-VaultValue -Description $description -Key $key)) {
            $data = ConvertFrom-Json -InputObject $data
        }

        # Return the endpoint.
        if ($url -or $auth -or $data) {
            New-Object -TypeName psobject -Property @{
                Url = $url
                Auth = $auth
                Data = $data
            }
        }
    } catch {
        $ErrorActionPreference = $originalErrorActionPreference
        Write-Error $_
    }
}

<#
.SYNOPSIS
Gets a secure file ticket.

.DESCRIPTION
Gets the secure file ticket that can be used to download the secure file contents.

.PARAMETER Id
Secure file id.

.PARAMETER Require
Writes an error to the error pipeline if the ticket is not found.
#>
function Get-SecureFileTicket {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Id,
        [switch]$Require)

    $originalErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Stop'

        $description = Get-LocString -Key PSLIB_Input0 -ArgumentList $Id
        $key = "SECUREFILE_TICKET_$Id"
        
        Get-VaultValue -Description $description -Key $key -Require:$Require
    } catch {
        $ErrorActionPreference = $originalErrorActionPreference
        Write-Error $_
    }
}

<#
.SYNOPSIS
Gets a secure file name.

.DESCRIPTION
Gets the name for a secure file.

.PARAMETER Id
Secure file id.

.PARAMETER Require
Writes an error to the error pipeline if the ticket is not found.
#>
function Get-SecureFileName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Id,
        [switch]$Require)

    $originalErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Stop'

        $description = Get-LocString -Key PSLIB_Input0 -ArgumentList $Id
        $key = "SECUREFILE_NAME_$Id"
        
        Get-VaultValue -Description $description -Key $key -Require:$Require
    } catch {
        $ErrorActionPreference = $originalErrorActionPreference
        Write-Error $_
    }
}

<#
.SYNOPSIS
Gets an input.

.DESCRIPTION
Gets the value for the specified input name.

.PARAMETER AsBool
Returns the value as a bool. Returns true if the value converted to a string is "1" or "true" (case insensitive); otherwise false.

.PARAMETER AsInt
Returns the value as an int. Returns the value converted to an int. Returns 0 if the conversion fails.

.PARAMETER Default
Default value to use if the input is null or empty.

.PARAMETER Require
Writes an error to the error pipeline if the input is null or empty.
#>
function Get-Input {
    [CmdletBinding(DefaultParameterSetName = 'Require')]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(ParameterSetName = 'Default')]
        $Default,
        [Parameter(ParameterSetName = 'Require')]
        [switch]$Require,
        [switch]$AsBool,
        [switch]$AsInt)

    # Get the input from the vault. Splat the bound parameters hashtable. Splatting is required
    # in order to concisely invoke the correct parameter set.
    $null = $PSBoundParameters.Remove('Name')
    $description = Get-LocString -Key PSLIB_Input0 -ArgumentList $Name
    $key = "INPUT_$($Name.Replace(' ', '_').ToUpperInvariant())"
    Get-VaultValue @PSBoundParameters -Description $description -Key $key
}

<#
.SYNOPSIS
Gets a task variable.

.DESCRIPTION
Gets the value for the specified task variable.

.PARAMETER AsBool
Returns the value as a bool. Returns true if the value converted to a string is "1" or "true" (case insensitive); otherwise false.

.PARAMETER AsInt
Returns the value as an int. Returns the value converted to an int. Returns 0 if the conversion fails.

.PARAMETER Default
Default value to use if the input is null or empty.

.PARAMETER Require
Writes an error to the error pipeline if the input is null or empty.
#>
function Get-TaskVariable {
    [CmdletBinding(DefaultParameterSetName = 'Require')]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(ParameterSetName = 'Default')]
        $Default,
        [Parameter(ParameterSetName = 'Require')]
        [switch]$Require,
        [switch]$AsBool,
        [switch]$AsInt)

    $originalErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Stop'
        $description = Get-LocString -Key PSLIB_TaskVariable0 -ArgumentList $Name
        $variableKey = Get-VariableKey -Name $Name
        if ($script:knownVariables.$variableKey.Secret) {
            # Get secret variable. Splatting is required to concisely invoke the correct parameter set.
            $null = $PSBoundParameters.Remove('Name')
            $vaultKey = "SECRET_$variableKey"
            Get-VaultValue @PSBoundParameters -Description $description -Key $vaultKey
        } else {
            # Get public variable.
            $item = $null
            $path = "Env:$variableKey"
            if ((Test-Path -LiteralPath $path) -and ($item = Get-Item -LiteralPath $path).Value) {
                # Intentionally empty. Value was successfully retrieved.
            } elseif (!$script:nonInteractive) {
                # The value wasn't found and the module is running in interactive dev mode.
                # Prompt for the value.
                Set-Item -LiteralPath $path -Value (Read-Host -Prompt $description)
                if (Test-Path -LiteralPath $path) {
                    $item = Get-Item -LiteralPath $path
                }
            }

            # Get the converted value. Splatting is required to concisely invoke the correct parameter set.
            $null = $PSBoundParameters.Remove('Name')
            Get-Value @PSBoundParameters -Description $description -Key $variableKey -Value $item.Value
        }
    } catch {
        $ErrorActionPreference = $originalErrorActionPreference
        Write-Error $_
    }
}

<#
.SYNOPSIS
Gets all job variables available to the task. Requires 2.104.1 agent or higher.

.DESCRIPTION
Gets a snapshot of the current state of all job variables available to the task.
Requires a 2.104.1 agent or higher for full functionality.

Returns an array of objects with the following properties:
    [string]Name
    [string]Value
    [bool]Secret

Limitations on an agent prior to 2.104.1:
 1) The return value does not include all public variables. Only public variables
    that have been added using setVariable are returned.
 2) The name returned for each secret variable is the formatted environment variable
    name, not the actual variable name (unless it was set explicitly at runtime using
    setVariable).
#>
function Get-TaskVariableInfo {
    [CmdletBinding()]
    param()

    foreach ($info in $script:knownVariables.Values) {
        New-Object -TypeName psobject -Property @{
            Name = $info.Name
            Value = Get-TaskVariable -Name $info.Name
            Secret = $info.Secret
        }
    }
}

<#
.SYNOPSIS
Sets a task variable.

.DESCRIPTION
Sets a task variable in the current task context as well as in the current job context. This allows the task variable to retrieved by subsequent tasks within the same job.
#>
function Set-TaskVariable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [string]$Value,
        [switch]$Secret)

    # Once a secret always a secret.
    $variableKey = Get-VariableKey -Name $Name
    [bool]$Secret = $Secret -or $script:knownVariables.$variableKey.Secret
    if ($Secret) {
        $vaultKey = "SECRET_$variableKey"
        if (!$Value) {
            # Clear the secret.
            Write-Verbose "Set $Name = ''"
            $script:vault.Remove($vaultKey)
        } else {
            # Store the secret in the vault.
            Write-Verbose "Set $Name = '********'"
            $script:vault[$vaultKey] = New-Object System.Management.Automation.PSCredential(
                $vaultKey,
                (ConvertTo-SecureString -String $Value -AsPlainText -Force))
        }

        # Clear the environment variable.
        Set-Item -LiteralPath "Env:$variableKey" -Value ''
    } else {
        # Set the environment variable.
        Write-Verbose "Set $Name = '$Value'"
        Set-Item -LiteralPath "Env:$variableKey" -Value $Value
    }

    # Store the metadata.
    $script:knownVariables[$variableKey] = New-Object -TypeName psobject -Property @{
            Name = $name
            Secret = $Secret
        }

    # Persist the variable in the task context.
    Write-SetVariable -Name $Name -Value $Value -Secret:$Secret
}

########################################
# Private functions.
########################################
function Get-VaultValue {
    [CmdletBinding(DefaultParameterSetName = 'Require')]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Description,
        [Parameter(Mandatory = $true)]
        [string]$Key,
        [Parameter(ParameterSetName = 'Require')]
        [switch]$Require,
        [Parameter(ParameterSetName = 'Default')]
        [object]$Default,
        [switch]$AsBool,
        [switch]$AsInt)

    # Attempt to get the vault value.
    $value = $null
    if ($psCredential = $script:vault[$Key]) {
        $value = $psCredential.GetNetworkCredential().Password
    } elseif (!$script:nonInteractive) {
        # The value wasn't found. Prompt for the value if running in interactive dev mode.
        $value = Read-Host -Prompt $Description
        if ($value) {
            $script:vault[$Key] = New-Object System.Management.Automation.PSCredential(
                $Key,
                (ConvertTo-SecureString -String $value -AsPlainText -Force))
        }
    }

    Get-Value -Value $value @PSBoundParameters
}

function Get-Value {
    [CmdletBinding(DefaultParameterSetName = 'Require')]
    param(
        [string]$Value,
        [Parameter(Mandatory = $true)]
        [string]$Description,
        [Parameter(Mandatory = $true)]
        [string]$Key,
        [Parameter(ParameterSetName = 'Require')]
        [switch]$Require,
        [Parameter(ParameterSetName = 'Default')]
        [object]$Default,
        [switch]$AsBool,
        [switch]$AsInt)

    $result = $Value
    if ($result) {
        if ($Key -like 'ENDPOINT_AUTH_*') {
            Write-Verbose "$($Key): '********'"
        } else {
            Write-Verbose "$($Key): '$result'"
        }
    } else {
        Write-Verbose "$Key (empty)"

        # Write error if required.
        if ($Require) {
            Write-Error "$(Get-LocString -Key PSLIB_Required0 $Description)"
            return
        }

        # Fallback to the default if provided.
        if ($PSCmdlet.ParameterSetName -eq 'Default') {
            $result = $Default
            $OFS = ' '
            Write-Verbose " Defaulted to: '$result'"
        } else {
            $result = ''
        }
    }

    # Convert to bool if specified.
    if ($AsBool) {
        if ($result -isnot [bool]) {
            $result = "$result" -in '1', 'true'
            Write-Verbose " Converted to bool: $result"
        }

        return $result
    }

    # Convert to int if specified.
    if ($AsInt) {
        if ($result -isnot [int]) {
            try {
                $result = [int]"$result"
            } catch {
                $result = 0
            }

            Write-Verbose " Converted to int: $result"
        }

        return $result
    }

    return $result
}

function Initialize-Inputs {
    # Store endpoints, inputs, and secret variables in the vault.
    foreach ($variable in (Get-ChildItem -Path Env:ENDPOINT_?*, Env:INPUT_?*, Env:SECRET_?*, Env:SECUREFILE_?*)) {
        # Record the secret variable metadata. This is required by Get-TaskVariable to
        # retrieve the value. In a 2.104.1 agent or higher, this metadata will be overwritten
        # when $env:VSTS_SECRET_VARIABLES is processed.
        if ($variable.Name -like 'SECRET_?*') {
            $variableKey = $variable.Name.Substring('SECRET_'.Length)
            $script:knownVariables[$variableKey] = New-Object -TypeName psobject -Property @{
                # This is technically not the variable name (has underscores instead of dots),
                # but it's good enough to make Get-TaskVariable work in a pre-2.104.1 agent
                # where $env:VSTS_SECRET_VARIABLES is not defined.
                Name = $variableKey
                Secret = $true
            }
        }

        # Store the value in the vault.
        $vaultKey = $variable.Name
        if ($variable.Value) {
            $script:vault[$vaultKey] = New-Object System.Management.Automation.PSCredential(
                $vaultKey,
                (ConvertTo-SecureString -String $variable.Value -AsPlainText -Force))
        }

        # Clear the environment variable.
        Remove-Item -LiteralPath "Env:$($variable.Name)"
    }

    # Record the public variable names. Env var added in 2.104.1 agent.
    if ($env:VSTS_PUBLIC_VARIABLES) {
        foreach ($name in (ConvertFrom-Json -InputObject $env:VSTS_PUBLIC_VARIABLES)) {
            $variableKey = Get-VariableKey -Name $name
            $script:knownVariables[$variableKey] = New-Object -TypeName psobject -Property @{
                Name = $name
                Secret = $false
            }
        }

        $env:VSTS_PUBLIC_VARIABLES = ''
    }

    # Record the secret variable names. Env var added in 2.104.1 agent.
    if ($env:VSTS_SECRET_VARIABLES) {
        foreach ($name in (ConvertFrom-Json -InputObject $env:VSTS_SECRET_VARIABLES)) {
            $variableKey = Get-VariableKey -Name $name
            $script:knownVariables[$variableKey] = New-Object -TypeName psobject -Property @{
                Name = $name
                Secret = $true
            }
        }

        $env:VSTS_SECRET_VARIABLES = ''
    }
}

function Get-VariableKey {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name)

    if ($Name -ne 'agent.jobstatus') {
        $Name = $Name.Replace('.', '_')
    }

    $Name.ToUpperInvariant()
}

# SIG # Begin signature block
# MIInngYJKoZIhvcNAQcCoIInjzCCJ4sCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBbqQXYs0XjHxpR
# oVUQXMXqm82JS7ioyoz7KfWP6suubqCCDYEwggX/MIID56ADAgECAhMzAAACUosz
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
# BgEEAYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAvBgkqhkiG9w0BCQQxIgQgxrmbjNFE
# ZLXqkLGTXz2EkXrcvAw0vUe5RMwasP97Y5swNAYKKwYBBAGCNwIBDDEmMCSgEoAQ
# AFQAZQBzAHQAUwBpAGcAbqEOgAxodHRwOi8vdGVzdCAwDQYJKoZIhvcNAQEBBQAE
# ggEAMNKM2i6go6jCQBf+MmpJnRkOWH7BaBBTL3K89Bs0XyU4AOTD1hjzk9cWaD4C
# kbZr1e9UhFvkyi0zCeps8QCZDH41cMjliac7gETZQmz+sLad8Qlh8Fy73mWsr47p
# adyTbE+WvO8885B7ymmaKqlNzj6tuRDF/u0Cd1gLSWYolVH5+3N+n+v+hp4zoGBd
# 8FSs4Z01VgnStBfJRvK7DRtlm/+Ro1bNL3VY15y4GeDM3qcG5Hv2J90OxNZRFf+J
# jyAbbfFq00DX4EMrQUJeo2xyHuqSUOtJXd+Pb5RbhIpFHfuW0ZfEwuc8Y/r45dAE
# 7r0OSAaLkenyx/5xMaM5x24tDaGCFwswghcHBgorBgEEAYI3AwMBMYIW9zCCFvMG
# CSqGSIb3DQEHAqCCFuQwghbgAgEDMQ8wDQYJYIZIAWUDBAIBBQAwggFUBgsqhkiG
# 9w0BCRABBKCCAUMEggE/MIIBOwIBAQYKKwYBBAGEWQoDATAxMA0GCWCGSAFlAwQC
# AQUABCDqkjhgIiVb5Qo5/vEm19YphhJyS4wDvcygxc8A8u/1aQIGYrIitFZ8GBIy
# MDIyMDcwNzIxNDIyNi40NlowBIACAfSggdSkgdEwgc4xCzAJBgNVBAYTAlVTMRMw
# EQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVN
# aWNyb3NvZnQgQ29ycG9yYXRpb24xKTAnBgNVBAsTIE1pY3Jvc29mdCBPcGVyYXRp
# b25zIFB1ZXJ0byBSaWNvMSYwJAYDVQQLEx1UaGFsZXMgVFNTIEVTTjozMkJELUUz
# RDUtM0IxRDElMCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZaCC
# EV8wggcQMIIE+KADAgECAhMzAAABrfzfTVjjXTLpAAEAAAGtMA0GCSqGSIb3DQEB
# CwUAMHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQH
# EwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNV
# BAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwMB4XDTIyMDMwMjE4NTEz
# NloXDTIzMDUxMTE4NTEzNlowgc4xCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNo
# aW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29y
# cG9yYXRpb24xKTAnBgNVBAsTIE1pY3Jvc29mdCBPcGVyYXRpb25zIFB1ZXJ0byBS
# aWNvMSYwJAYDVQQLEx1UaGFsZXMgVFNTIEVTTjozMkJELUUzRDUtM0IxRDElMCMG
# A1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZTCCAiIwDQYJKoZIhvcN
# AQEBBQADggIPADCCAgoCggIBAOieUyqlTSrVLhvY7TO8vgC+T5N/y/MXeR3oNwE0
# rLI1Eg/gM5g9NhP+KqqJc/7uPL4TsoALb+RVf6roYNllyQrYmquUjwsq262MD5L9
# l9rU1plz2tMPehP8addVlNIjYIBh0NC4CyME6txVppQr7eFd/bW0X9tnZy1aDW+z
# oaJB2FY8haokq5cRONEW4uoVsTTXsICkbYOAYffIIGakMFXVvB30NcsuiDn6uDk8
# 3XXTs0tnSr8FxzPoD8SgPPIcWaWPEjCQLr5I0BxfdUliwNPHIPEglqosrClRjXG7
# rcZWbWeODgATi0i6DUsv1Wn0LOW4svK4/Wuc/v9dlmuIramv9whbgCykUuYZy8Mx
# TzsQqU2Rxcm8h89CXA5jf1k7k3ZiaLUJ003MjtTtNXzlgb+k1A5eL17G3C4Ejw5A
# oViM+UBGQvxuTxpFeaGoQFqeOGGtEK0qk0wdUX9p/4Au9Xsle5D5fvypBdscXBsl
# UBcT6+CYq0kQ9smsTyhV4DK9wb9Zn7ObEOfT0AQyppI6jwzBjHhAGFyrKYjIbglM
# aEixjRv7XdNic2VuYKyS71A0hs6dbbDx/V7hDbdv2srtZ2VTO0y2E+4QqMRKtABv
# 4AggjYKz5TYGuQ4VbbPY8fBO9Xqva3Gnx1ZDOQ3nGVFKHwarGDcNdB3qesvtJbIG
# JgJjAgMBAAGjggE2MIIBMjAdBgNVHQ4EFgQUfVB0HQS8qiFabmqEqOV9LrLGwVkw
# HwYDVR0jBBgwFoAUn6cVXQBeYl2D9OXSZacbUzUZ6XIwXwYDVR0fBFgwVjBUoFKg
# UIZOaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9jcmwvTWljcm9zb2Z0
# JTIwVGltZS1TdGFtcCUyMFBDQSUyMDIwMTAoMSkuY3JsMGwGCCsGAQUFBwEBBGAw
# XjBcBggrBgEFBQcwAoZQaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9j
# ZXJ0cy9NaWNyb3NvZnQlMjBUaW1lLVN0YW1wJTIwUENBJTIwMjAxMCgxKS5jcnQw
# DAYDVR0TAQH/BAIwADATBgNVHSUEDDAKBggrBgEFBQcDCDANBgkqhkiG9w0BAQsF
# AAOCAgEAi9AdRbsx/gOSdBXndwRejQuutQqce3k3bgs1slPjZSx6FDXp1IZzjOyT
# 1Jo/3eUWDBFJdi+Heu1NoyDdGn9vL6rxly1L68K4MnfLBm+ybyjN+xa1eNa4+4cO
# oOuxE2Kt8jtmZbIhx2jvY7F9qY/lanR5PSbUKyClhNQhxsnNUp/JSQ+o7nAuQJ+w
# sCwPCrXYE7C+TvKDja6e6WU0K4RiBXFGU1z6Mt3K9wlMD/QGU4+/IGZDmE+/Z/k0
# JfJjZyxCAlcmhe3rgdhDzAsGxJYq4PblGZTBdr8wkQwpP2jggyMMawMM5DggwvXa
# DbrqCQ8gksNhCZzTqfS2dbgLF0m7HfwlUMrcnzi/bdTSRWzIXg5QsH1t5XaaIH+T
# Z1uZBtwXJ8EOXr6S+2A6q8RQVY10KnBH6YpGE9OhXPfuIu882muFEdh4EXbPdARU
# R1IMSIxg88khSBC/YBwQhCpjTksq5J3Z+jyHWZ4MnXX5R42mAR584iRYc7agYvuo
# tDEqcD0U9lIjgW31PqfqZQ1tuYZTiGcKE9QcYGvZFKnVdkqK8V0M9e+kF5CqDOrM
# MYRV2+I/FhyQsJHxK/G53D0O5bvdIh2gDnEHRAFihdZj29Z7W0paGPotGX0oB5r9
# wqNjM3rbvuEe6FJ323MPY1x9/N1g126T/SokqADJBTKqyBYN4zMwggdxMIIFWaAD
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
# ZXMgVFNTIEVTTjozMkJELUUzRDUtM0IxRDElMCMGA1UEAxMcTWljcm9zb2Z0IFRp
# bWUtU3RhbXAgU2VydmljZaIjCgEBMAcGBSsOAwIaAxUAQJLRrUVR4ZbBDgWPjuNq
# VctUzpCggYMwgYCkfjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3Rv
# bjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0
# aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDANBgkq
# hkiG9w0BAQUFAAIFAOZxuJkwIhgPMjAyMjA3MDcyMzU1MDVaGA8yMDIyMDcwODIz
# NTUwNVowdzA9BgorBgEEAYRZCgQBMS8wLTAKAgUA5nG4mQIBADAKAgEAAgIi4wIB
# /zAHAgEAAgISZzAKAgUA5nMKGQIBADA2BgorBgEEAYRZCgQCMSgwJjAMBgorBgEE
# AYRZCgMCoAowCAIBAAIDB6EgoQowCAIBAAIDAYagMA0GCSqGSIb3DQEBBQUAA4GB
# ADFi++2aNb7AJzYkwZXsJ9JfYK58YEFeJnmqyIskT+Jp1Yqe3VWE6L/dAQF1Vhm6
# WWPltpthCMT8+u7GBrEzh6Tr8vlKzSc0RX+LEXkptSDXAp6wQnxwJYOd9hTKDtZx
# +WBgIuoa7Jnf369mbeFCqccCZcBMC2FcMeS7aPUwEoD3MYIEDTCCBAkCAQEwgZMw
# fDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1Jl
# ZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMd
# TWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTACEzMAAAGt/N9NWONdMukAAQAA
# Aa0wDQYJYIZIAWUDBAIBBQCgggFKMBoGCSqGSIb3DQEJAzENBgsqhkiG9w0BCRAB
# BDAvBgkqhkiG9w0BCQQxIgQgmZ0aTgk0LAq73FK/QeyydawFjJfoVZcvdijrFOCc
# dsgwgfoGCyqGSIb3DQEJEAIvMYHqMIHnMIHkMIG9BCCf6nw9CR5e1+Ottcn1w992
# Kmn8YMTY/DWPIHeMbMtQgjCBmDCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQI
# EwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3Nv
# ZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBD
# QSAyMDEwAhMzAAABrfzfTVjjXTLpAAEAAAGtMCIEINq0OAOgCnrT/WpAMUd04XcQ
# H5nCyfMzadT7BE7lt2JuMA0GCSqGSIb3DQEBCwUABIICAE322YF1z8bv4gQ/MDsO
# n23K/z101F+B1JQpCh7nh68/aSiLlOj5MfBbCw4PV6v87xQtkEnRnUZXGBcJ2trP
# 2JGXJavF8O116gNLTK3+0+t2gM0G/XeT4Vk3+yWOM9NvYaJVw1D2Uofv9y5pUKmF
# g8qJM5JwsFQu0jyBHk6/HFmECaQo1ePR5T2bknwf5dFvXwGXjGQkiUlucK/ZM796
# F+djx2H7Gs6YKbGcvXhvveczrhGB6mPMSlM/Dd3SkGnTlYV0AMpGZ+jdDK8AzcUG
# O808aRb5TQ439UkJez4wrEfP2Lb47UGFZ1FqbzOyEn8uW1B0388ZqQgLNJQd7VxK
# uAQYKpErQd+Oo1Iz2dhVQxWELfieqCCmaZaw/BTU/KCeH0P2Jv4VzNnvv6SCcMo0
# j7uM4hwhHNP2tb5bxGqQw5LQtclxwDMY/r5AzfkEhQHHA6qWgQy8GrxUwjd+Y/6S
# PblSU5CZz6fkoRR5M+cz+Lng4aIWLc3XF/ODFYXjireP91+3InN7OR0jXNe8sXDA
# S12bfL7zY4gfnALnC7r4iLI6P6W8u+k5lBzm/LfzAzdAZYUyVmuIPQvQt0piSLm4
# pBl0yBvJIiUh0SVbLfZ8hw7ZCdOWhsOfrBBmklzGkE0nTutuVH5ApYmJZT8bZSV2
# JkK/DyNz7IAh4WfZpxJlQ/93
# SIG # End signature block
