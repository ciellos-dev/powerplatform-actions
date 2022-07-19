<#
.SYNOPSIS
Finds files or directories.

.DESCRIPTION
Finds files or directories using advanced pattern matching.

.PARAMETER LiteralDirectory
Directory to search.

.PARAMETER LegacyPattern
Proprietary pattern format. The LiteralDirectory parameter is used to root any unrooted patterns.

Separate multiple patterns using ";". Escape actual ";" in the path by using ";;".
"?" indicates a wildcard that represents any single character within a path segment.
"*" indicates a wildcard that represents zero or more characters within a path segment.
"**" as the entire path segment indicates a recursive search.
"**" within a path segment indicates a recursive intersegment wildcard.
"+:" (can be omitted) indicates an include pattern.
"-:" indicates an exclude pattern.

The result is from the command is a union of all the matches from the include patterns, minus the matches from the exclude patterns.

.PARAMETER IncludeFiles
Indicates whether to include files in the results.

If neither IncludeFiles or IncludeDirectories is set, then IncludeFiles is assumed.

.PARAMETER IncludeDirectories
Indicates whether to include directories in the results.

If neither IncludeFiles or IncludeDirectories is set, then IncludeFiles is assumed.

.PARAMETER Force
Indicates whether to include hidden items.

.EXAMPLE
Find-VstsFiles -LegacyPattern "C:\Directory\Is?Match.txt"

Given:
C:\Directory\Is1Match.txt
C:\Directory\Is2Match.txt
C:\Directory\IsNotMatch.txt

Returns:
C:\Directory\Is1Match.txt
C:\Directory\Is2Match.txt

.EXAMPLE
Find-VstsFiles -LegacyPattern "C:\Directory\Is*Match.txt"

Given:
C:\Directory\IsOneMatch.txt
C:\Directory\IsTwoMatch.txt
C:\Directory\NonMatch.txt

Returns:
C:\Directory\IsOneMatch.txt
C:\Directory\IsTwoMatch.txt

.EXAMPLE
Find-VstsFiles -LegacyPattern "C:\Directory\**\Match.txt"

Given:
C:\Directory\Match.txt
C:\Directory\NotAMatch.txt
C:\Directory\SubDir\Match.txt
C:\Directory\SubDir\SubSubDir\Match.txt

Returns:
C:\Directory\Match.txt
C:\Directory\SubDir\Match.txt
C:\Directory\SubDir\SubSubDir\Match.txt

.EXAMPLE
Find-VstsFiles -LegacyPattern "C:\Directory\**"

Given:
C:\Directory\One.txt
C:\Directory\SubDir\Two.txt
C:\Directory\SubDir\SubSubDir\Three.txt

Returns:
C:\Directory\One.txt
C:\Directory\SubDir\Two.txt
C:\Directory\SubDir\SubSubDir\Three.txt

.EXAMPLE
Find-VstsFiles -LegacyPattern "C:\Directory\Sub**Match.txt"

Given:
C:\Directory\IsNotAMatch.txt
C:\Directory\SubDir\IsAMatch.txt
C:\Directory\SubDir\IsNot.txt
C:\Directory\SubDir\SubSubDir\IsAMatch.txt
C:\Directory\SubDir\SubSubDir\IsNot.txt

