[CmdletBinding()]

param(
	[string]$CrmConnectionString,
	[ValidateSet('Upsert','Reset','Delsert')]
    [string]$RegistrationType,
	[string]$AssemblyPath,
	[bool]$UseSplitAssembly,
	[string]$ProjectFilePath,
	[string]$MappingFile,
	[string]$SolutionName,
	[int]$CrmConnectionTimeout
)

$ErrorActionPreference = "Stop"

Write-Verbose 'Entering PluginRegistration.ps1'

#Print Verbose
Write-Verbose "crmConnectionString = $CrmConnectionString"
Write-Verbose "registrationType = $RegistrationType"
Write-Verbose "assemblyPath = $AssemblyPath"
Write-Verbose "projectFilePath = $ProjectFilePath"
Write-Verbose "useSplitAssembly = $UseSplitAssembly"
Write-Verbose "MappingFile = $MappingFile"
Write-Verbose "solutionName = $SolutionName"
Write-Verbose "crmConnectionTimeout = $CrmConnectionTimeout"


& "$PSScriptRoot\..\ps_modules\lib\xRMCIFramework\9.0.0\PluginRegistration.ps1" -CrmConnectionString $CrmConnectionString -RegistrationType $RegistrationType -AssemblyPath $AssemblyPath -MappingFile $MappingFile -SolutionName $SolutionName -useSplitAssembly $UseSplitAssembly -projectFilePath $ProjectFilePath -Timeout $CrmConnectionTimeout

Write-Verbose 'Leaving MSCRMPluginRegistration.ps1'