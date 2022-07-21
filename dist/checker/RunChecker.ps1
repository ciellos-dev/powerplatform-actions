# Copyright (c) Microsoft Corporation. All rights reserved.

[CmdletBinding()]
param()

function Invoke-PAChecker {
    [CmdletBinding()]
    param (
        [parameter (Mandatory = $true)][guid]$TenantID,
        [parameter (Mandatory = $true)][guid]$ClientApplicationId,
        [parameter (Mandatory = $true)][securestring]$ClientApplicationSecret,
        [parameter (Mandatory = $true)][uri]$ApiUrl,
        [parameter (Mandatory = $false)][string]$FileUnderAnalysis = $null,
        [parameter (Mandatory = $false)][string]$FileUnderAnalysisSasUri = $null,
        [parameter (Mandatory = $true)][Microsoft.PowerApps.Checker.Client.Models.Ruleset]$Ruleset,
        [parameter (Mandatory = $true)][string]$OutputDirectory,
        [parameter (Mandatory = $false)][string[]]$ExcludedFileNamePattern,
        [parameter (Mandatory = $false)][Microsoft.PowerApps.Checker.Client.Models.Rule[]]$RuleLevelOverrides,
        [parameter (Mandatory = $false)][string]$IncludeMessageFormats,
        [parameter (Mandatory = $false)][string]$LocaleName,
        # see also range min/max for these parameters: CRMDevTools: src\GeneralTools\PowerShell\Microsoft.PowerApps.Checker.PowerShell\Microsoft.PowerApps.Checker.PowerShell\Cmdlets\InvokePowerAppsChecker.cs
        [parameter (Mandatory = $false)][int]$MaxStatusChecks = 50,
        [parameter (Mandatory = $false)][int]$SecondsBetweenChecks = 60
    )

    begin {
        #Setup parameter hash table
        $Parameters = . Get-ParameterValue
    }

    process {
        #Invoke PowerApps Checker
        Write-Verbose "MaxWaitTime: $($MaxStatusChecks * $SecondsBetweenChecks) sec"
        $output = Invoke-PowerAppsChecker -Verbose @Parameters
    }

    end {
        return $output
    }
}

function Get-PACheckerRuleset {
    [CmdletBinding()]
    param (
        [parameter (Mandatory = $true)][uri]$apiUrl,
        [parameter (Mandatory = $true)][string]$rulesetIdOrName
    )

    begin {
        $allRulesets = Get-PowerAppsCheckerRulesets -ApiUrl $apiUrl
    }

    process {
        $powerAppsCheckerRuleset = $allRulesets | `
            Where-Object { $_.Id -eq $rulesetIdOrName -or $_.Name -eq $rulesetIdOrName }

        if ($null -eq $powerAppsCheckerRuleset) {
            if ([guid]::TryParse($rulesetIdOrName, $([ref][guid]::Empty))) {
                $powerAppsCheckerRuleset = [Microsoft.PowerApps.Checker.Client.Models.Ruleset]@{Id=$rulesetIdOrName}
            }else {
                $powerAppsCheckerRuleset = [Microsoft.PowerApps.Checker.Client.Models.Ruleset]@{Name=$rulesetIdOrName}
            }
            Write-VstsTaskWarning "RuleSets task parameter specified an unknown ruleset id or name: $rulesetIdOrName (got rulesets from: $apiUrl)"
        }
    }

    end {
        return $powerAppsCheckerRuleset
    }
}

function Confirm-PACheckerResults {
    [CmdletBinding()]
    param (
        [parameter (Mandatory = $true)][Microsoft.PowerApps.Checker.Client.Models.AnalyzeResult]$paCheckerResult,
        [parameter (Mandatory = $true)][string]$errorLevel,
        [parameter (Mandatory = $true)][int]$errorThreshold,
        [parameter (Mandatory = $true)][bool]$failOnPowerAppsCheckerAnalysisError
    )

    begin {
        $PAErrorLevels = @{
            "CriticalIssueCount" = 5
            "HighIssueCount" = 4
            "MediumIssueCount" = 3
            "LowIssueCount" = 2
            "InformationalIssueCount" = 1
        }
    }

    process {
        Write-Host "##[section]Processing PowerApps Checker Result..."
        Write-Host "`tFile: $($paCheckerResult.DownloadedResultFiles)`n`tCorrelation ID: $($paCheckerResult.RunCorrelationId.Guid)`n`tStatus: $($paCheckerResult.Status)"

        if ($($paCheckerResult.Status) -eq [Microsoft.PowerApps.Checker.Client.Models.ResultStatus]::Failed -or $($paCheckerResult.Status) -eq [Microsoft.PowerApps.Checker.Client.Models.ResultStatus]::FinishedWithErrors) {
            if ($failOnPowerAppsCheckerAnalysisError) {
                Write-VstsTaskError "PowerApps Checker analysis results indicate a failure or error during the analysis process."
                Write-VstsSetResult -Result "Failed" -DoNotThrow
            }
            else {
                Write-VstsTaskWarning "PowerApps Checker analysis results indicate a failure or error during the analysis process."
            }
        }

        # Get error levels greater than or equal to error level
        $errorLevelsToCheck = $PAErrorLevels.GetEnumerator() | Where-Object {$_.value -ge $PAErrorLevels[$errorLevel]}

        foreach ($errorLevelToCheck in $errorLevelsToCheck) {
            if ($paCheckerResult.IssueSummary.$($errorLevelToCheck.Name) -gt $errorThreshold ) {
                Write-VstsTaskError "Analysis results do not pass with selected error level and threshold choices.  Please review detailed results in SARIF file for more information."
                Write-VstsSetResult -Result "Failed" -DoNotThrow
                break
            }
        }

        $out = Out-String -InputObject $paCheckerResult.IssueSummary
    }

    end {
        Write-Host $out
    }
}