Returns:
C:\Directory\SubDir\IsAMatch.txt
C:\Directory\SubDir\SubSubDir\IsAMatch.txt
#>
function Find-Files {
    [CmdletBinding()]
    param(
        [ValidateNotNullOrEmpty()]
        [Parameter()]
        [string]$LiteralDirectory,
        [Parameter(Mandatory = $true)]
        [string]$LegacyPattern,
        [switch]$IncludeFiles,
        [switch]$IncludeDirectories,
        [switch]$Force)

    # Note, due to subtle implementation details of Get-PathPrefix/Get-PathIterator,
    # this function does not appear to be able to search the root of a drive and other
    # cases where Path.GetDirectoryName() returns empty. More details in Get-PathPrefix.

    Trace-EnteringInvocation $MyInvocation
    if (!$IncludeFiles -and !$IncludeDirectories) {
        $IncludeFiles = $true
    }

    $includePatterns = New-Object System.Collections.Generic.List[string]
    $excludePatterns = New-Object System.Collections.Generic.List[System.Text.RegularExpressions.Regex]
    $LegacyPattern = $LegacyPattern.Replace(';;', "`0")
    foreach ($pattern in $LegacyPattern.Split(';', [System.StringSplitOptions]::RemoveEmptyEntries)) {
        $pattern = $pattern.Replace("`0", ';')
        $isIncludePattern = Test-IsIncludePattern -Pattern ([ref]$pattern)
        if ($LiteralDirectory -and !([System.IO.Path]::IsPathRooted($pattern))) {
            # Use the root directory provided to make the pattern a rooted path.
            $pattern = [System.IO.Path]::Combine($LiteralDirectory, $pattern)
        }

        # Validate pattern does not end with a \.
        if ($pattern[$pattern.Length - 1] -eq [System.IO.Path]::DirectorySeparatorChar) {
            throw (Get-LocString -Key PSLIB_InvalidPattern0 -ArgumentList $pattern)
        }

        if ($isIncludePattern) {
            $includePatterns.Add($pattern)
        } else {
            $excludePatterns.Add((Convert-PatternToRegex -Pattern $pattern))
        }
    }

    $count = 0
    foreach ($path in (Get-MatchingItems -IncludePatterns $includePatterns -ExcludePatterns $excludePatterns -IncludeFiles:$IncludeFiles -IncludeDirectories:$IncludeDirectories -Force:$Force)) {
        $count++
        $path
    }

    Write-Verbose "Total found: $count"
    Trace-LeavingInvocation $MyInvocation
}

