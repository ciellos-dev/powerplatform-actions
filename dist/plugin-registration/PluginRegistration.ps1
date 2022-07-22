[CmdletBinding()]

param(
	[Parameter()]
	[string]$CrmConnectionString,
    [ValidateSet('Upsert','Reset','Delsert')][string]$RegistrationType,
	[string]$AssemblyPath,
	[string]$UseSplitAssembly,
	[string]$ProjectFilePath,
	[string]$MappingFile,
	[string]$SolutionName,
	[string]$CrmConnectionTimeout
)

$ErrorActionPreference = "Stop"

Write-Verbose 'Entering PluginRegistration.ps1'

#Print Verbose
Write-Host "crmConnectionString = " $CrmConnectionString
Write-Host "registrationType = " $RegistrationType
Write-Host "assemblyPath = " $AssemblyPath
Write-Host "projectFilePath = " $ProjectFilePath
Write-Host "useSplitAssembly = " $UseSplitAssembly
Write-Host "MappingFile = " $MappingFile
Write-Host "solutionName = " $SolutionName
Write-Host "crmConnectionTimeout = " $CrmConnectionTimeout


& "$PSScriptRoot\..\ps_modules\lib\xRMCIFramework\9.0.0\PluginRegistration.ps1" -CrmConnectionString "$CrmConnectionString" -RegistrationType "$RegistrationType" -AssemblyPath "$AssemblyPath" -MappingFile "$MappingFile" -SolutionName "$SolutionName" -useSplitAssembly $UseSplitAssembly -projectFilePath "$ProjectFilePath" -Timeout $CrmConnectionTimeout

Write-Verbose 'Leaving MSCRMPluginRegistration.ps1'