function Publish-PACheckerResults {
    [CmdletBinding()]
    param (
        [parameter (Mandatory = $true)][string[]]$resultFiles,
        [parameter (Mandatory = $true)][string]$outputSummary,
        [parameter (Mandatory = $true)][string]$outputDirectory,
        [parameter (Mandatory = $true)][string]$artifactDestName,
        [parameter (Mandatory = $true)][bool]$hasArtifactUpload
    )

    begin {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
     }

    process {
        $resultsDirectory = Join-Path -Path $outputDirectory "results"
        New-Item $resultsDirectory -ItemType Directory -Force | Out-Null
        foreach ($resultFile in $resultFiles) {
            [System.IO.Compression.ZipFile]::ExtractToDirectory($resultFile, $resultsDirectory)
        }
        $issueResultSummary = Join-Path $resultsDirectory "IssueResultSummary.md"
        Set-Content -Value $outputSummary -Path $issueResultSummary -Force

        if ($hasArtifactUpload) {
            # Upload SARIF output for use in SARIF extension
            Write-VstsUploadArtifact -ContainerFolder "PowerAppsChecker" -Name $artifactDestName -Path $resultsDirectory
            # Upload issue summary results
            Write-VstsUploadSummary $issueResultSummary
        } else {
            # release pipelines don't have artifacts nor attachements: just upload as files
            foreach ($resultFile in (Get-ChildItem $resultsDirectory)) {
                $resultFile = Join-Path -Path $resultsDirectory $resultFile
                Write-Verbose "resultFile: $resultFile"
                Write-VstsUploadFile $resultFile
            }
            Write-VstsUploadFile $issueResultSummary
        }

    }

    end { }
}

function Get-PACheckerEndpoint  {
    param (
        [string][ValidateNotNullOrEmpty()] $environmentUrl
    )
    $source = [string]::Join('.', ([uri]$environmentUrl).Host.Split('.')[-3..-1])
    $url = switch ($source) {
        # https://docs.microsoft.com/en-us/powerapps/developer/common-data-service/online-management-api/get-started-online-management-api#service-url
        'crm.dynamics.com'         { 'https://unitedstates.api.advisor.powerapps.com/' }
        'crm2.dynamics.com'        { 'https://southamerica.api.advisor.powerapps.com/' }
        'crm3.dynamics.com'        { 'https://canada.api.advisor.powerapps.com/' }
        'crm4.dynamics.com'        { 'https://europe.api.advisor.powerapps.com/' }
        'crm5.dynamics.com'        { 'https://asia.api.advisor.powerapps.com/' }
        'crm6.dynamics.com'        { 'https://australia.api.advisor.powerapps.com/' }
        'crm7.dynamics.com'        { 'https://japan.api.advisor.powerapps.com/' }
        'crm8.dynamics.com'        { 'https://india.api.advisor.powerapps.com/' }
        'crm9.dynamics.com'        { 'https://gov.api.advisor.powerapps.us/' }
        'crm11.dynamics.com'       { 'https://unitedkingdom.api.advisor.powerapps.com/' }
        'crm12.dynamics.com'       { 'https://france.api.advisor.powerapps.com/' }
        'crm15.dynamics.com'       { 'https://unitedarabemirates.api.advisor.powerapps.com/' }
        'crm16.dynamics.com'       { 'https://germany.api.advisor.powerapps.com/' }
        'crm17.dynamics.com'       { 'https://switzerland.api.advisor.powerapps.com/' }
        'crm.dynamics.cn'          { 'https://china.api.advisor.powerapps.cn/' }
        'crm.microsoftdynamics.us' { 'https://high.api.advisor.powerapps.us/' }
        'crm.appsplatforms.us'     { 'https://mil.api.advisor.appsplatform.us/' }
        Default { 'https://unitedstates.api.advisor.powerapps.com/' }
    }
    return $url
}