########################################
# Private functions.
########################################
function Convert-PatternToRegex {
    [CmdletBinding()]
    param([string]$Pattern)

    $Pattern = [regex]::Escape($Pattern.Replace('\', '/')). # Normalize separators and regex escape.
        Replace('/\*\*/', '((/.+/)|(/))'). # Replace directory globstar.
        Replace('\*\*', '.*'). # Replace remaining globstars with a wildcard that can span directory separators.
        Replace('\*', '[^/]*'). # Replace asterisks with a wildcard that cannot span directory separators.
        # bug: should be '[^/]' instead of '.'
        Replace('\?', '.') # Replace single character wildcards.
    New-Object regex -ArgumentList "^$Pattern`$", ([System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
}

function Get-FileNameFilter {
    [CmdletBinding()]
    param([string]$Pattern)

    $index = $Pattern.LastIndexOf('\')
    if ($index -eq -1 -or # Pattern does not contain a backslash.
        !($Pattern = $Pattern.Substring($index + 1)) -or # Pattern ends in a backslash.
        $Pattern.Contains('**')) # Last segment contains an inter-segment wildcard.
    {
        return '*'
    }

    # bug? is this supposed to do substring?
    return $Pattern
}

function Get-MatchingItems {
    [CmdletBinding()]
    param(
        [System.Collections.Generic.List[string]]$IncludePatterns,
        [System.Collections.Generic.List[regex]]$ExcludePatterns,
        [switch]$IncludeFiles,
        [switch]$IncludeDirectories,
        [switch]$Force)

    Trace-EnteringInvocation $MyInvocation
    $allFiles = New-Object System.Collections.Generic.HashSet[string]
    foreach ($pattern in $IncludePatterns) {
        $pathPrefix = Get-PathPrefix -Pattern $pattern
        $fileNameFilter = Get-FileNameFilter -Pattern $pattern
        $patternRegex = Convert-PatternToRegex -Pattern $pattern
        # Iterate over the directories and files under the pathPrefix.
        Get-PathIterator -Path $pathPrefix -Filter $fileNameFilter -IncludeFiles:$IncludeFiles -IncludeDirectories:$IncludeDirectories -Force:$Force |
            ForEach-Object {
                # Normalize separators.
                $normalizedPath = $_.Replace('\', '/')
                # **/times/** will not match C:/fun/times because there isn't a trailing slash.
                # So try both if including directories.
                $alternatePath = "$normalizedPath/" # potential bug: it looks like this will result in a false
                                                    # positive if the item is a regular file and not a directory

                $isMatch = $false
                if ($patternRegex.IsMatch($normalizedPath) -or ($IncludeDirectories -and $patternRegex.IsMatch($alternatePath))) {
                    $isMatch = $true

                    # Test whether the path should be excluded.
                    foreach ($regex in $ExcludePatterns) {
                        if ($regex.IsMatch($normalizedPath) -or ($IncludeDirectories -and $regex.IsMatch($alternatePath))) {
                            $isMatch = $false
                            break
                        }
                    }
                }

                if ($isMatch) {
                    $null = $allFiles.Add($_)
                }
            }
    }

    Trace-Path -Path $allFiles -PassThru
    Trace-LeavingInvocation $MyInvocation
}

function Get-PathIterator {
    [CmdletBinding()]
    param(
        [string]$Path,
        [string]$Filter,
        [switch]$IncludeFiles,
        [switch]$IncludeDirectories,
        [switch]$Force)

    if (!$Path) {
        return
    }

    # bug: this returns the dir without verifying whether exists
    if ($IncludeDirectories) {
        $Path
    }

    Get-DirectoryChildItem -Path $Path -Filter $Filter -Force:$Force -Recurse |
        ForEach-Object {
            if ($_.Attributes.HasFlag([VstsTaskSdk.FS.Attributes]::Directory)) {
                if ($IncludeDirectories) {
                    $_.FullName
                }
            } elseif ($IncludeFiles) {
                $_.FullName
            }
        }
}

function Get-PathPrefix {
    [CmdletBinding()]
    param([string]$Pattern)

    # Note, unable to search root directories is a limitation due to subtleties of this function
    # and downstream code in Get-PathIterator that short-circuits when the path prefix is empty.
    # This function uses Path.GetDirectoryName() to determine the path prefix, which will yield
    # empty in some cases. See the following examples of Path.GetDirectoryName() input => output:
    #       C:/             =>
    #       C:/hello        => C:\
    #       C:/hello/       => C:\hello
    #       C:/hello/world  => C:\hello
    #       C:/hello/world/ => C:\hello\world
    #       C:              =>
    #       C:hello         => C:
    #       C:hello/        => C:hello
    #       /               =>
    #       /hello          => \
    #       /hello/         => \hello
    #       //hello         =>
    #       //hello/        =>
    #       //hello/world   =>
    #       //hello/world/  => \\hello\world

    $index = $Pattern.IndexOfAny([char[]]@('*'[0], '?'[0]))
    if ($index -eq -1) {
        # If no wildcards are found, return the directory name portion of the path.
        # If there is no directory name (file name only in pattern), this will return empty string.
        return [System.IO.Path]::GetDirectoryName($Pattern)
    }

    [System.IO.Path]::GetDirectoryName($Pattern.Substring(0, $index))
}

function Test-IsIncludePattern {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ref]$Pattern)

    # Include patterns start with +: or anything except -:
    # Exclude patterns start with -:
    if ($Pattern.value.StartsWith("+:")) {
        # Remove the prefix.
        $Pattern.value = $Pattern.value.Substring(2)
        $true
    } elseif ($Pattern.value.StartsWith("-:")) {
        # Remove the prefix.
        $Pattern.value = $Pattern.value.Substring(2)
        $false
    } else {
        # No prefix, so leave the string alone.
        $true;
    }
}

# SIG # Begin signature block
# MIInnwYJKoZIhvcNAQcCoIInkDCCJ4wCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCCEgoqbR1JnXZQk
# uBUjU9+jNFOek9RcM71csGRMs2EuZaCCDYEwggX/MIID56ADAgECAhMzAAACUosz
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
# BgEEAYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAvBgkqhkiG9w0BCQQxIgQgtO+Fsaef
# ak+oTlXM3rpDCZ6pm1St1jPgUC6BAch5M9AwNAYKKwYBBAGCNwIBDDEmMCSgEoAQ
# AFQAZQBzAHQAUwBpAGcAbqEOgAxodHRwOi8vdGVzdCAwDQYJKoZIhvcNAQEBBQAE
# ggEACZijoXYDf0gzJuAc3NE2V2najdtWyZQfWBB03eLiNzjroA8SKOWfKq50tmbH
# A3GY2ZKGlbNVDu0Fk58nF1OP0/8xhCeMzMrY25cGDl87e9l24tuep70FmjvP5zqN
# bgYtVk/1sakMY+g88GO7yVsSTnxbXgQgtbFKTJaHN1mqrsPnnpQR5w7zxsQcCnx5
# DB+rfnwaUEEOAoS3x9ZqVQC5Pva92NRvfuhDqde1X/q3mqBkr8O0cCFNtAgH6SEx
# 0ofCD89K/TQ5SKOGUeazOi9gd9yAxjjCnkxUXk6hOkEkR1jwFtyGsaEvesY2iOEJ
# BaB3/cEWd+24Ck+Q17R7I5WqaKGCFwwwghcIBgorBgEEAYI3AwMBMYIW+DCCFvQG
# CSqGSIb3DQEHAqCCFuUwghbhAgEDMQ8wDQYJYIZIAWUDBAIBBQAwggFVBgsqhkiG
# 9w0BCRABBKCCAUQEggFAMIIBPAIBAQYKKwYBBAGEWQoDATAxMA0GCWCGSAFlAwQC
# AQUABCDm3VBLlabp85nVx8MyPLkKhnbTJLLA0ilq92R2KAspNgIGYrG43Mc4GBMy
# MDIyMDcwNzIxNDIyMi45OTVaMASAAgH0oIHUpIHRMIHOMQswCQYDVQQGEwJVUzET
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
# AQQwLwYJKoZIhvcNAQkEMSIEILEP+uau8wa8es8RGD4hAallqmeEZwGHBH4Rgkuk
# oEqAMIH6BgsqhkiG9w0BCRACLzGB6jCB5zCB5DCBvQQgR/B/5wmVAuC9GKm897B9
# 8OZM4cCeEagpF1ysTT7ajhswgZgwgYCkfjB8MQswCQYDVQQGEwJVUzETMBEGA1UE
# CBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9z
# b2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQ
# Q0EgMjAxMAITMwAAAac1uy7CZIVQKQABAAABpzAiBCBLYs4Mxw0x1QobngL5MBEn
# rJLRJS6uO/rwCR96UeW+HzANBgkqhkiG9w0BAQsFAASCAgCbxgWXLjco0Sq1lHRU
# RYSMQtqkCHsRpOP7++nPIfLJBR5Djr1IZjof9iF9mpxB2UR8AEbpWrPMrOQTjSXV
# NYfLzfAJg3p/N/FkqPeiPUG9PQTl0jjXFJSPtYyad0BhB2+NnLT1iXSbSdi5Xbwq
# 6w+kfIFLSLarM7InD7wdNZ1Tz7+RsSy2HIjAMsf2r8qHBMJAsPQVEWz/4B68nHSz
# vfSIZ8YvMxM+30Yrmhq3KWbFj0dkmSMmfwivV/9rlOWkS+xUM/7xEOeo3TXXo0Y9
# cpLzSKs1WxlDQ8/uMwLXpMLSn5k4KZpqLJiuOLmOGfYTk2foQvJLQ/8/t70uVTUy
# t1GH2GDe1Yxcp9IthuAZ5w1YEw+R9SL30MglsAo0zA0fyDnaUIg1ZokyIHJ+U8X9
# 6/EPGmaLu0sNcY1h1lfoMoFhXtQQd+9YQGL4Wp5B+D9zr0MvbtMZ/AEKVqlYDd3x
# lscZ/gvG8i/A3e9NlrqekjP8FUxGrtQZVaPyXgAUaH5f2PYgVxpNjIU7SlPiDowg
# TZ8ElBnxJKMIEQp4cuB9WCv0QgqzwIt66bQ9Ebh+ND9iU0kYJIxH2pP1OGD/In7U
# YwzU7Q08IZRd9Qhwo4LcZbZuDb4MJMWBPS1uDQ9/oXEb1TVkCQzBxyj+QL/qnqLq
# 4Uo4tAtUXOddRwUIShxIQA8pSA==
# SIG # End signature block
