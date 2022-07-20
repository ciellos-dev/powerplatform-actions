$script:resourceStrings = @{ }

<#
.SYNOPSIS
Gets a localized resource string.

.DESCRIPTION
Gets a localized resource string and optionally formats the string with arguments.

If the format fails (due to a bad format string or incorrect expected arguments in the format string), then the format string is returned followed by each of the arguments (delimited by a space).

If the lookup key is not found, then the lookup key is returned followed by each of the arguments (delimited by a space).

.PARAMETER Require
Writes an error to the error pipeline if the endpoint is not found.
#>
function Get-LocString {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 1)]
        [string]$Key,
        [Parameter(Position = 2)]
        [object[]]$ArgumentList = @( ))

    # Due to the dynamically typed nature of PowerShell, a single null argument passed
    # to an array parameter is interpreted as a null array.
    if ([object]::ReferenceEquals($null, $ArgumentList)) {
        $ArgumentList = @( $null )
    }

    # Lookup the format string.
    $format = ''
    if (!($format = $script:resourceStrings[$Key])) {
        # Warn the key was not found. Prevent recursion if the lookup key is the
        # "string resource key not found" lookup key.
        $resourceNotFoundKey = 'PSLIB_StringResourceKeyNotFound0'
        if ($key -ne $resourceNotFoundKey) {
            Write-Warning (Get-LocString -Key $resourceNotFoundKey -ArgumentList $Key)
        }

        # Fallback to just the key itself if there aren't any arguments to format.
        if (!$ArgumentList.Count) { return $key }

        # Otherwise fallback to the key followed by the arguments.
        $OFS = " "
        return "$key $ArgumentList"
    }

    # Return the string if there aren't any arguments to format.
    if (!$ArgumentList.Count) { return $format }

    try {
        [string]::Format($format, $ArgumentList)
    } catch {
        Write-Warning (Get-LocString -Key 'PSLIB_StringFormatFailed')
        $OFS = " "
        "$format $ArgumentList"
    }
}

<#
.SYNOPSIS
Imports resource strings for use with Get-VstsLocString.

.DESCRIPTION
Imports resource strings for use with Get-VstsLocString. The imported strings are stored in an internal resource string dictionary. Optionally, if a separate resource file for the current culture exists, then the localized strings from that file then imported (overlaid) into the same internal resource string dictionary.

Resource strings from the SDK are prefixed with "PSLIB_". This prefix should be avoided for custom resource strings.

.Parameter LiteralPath
JSON file containing resource strings.

.EXAMPLE
Import-VstsLocStrings -LiteralPath $PSScriptRoot\Task.json

Imports strings from messages section in the JSON file. If a messages section is not defined, then no strings are imported. Example messages section:
{
    "messages": {
        "Hello": "Hello you!",
        "Hello0": "Hello {0}!"
    }
}

.EXAMPLE
Import-VstsLocStrings -LiteralPath $PSScriptRoot\Task.json

Overlays strings from an optional separate resource file for the current culture.

Given the task variable System.Culture is set to 'de-DE'. This variable is set by the agent based on the current culture for the job.
Given the file Task.json contains:
{
    "messages": {
        "GoodDay": "Good day!",
    }
}
Given the file resources.resjson\de-DE\resources.resjson:
{
    "loc.messages.GoodDay": "Guten Tag!"
}

The net result from the import command would be one new key-value pair added to the internal dictionary: Key = 'GoodDay', Value = 'Guten Tag!'
#>
function Import-LocStrings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$LiteralPath)

    # Validate the file exists.
    if (!(Test-Path -LiteralPath $LiteralPath -PathType Leaf)) {
        Write-Warning (Get-LocString -Key PSLIB_FileNotFound0 -ArgumentList $LiteralPath)
        return
    }

    # Load the json.
    Write-Verbose "Loading resource strings from: $LiteralPath"
    $count = 0
    if ($messages = (Get-Content -LiteralPath $LiteralPath -Encoding UTF8 | Out-String | ConvertFrom-Json).messages) {
        # Add each resource string to the hashtable.
        foreach ($member in (Get-Member -InputObject $messages -MemberType NoteProperty)) {
            [string]$key = $member.Name
            $script:resourceStrings[$key] = $messages."$key"
            $count++
        }
    }

    Write-Verbose "Loaded $count strings."

    # Get the culture.
    $culture = Get-TaskVariable -Name "System.Culture" -Default "en-US"

    # Load the resjson.
    $resjsonPath = "$([System.IO.Path]::GetDirectoryName($LiteralPath))\Strings\resources.resjson\$culture\resources.resjson"
    if (Test-Path -LiteralPath $resjsonPath) {
        Write-Verbose "Loading resource strings from: $resjsonPath"
        $count = 0
        $resjson = Get-Content -LiteralPath $resjsonPath -Encoding UTF8 | Out-String | ConvertFrom-Json
        foreach ($member in (Get-Member -Name loc.messages.* -InputObject $resjson -MemberType NoteProperty)) {
            if (!($value = $resjson."$($member.Name)")) {
                continue
            }

            [string]$key = $member.Name.Substring('loc.messages.'.Length)
            $script:resourceStrings[$key] = $value
            $count++
        }

        Write-Verbose "Loaded $count strings."
    }
}