function Analyze-FilesWithPAChecker {
    [CmdletBinding()]
    param (
        [parameter (Mandatory = $true)][string[]]$fileList,
        [parameter (Mandatory = $true)][bool]$isLocalFile,
        [parameter (Mandatory = $true)][PSCustomObject]$authInfo,
        [parameter (Mandatory = $true)][string]$paCheckerEndpointUrl,
        [parameter (Mandatory = $true)][Microsoft.PowerApps.Checker.Client.Models.Ruleset]$ruleset,
        [parameter (Mandatory = $true)][string]$outputDirectoryPath,
        [parameter (Mandatory = $false)][string[]]$excludedFileNamePattern,
        [parameter (Mandatory = $false)][Microsoft.PowerApps.Checker.Client.Models.Rule[]]$overrides,
        [parameter (Mandatory = $true)][string]$errorLevel,
        [parameter (Mandatory = $true)][int]$errorThreshold,
        [parameter (Mandatory = $true)][bool]$failOnPowerAppsCheckerAnalysisError,
        [parameter (Mandatory = $true)][AllowEmptyCollection()][System.Collections.ArrayList]$resultFileList,
        [parameter (Mandatory = $true)][string]$outputSummary
    )

    begin {}

    process {
        foreach ($file in $fileList) {
            if ($isLocalFile) {
                $paCheckerResult = Invoke-PAChecker -fileUnderAnalysis $file `
                    -tenantID $authInfo.TenantId -clientApplicationId $authInfo.Credential.UserName -clientApplicationSecret $authInfo.Credential.Password `
                    -apiUrl $paCheckerEndpointUrl -Ruleset $ruleSet -outputDirectory $outputDirectoryPath -ExcludedFileNamePattern $excludedFileNamePattern `
                    -RuleLevelOverrides $overrides
            } else {
                $paCheckerResult = Invoke-PAChecker -fileUnderAnalysisSasUri $file `
                    -tenantID $authInfo.TenantId -clientApplicationId $authInfo.Credential.UserName -clientApplicationSecret $authInfo.Credential.Password `
                    -apiUrl $paCheckerEndpointUrl -Ruleset $ruleSet -outputDirectory $outputDirectoryPath -ExcludedFileNamePattern $excludedFileNamePattern `
                    -RuleLevelOverrides $overrides
            }

            Confirm-PACheckerResults -paCheckerResult $paCheckerResult -errorLevel $errorLevel -errorThreshold $errorThreshold -failOnPowerAppsCheckerAnalysisError $failOnPowerAppsCheckerAnalysisError
            $resultFileList.AddRange(@($($paCheckerResult.DownloadedResultFiles)))
            $fileName = Split-Path $($paCheckerResult.DownloadedResultFiles) -Leaf
            $outputSummary += "`n|$fileName|$($paCheckerResult.IssueSummary.CriticalIssueCount)|$($paCheckerResult.IssueSummary.HighIssueCount)|$($paCheckerResult.IssueSummary.MediumIssueCount)|$($paCheckerResult.IssueSummary.LowIssueCount)|$($paCheckerResult.IssueSummary.InformationalIssueCount)|"
        }
    }

    end {
        return ,$outputSummary
    }
}

