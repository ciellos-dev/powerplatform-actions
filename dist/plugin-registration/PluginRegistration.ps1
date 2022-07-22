[CmdletBinding()]

param(
	[parameter (Mandatory = $true)][string]$CrmConnectionString,
	[ValidateSet('Upsert','Reset','Delsert')]
    [parameter (Mandatory = $true)][string]$RegistrationType,
	[parameter (Mandatory = $true)][string]$AssemblyPath,
	[bool]$UseSplitAssembly,
	[string]$ProjectFilePath,
	[string]$MappingFile,
	[string]$SolutionName,
	[parameter (Mandatory = $true)][int]$CrmConnectionTimeout
)

$ErrorActionPreference = "Stop"

Write-Verbose 'Entering PluginRegistration.ps1'

#Get Parameters
$crmConnectionTimeout = Get-VstsInput -Name crmConnectionTimeout -Require -AsInt

#Print Verbose
Write-Verbose "crmConnectionString = $CrmConnectionString"
Write-Verbose "registrationType = $RegistrationType"
Write-Verbose "assemblyPath = $AssemblyPath"
Write-Verbose "projectFilePath = $ProjectFilePath"
Write-Verbose "useSplitAssembly = $UseSplitAssembly"
Write-Verbose "MappingFile = $MappingFile"
Write-Verbose "solutionName = $SolutionName"
Write-Verbose "crmConnectionTimeout = $CrmConnectionTimeout"


& "$PSScriptRoot\..\dist\ps_modules\lib\xRMCIFramework\9.0.0\PluginRegistration.ps1" -CrmConnectionString $CrmConnectionString -RegistrationType $RegistrationType -AssemblyPath $AssemblyPath -MappingFile $MappingFile -SolutionName $SolutionName -useSplitAssembly $UseSplitAssembly -projectFilePath $ProjectFilePath -Timeout $CrmConnectionTimeout

Write-Verbose 'Leaving MSCRMPluginRegistration.ps1'