# SIG # Begin signature block
# MIInnwYJKoZIhvcNAQcCoIInkDCCJ4wCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBCb0kJy558Jvwk
# jMrfdlKBV+D4yMzsznfGgVE6gqD3caCCDYEwggX/MIID56ADAgECAhMzAAACUosz
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
# BgEEAYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAvBgkqhkiG9w0BCQQxIgQgvdFYlRTf
# vr5MH9PT+bbflC5WdmdfA60lXmHLdXPioPkwNAYKKwYBBAGCNwIBDDEmMCSgEoAQ
# AFQAZQBzAHQAUwBpAGcAbqEOgAxodHRwOi8vdGVzdCAwDQYJKoZIhvcNAQEBBQAE
# ggEAZPSA2g2Zb4/C3pqDyM3I6HKMjH0OD7Ieh/5vUxTvGEslA6+IBD3MtT6y3at4
# WlbQx9kcDtTdh98ta7INZFv2zrKWFpn05OyKPTzm36YGWv06eVg+LGg0ZYw/SHd+
# ch9Sd/0IJKMEse35OLoCHWjFu4N/5YgaDfN8ia8ox1/82SPhBQuMsc/Yd/oCKlCx
# tIHiBUsMQpHA01BFRWH5MCzI0bIt39v+d8GYC4bluD3aMYI3AK7UxgbEG14o+HfE
# trlxZZpvRVpstVmL3KKcUZzU5V3NoBKDVSXHHMQeQFeYJWJ9qkC9+CngSgqfzi+m
# VVluieoFZg11tTbNFd5ylDgYDqGCFwwwghcIBgorBgEEAYI3AwMBMYIW+DCCFvQG
# CSqGSIb3DQEHAqCCFuUwghbhAgEDMQ8wDQYJYIZIAWUDBAIBBQAwggFVBgsqhkiG
# 9w0BCRABBKCCAUQEggFAMIIBPAIBAQYKKwYBBAGEWQoDATAxMA0GCWCGSAFlAwQC
# AQUABCAuPS+A3AwMZ9pzPLGwFdvOkCO4Ec7JKNttzy8ycDT0nQIGYrHY9o0OGBMy
# MDIyMDcwNzIxNDIyMy4yOTZaMASAAgH0oIHUpIHRMIHOMQswCQYDVQQGEwJVUzET
# MBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMV
# TWljcm9zb2Z0IENvcnBvcmF0aW9uMSkwJwYDVQQLEyBNaWNyb3NvZnQgT3BlcmF0
# aW9ucyBQdWVydG8gUmljbzEmMCQGA1UECxMdVGhhbGVzIFRTUyBFU046Nzg4MC1F
# MzkwLTgwMTQxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2Wg
# ghFfMIIHEDCCBPigAwIBAgITMwAAAahV8GGpzDAYXAABAAABqDANBgkqhkiG9w0B
# AQsFADB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UE
# BxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYD
# VQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDAeFw0yMjAzMDIxODUx
# MjNaFw0yMzA1MTExODUxMjNaMIHOMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2Fz
# aGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENv
# cnBvcmF0aW9uMSkwJwYDVQQLEyBNaWNyb3NvZnQgT3BlcmF0aW9ucyBQdWVydG8g
# UmljbzEmMCQGA1UECxMdVGhhbGVzIFRTUyBFU046Nzg4MC1FMzkwLTgwMTQxJTAj
# BgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2UwggIiMA0GCSqGSIb3
# DQEBAQUAA4ICDwAwggIKAoICAQCj2m3KwC4l1/KY8l6XDDfPSk73JpQIg8OKVPh3
# o2YYm1HqPx1Mvj/VcVoQl+6IHnijyeu+/i3lXT3RuYU7xg4ErqN8PgHJs3F2dkAh
# lIFEXi1Cm5q69OmwdMYb7WcKHpYcbT5IyRbG0xrUrflexOFQoz3WKkGf4jdAK115
# oGxH1cgsEvodrqKAYTOVHGz6ILa+VaYHc21DOP61rqZhVYzwdWrJ9/sL+2gQivI/
# UFCa6GOMtaZmUn9ErhjFmO3JtnL623Zu15XZY6kXR1vgkAAeBKojqoLpn0fmkqaO
# U++ShtPp7AZI5RkrFNQYteaeKz/PKWZ0qKe9xnpvRljthkS8D9eWBJyrHM8YRmPm
# fDRGtEMDDIlZZLHT1OyeaivYMQEIzic6iEic4SMEFrRC6oCaB8JKk8Xpt4K2Owew
# zs0E50KSlqC9B1kfSqiL2gu4vV5T7/rnvPY/Xu35geJ4dYbpcxCc1+kTFPUxyTJW
# zujqz9zTRCiVvI4qQp8vB9X7r0rhX7ge7fviivYNnNjSruRM0rNZyjarZeCjt1M8
# ly1r00QzuA+T1UDnWtLao0vwFqFK8SguWT5ZCxPmD7EuRvhP1QoAmoIT8gWbBzSu
# 8B5Un/9uroS5yqel0QCK6IhGJf+cltJkoY75wET69BiJUptCq6ksAo0eXJFk9bCm
# hG/MNwIDAQABo4IBNjCCATIwHQYDVR0OBBYEFDbH2+Pi+FLrZTYfzMYxpI9JCyLV
# MB8GA1UdIwQYMBaAFJ+nFV0AXmJdg/Tl0mWnG1M1GelyMF8GA1UdHwRYMFYwVKBS
# oFCGTmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY3JsL01pY3Jvc29m
# dCUyMFRpbWUtU3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNybDBsBggrBgEFBQcBAQRg
# MF4wXAYIKwYBBQUHMAKGUGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMv
# Y2VydHMvTWljcm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBDQSUyMDIwMTAoMSkuY3J0
# MAwGA1UdEwEB/wQCMAAwEwYDVR0lBAwwCgYIKwYBBQUHAwgwDQYJKoZIhvcNAQEL
# BQADggIBAHE7gktkaqpn9pj6+jlMnYZlMfpur6RD7M1oqCV257EW58utpxfWF0yr
# kjVh9UBX8nP9jd2ExKeIRPGLYWCoAzPx1IVERF91k8BrHmLrg3ksVkSVgqKwBxdZ
# MEMyCoK1HNxvrlcAJhvxCNRC0RMQOH7cdBIa3+fWiZuzp4J9JU0koilHrhgPjMuq
# Aov1fBE8c/nm5b0ADWpbSYBn6abll2E+I4rEChE76CYwb+cfgQNKBBbu4BmnjA5G
# Y5zub3X+h3ip3iC7PWb8CFpIGEItmXqM28YJRuWMBMaIsXpMa0Uw2cDKJCGMV5nH
# LHENMV5ofiN76O4VfWTCk2vT2s+Z3uHHPDncNU/utuJgdFmlvRwBNYaIwegm37p3
# bVf48MZnSodeaZSV5zdcjOzi/duB6gIiYrB2p6ThCeFJvW94RVFxNrhCS/WmLiIJ
# LFWCKtT9va0eF+5c97hCR+gjpKBOvlHGrjeiWBYITfSPCUQVgIR1+BkB5Z4LHX7V
# iy4g2TMp5YEQmc5GCNuDfXMfg9+u2MHJajWOgmbgIM8MtdrkWBUGrGB2CtYac8k7
# biPwNgfHBvhzOl9Y39nfbgEcB+voS5D7bd/+TQZS16TpeYmckZQYu4g15FjWt47h
# nywCdyEg8jYe8rvh+MkGMkbPzFawpFlCbPRIryyrDSdgfyIza0rWMIIHcTCCBVmg
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
# bGVzIFRTUyBFU046Nzg4MC1FMzkwLTgwMTQxJTAjBgNVBAMTHE1pY3Jvc29mdCBU
# aW1lLVN0YW1wIFNlcnZpY2WiIwoBATAHBgUrDgMCGgMVAGy6/MSfQQeKy+GIOfF9
# S2eYkHcsoIGDMIGApH4wfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0
# b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3Jh
# dGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAwDQYJ
# KoZIhvcNAQEFBQACBQDmcW7kMCIYDzIwMjIwNzA3MTg0MDM2WhgPMjAyMjA3MDgx
# ODQwMzZaMHcwPQYKKwYBBAGEWQoEATEvMC0wCgIFAOZxbuQCAQAwCgIBAAICFCwC
# Af8wBwIBAAICEhwwCgIFAOZywGQCAQAwNgYKKwYBBAGEWQoEAjEoMCYwDAYKKwYB
# BAGEWQoDAqAKMAgCAQACAwehIKEKMAgCAQACAwGGoDANBgkqhkiG9w0BAQUFAAOB
# gQAVdGSTe5oJr7gVRCra4jllLp3Q8AFMeTWjWcN2MwuDX0eKUKo/a/uQsjU+l+Xd
# TgVCjY1r5pHGgS95nHJls8ak9Jv8Hg1mAcyEhOSU2De8HRUj1bH5KB3dh3fTKY17
# wBCXoCq2S0SYb/jRIf9HbkwLuAloUPImaDXlqGPgRAckuDGCBA0wggQJAgEBMIGT
# MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdS
# ZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMT
# HU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwAhMzAAABqFXwYanMMBhcAAEA
# AAGoMA0GCWCGSAFlAwQCAQUAoIIBSjAaBgkqhkiG9w0BCQMxDQYLKoZIhvcNAQkQ
# AQQwLwYJKoZIhvcNAQkEMSIEIAbFSK8TZQF9YFYP02mGVf8DGl3yy0qyJSNPKE9W
# bh0IMIH6BgsqhkiG9w0BCRACLzGB6jCB5zCB5DCBvQQgdP7LHQDLB8JzcIXxQVz5
# RZ0b1oR6kl/WC1MQQ5dcZaYwgZgwgYCkfjB8MQswCQYDVQQGEwJVUzETMBEGA1UE
# CBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9z
# b2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQ
# Q0EgMjAxMAITMwAAAahV8GGpzDAYXAABAAABqDAiBCATkGJwnP7fRJU4WlXI4CvT
# 328k2SpL4ZlOIXy5ghZ3aTANBgkqhkiG9w0BAQsFAASCAgBUOXj2T0I/PUq1ym89
# hDUgxDqDGlsxGpqCL+nNkVQryYfJdLRFg5vhMtKn7eFkQIcNjz7G2yWJU37nI1WK
# Nio6X/b8h2yujWk4biG9vZFDfzFniXKlXDU6M2icwPRR25+AmQfhU3jyUdx/w4dU
# LWVYiI9WQ0sa9KlRf6adrtcYCiZw1PhKihpwFnIR6Fy+4WIQdvEf/BkphV5zj1Jq
# pDuFGBJ+r07sv3XCTBgdgKnQqYXYd2uON2kuiu71Dws5mTT80T/aZRQ7Ep4tC8bS
# 2lN4lMJqqlvz8pMFeb+WLibN57LA9XZku63mM1AX8BJcdjfvjJ5H7aT11Yu6ASbM
# QS4wDntXLRT/3uQJjCzD/++he728am0hJsszWZOWFXLh1EvIsfOEj2HdFbA5ulgf
# pEeuqj2o2N3wqh/ro/djas6zXCFNifBCbuH484+Nm1U0ZHtVjt0X7/74UldVkuOY
# Pd6WWbV7Q1mASTZ/vl61Mux7Lko21drQoQBQOSMNZUoFdjfQ4dSOZIzqqd3R19hU
# q1GVmeW4iGOKU6bziAMhlpcK/t9nRftBDl4hrSqekMK1UzLC6veGYkQwk1m23v1n
# 1v4rjlcw1xYM2gND0SR1wTHfGyhErSWCi0srL4zB6YwPBjl2lDQCyizqe/FuvX/m
# ezZHUHGgqrTPixw9b1TatWg4eQ==
# SIG # End signature block