function ToRuleLevel {
    [CmdletBinding()]
    param (
        [parameter (Mandatory = $true)][string]$RuleLevelString
    )

    switch -Exact ($RuleLevelString)
    {
        "Critical" { [Microsoft.PowerApps.Checker.PowerShell.RuleLevel]::Critical }
        "High" { [Microsoft.PowerApps.Checker.PowerShell.RuleLevel]::High }
        "Medium" { [Microsoft.PowerApps.Checker.PowerShell.RuleLevel]::Medium }
        "Low" { [Microsoft.PowerApps.Checker.PowerShell.RuleLevel]::Low }
        "Informational" { [Microsoft.PowerApps.Checker.PowerShell.RuleLevel]::Informational }
    }
 }

Trace-VstsEnteringInvocation $MyInvocation
try {
    # Load shared functions and other dependencies
    ("..\ps_modules\SharedFunctions.psm1", "..\ps_modules\Get-ParameterValue.ps1") `
        | %{ Join-Path -Path $PSScriptRoot $_ } | Import-Module
    $redirector = Get-BindingRedirector

    Import-PowerPlatformToolsPowerShellModule -ModuleName "Microsoft.PowerApps.Checker.PowerShell"

    # Get input parameters and credentials; PA Checker only supports SPN authN
    $authInfo = Get-AuthInfoFromActiveServiceConnection -selectedAuthName "PowerPlatformSPN"

    $taskJson = Join-Path -Path $PSScriptRoot "task.json"
    $useDefaultEndpoint = Get-VstsInputWithDefault -Name "UseDefaultPACheckerEndpoint" -taskJsonFile $taskJson -AsBool
    if ($useDefaultEndpoint) {
        $paCheckerEndpointUrl = Get-PACheckerEndpoint -environmentUrl $authInfo.EnvironmentUrl
    } else {
        $paCheckerEndpointUrl = Get-VstsInputWithDefault -Name "CustomPACheckerEndpoint" -taskJsonFile $taskJson
        if ([String]::IsNullOrEmpty($paCheckerEndpointUrl)) {
            $paCheckerEndpointUrl = Get-PACheckerEndpoint -environmentUrl $authInfo.EnvironmentUrl
            Write-Warning "Missing Custom URL for PowerApps Checker; falling back to default location: $paCheckerEndpointUrl "
        }
    }

    $fileLocation = Get-VstsInputWithDefault -Name "FileLocation" -taskJsonFile $taskJson
    $filesToAnalyze = Get-VstsInputWithDefault -Name "FilesToAnalyze" -taskJsonFile $taskJson
    $filesToAnalyzeSasUriList = Get-VstsInputWithDefault -Name "FilesToAnalyzeSasUri" -taskJsonFile $taskJson
    $filesToExcludeList = Get-VstsInputWithDefault -Name "FilesToExclude" -taskJsonFile $taskJson
    $RulesToOverride = Get-VstsInputWithDefault -Name "RulesToOverride" -taskJsonFile $taskJson
    $errorLevel = Get-VstsInputWithDefault -Name "ErrorLevel" -taskJsonFile $taskJson
    $errorThreshold = Get-VstsInputWithDefault -Name "ErrorThreshold" -taskJsonFile $taskJson -AsInt
    # TODO: task.json should have this list generated at VSIX build time
    # see Task: #1851194
    # the picklist is editable, so its value is either the key/id of the selcted option, or a free form text with the name of a ruleset:
    $ruleSetIdOrName = Get-VstsInputWithDefault -Name "RuleSet" -taskJsonFile $taskJson
    # truncate to length of guid plus ~4 chars
    $rulesetIdOrName = $rulesetIdOrName.Substring(0, [System.Math]::Min(40, $rulesetIdOrName.Length))

    $artifactDestName = Get-VstsInputWithDefault -Name "ArtifactDestinationName" -taskJsonFile $taskJson
    $failOnPowerAppsCheckerAnalysisError = Get-VstsInputWithDefault -Name "FailOnPowerAppsCheckerAnalysisError" -taskJsonFile $taskJson -AsBool

    $outputDirectory = Get-OutputDirectory "PowerAppsChecker"
    Write-Verbose "outputDirectory: $($outputDirectory.path)"

    $resultFileList = New-Object System.Collections.ArrayList
    $outputSummary = "|File|Critical|High|Medium|Low|Informational|"
    $outputSummary += "`n|---|---|---|---|---|---|"

    # Get PowerApps Checker Ruleset
    $ruleset = Get-PACheckerRuleset -apiUrl $paCheckerEndpointUrl -rulesetIdOrName $ruleSetIdOrName
    Write-Host "##[section]Starting PowerApps Checker Analysis..."
    Write-Host "`tRuleSet: $($ruleset.Name)`n`tError Level: $($errorLevel.Replace('IssueCount',''))`n`tError Threshold: $errorThreshold"

    # Process files to exclude
    $excludedFileNamePattern = ""
    if ($null -ne $filesToExcludeList) {
        $excludedFileNamePattern = $filesToExcludeList.Split(",;")
    }

    # Process rules to override
    $overridesArray = @()
    if ($null -ne $RulesToOverride) {
        try {
            $rulesToOverrideList = ConvertFrom-Json $RulesToOverride
            foreach ($override in $rulesToOverrideList){
                if (![string]::IsNullOrWhiteSpace($override.Id) -and ![string]::IsNullOrWhiteSpace($override.OverrideLevel)){
                    $overrideLevel = ToRuleLevel -RuleLevelString $override.OverrideLevel
                    if ($null -ne $overrideLevel){
                        $override = New-PowerAppsCheckerRuleLevelOverride -Id $override.Id -OverrideLevel $override.OverrideLevel
                        $overridesArray += $override
                    }else {
                        Write-VstsTaskWarning "Invalid override level $($override.OverrideLevel) in JSON string. Skipping rule overrides for ruleId $($override.Id)."
                    }
                }
            }
        }
        catch {
            Write-VstsTaskWarning "Fail to parse RulesToOverride JSON string. Skipping rule overrides."
        }
    }

    # Process local files and invoke PowerApps Checker
    if ($fileLocation -eq "localFiles") {
        $localFiles = Find-VstsMatch -Pattern $filesToAnalyze
        if (!$localFiles.Count) {
            Write-VstsTaskError "Could not locate any files to analyze using input: $filesToAnalyze"
        }
        $outputSummary = Analyze-FilesWithPAChecker -fileList $localFiles `
                            -isLocalFile $true `
                            -authInfo $authInfo `
                            -paCheckerEndpointUrl $paCheckerEndpointUrl `
                            -ruleset $ruleSet `
                            -outputDirectoryPath $outputDirectory.path `
                            -excludedFileNamePattern $excludedFileNamePattern `
                            -overrides $overridesArray `
                            -errorLevel $errorLevel `
                            -errorThreshold $errorThreshold `
                            -failOnPowerAppsCheckerAnalysisError $failOnPowerAppsCheckerAnalysisError `
                            -resultFileList $resultFileList `
                            -outputSummary $outputSummary
    }
    # Process sas uri file
    elseif ($fileLocation -eq "sasUriFile") {
        $filesToAnalyzeSasUri = $filesToAnalyzeSasUriList.Split(",;")
        $outputSummary = Analyze-FilesWithPAChecker -fileList $filesToAnalyzeSasUri `
                            -isLocalFile $false `
                            -authInfo $authInfo `
                            -paCheckerEndpointUrl $paCheckerEndpointUrl `
                            -ruleset $ruleSet `
                            -outputDirectoryPath $outputDirectory.path `
                            -excludedFileNamePattern $excludedFileNamePattern `
                            -overrides $overridesArray `
                            -errorLevel $errorLevel `
                            -errorThreshold $errorThreshold `
                            -failOnPowerAppsCheckerAnalysisError $failOnPowerAppsCheckerAnalysisError `
                            -resultFileList $resultFileList `
                            -outputSummary $outputSummary
    }
    else {
        Write-VstsTaskError "Invalid files location option.  Valid options are Local Files and Sas Uri Files."
    }

    # Publish sarif result files as artifacts
    Publish-PACheckerResults -resultFiles $resultFileList -outputSummary $outputSummary -outputDirectory $outputDirectory.path -hasArtifactUpload $outputDirectory.hasArtifactFolder -artifactDestName $artifactDestName

} finally {
    if ($null -ne $redirector) {
        $redirector.Dispose()
    }
    Trace-VstsLeavingInvocation $MyInvocation
}

# SIG # Begin signature block
# MIInnAYJKoZIhvcNAQcCoIInjTCCJ4kCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCAiE20wg3sryOHP
# riOOPkHjwSTesvTTNA8ZAg8jyhmGm6CCDYEwggX/MIID56ADAgECAhMzAAACUosz
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
# BgEEAYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAvBgkqhkiG9w0BCQQxIgQgaEwU5ALR
# Gd5mQ7HWuk01i6vpQUntMOfwUmV10MVLHLYwNAYKKwYBBAGCNwIBDDEmMCSgEoAQ
# AFQAZQBzAHQAUwBpAGcAbqEOgAxodHRwOi8vdGVzdCAwDQYJKoZIhvcNAQEBBQAE
# ggEAyxqxBKTg3MqKol5yJp2SmaVoekjmdqiRz1wd5VjTEugq2iHoSuUSBJuErH9K
# EXgvmAYkkOPuzKYiFxtixgE8cfNysGPqxLRXbUNMWN0j2DTnwUqVe0KsJtYkj0nG
# 2YTati/nJVFO0CRRMCC4tAmyGuWhgO02As1Rwgwer/AqFU/msPjnWWNAwD3gbHUe
# X18HSyDbNcxH29vpiVo7UZc7X2e4vZ+GgBb+4O72FvvVPi368+36ChqNbhmxXTfS
# 4zzHdvurhEhW6owZkDk1j4davFo2+MHsq99+1G+72MVaxoOyswEwijNFcK7b6DGj
# iqGiUJKEVI7pEKC0en1Xj1JxAqGCFwkwghcFBgorBgEEAYI3AwMBMYIW9TCCFvEG
# CSqGSIb3DQEHAqCCFuIwghbeAgEDMQ8wDQYJYIZIAWUDBAIBBQAwggFVBgsqhkiG
# 9w0BCRABBKCCAUQEggFAMIIBPAIBAQYKKwYBBAGEWQoDATAxMA0GCWCGSAFlAwQC
# AQUABCDdtGvvLHN+2OEDM/Oxy/oBZn+oDQGGMZIFzWSN5QAaiAIGYrIsJNVdGBMy
# MDIyMDcwNzIxNDIyMy41MTNaMASAAgH0oIHUpIHRMIHOMQswCQYDVQQGEwJVUzET
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
# LwYJKoZIhvcNAQkEMSIEIFESgN8UGxnGBQGETcVtuBppRfDNsPbSwzyxd+viOeiE
# MIH6BgsqhkiG9w0BCRACLzGB6jCB5zCB5DCBvQQgSSgdPriMw1qh7p9PZqk1PLjo
# OrXsNMrtbkNIlPxSb2gwgZgwgYCkfjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMK
# V2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0
# IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0Eg
# MjAxMAITMwAAAa6qC1yzNKWVGgABAAABrjAiBCCZTHE8B4SxfhZ9EPr+c510YYOF
# TXOpjRivPcsmCdGy6jANBgkqhkiG9w0BAQsFAASCAgAnHS8yFUFCepu7bmZZMJ2V
# p4z55lSc8O5IC/1wzFWsqQlGJWfXCuojrxIbVNogSAt4aAZ47tWnUrnNcP04LRDc
# 50eIGW10Ey+zaytk2/Qnm1EAGkEafuqq9zcb607I6XCEmneB4zEITLqONoT3Gwo1
# tdCKkz9c1rTTsbcC+/Vr+9MqkzowOAUGlRCkK4BOwzkSFJRNHJt/Q4IcZO8YWKth
# Itil4JpvnBmepRvztdtXbtPBILpsmrfw9MuDDQQ8r31Rh+RjfeeZ+k5fOmNj2r7c
# 68vUbEN+nPwTBih1yp5Jz03MFbRC6S3jMniVTZfC/LcY6fr7Jsirtkpk5B3Dp1XZ
# qhWBJjFtZ2j9h9eA3SGDnNmmSG/e3KEy7ig7iDbzNCmMtxAW1Uba1O+aFSW8VwNb
# SwiAENqu4is5i7DFp61LWCtLHB1RjJ6ZI4gji6A+WK3Diqgrxz+ifduLAiAtP5f0
# /rEH038MNrz5ulQjxP9Io72dHe+hdaj3qx6HeOp9KwIjENuCE+unVQkzxIArvySc
# 2kkV3CP2N6eV8JdRGaNsNQusa6x+Ym8IDI9LMTyO1SERQbgEkqdO19x2BqVCULez
# sgdLusLEPZtRKi66hhLx/SFXFrvL7Kc/DjYBTdRNFF9FnPwzN4dnQfuLgZjnj2wj
# ZWkBCGs1O3dZNBXUPMhtlA==
# SIG # End signature block
