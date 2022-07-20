<#
.SYNOPSIS
Gets assembly reference information.

.DESCRIPTION
Not supported for use during task execution. This function is only intended to help developers resolve the minimal set of DLLs that need to be bundled when consuming the VSTS REST SDK or TFS Extended Client SDK. The interface and output may change between patch releases of the VSTS Task SDK.

Only a subset of the referenced assemblies may actually be required, depending on the functionality used by your task. It is best to bundle only the DLLs required for your scenario.

Walks an assembly's references to determine all of it's dependencies. Also walks the references of the dependencies, and so on until all nested dependencies have been traversed. Dependencies are searched for in the directory of the specified assembly. NET Framework assemblies are omitted.

See https://github.com/Microsoft/vsts-task-lib/tree/master/powershell/Docs/UsingOM.md for reliable usage when working with the TFS extended client SDK from a task.

.PARAMETER LiteralPath
Assembly to walk.

.EXAMPLE
Get-VstsAssemblyReference -LiteralPath C:\nuget\microsoft.teamfoundationserver.client.14.102.0\lib\net45\Microsoft.TeamFoundation.Build2.WebApi.dll
#>
function Get-AssemblyReference {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$LiteralPath)

    $ErrorActionPreference = 'Stop'
    Write-Warning "Not supported for use during task execution. This function is only intended to help developers resolve the minimal set of DLLs that need to be bundled when consuming the VSTS REST SDK or TFS Extended Client SDK. The interface and output may change between patch releases of the VSTS Task SDK."
    Write-Output ''
    Write-Warning "Only a subset of the referenced assemblies may actually be required, depending on the functionality used by your task. It is best to bundle only the DLLs required for your scenario."
    $directory = [System.IO.Path]::GetDirectoryName($LiteralPath)
    $hashtable = @{ }
    $queue = @( [System.Reflection.Assembly]::ReflectionOnlyLoadFrom($LiteralPath).GetName() )
    while ($queue.Count) {
        # Add a blank line between assemblies.
        Write-Output ''

        # Pop.
        $assemblyName = $queue[0]
        $queue = @( $queue | Select-Object -Skip 1 )

        # Attempt to find the assembly in the same directory.
        $assembly = $null
        $path = "$directory\$($assemblyName.Name).dll"
        if ((Test-Path -LiteralPath $path -PathType Leaf)) {
            $assembly = [System.Reflection.Assembly]::ReflectionOnlyLoadFrom($path)
        } else {
            $path = "$directory\$($assemblyName.Name).exe"
            if ((Test-Path -LiteralPath $path -PathType Leaf)) {
                $assembly = [System.Reflection.Assembly]::ReflectionOnlyLoadFrom($path)
            }
        }

        # Make sure the assembly full name matches, not just the file name.
        if ($assembly -and $assembly.GetName().FullName -ne $assemblyName.FullName) {
            $assembly = $null
        }

        # Print the assembly.
        if ($assembly) {
            Write-Output $assemblyName.FullName
        } else {
            if ($assemblyName.FullName -eq 'Newtonsoft.Json, Version=6.0.0.0, Culture=neutral, PublicKeyToken=30ad4fe6b2a6aeed') {
                Write-Warning "*** NOT FOUND $($assemblyName.FullName) *** This is an expected condition when using the HTTP clients from the 15.x VSTS REST SDK. Use Get-VstsVssHttpClient to load the HTTP clients (which applies a binding redirect assembly resolver for Newtonsoft.Json). Otherwise you will need to manage the binding redirect yourself."
            } else {
                Write-Warning "*** NOT FOUND $($assemblyName.FullName) ***"
            }
    
            continue
        }

        # Walk the references.
        $refAssemblyNames = @( $assembly.GetReferencedAssemblies() )
        for ($i = 0 ; $i -lt $refAssemblyNames.Count ; $i++) {
            $refAssemblyName = $refAssemblyNames[$i]

            # Skip framework assemblies.
            $fxPaths = @(
                "$env:windir\Microsoft.Net\Framework64\v4.0.30319\$($refAssemblyName.Name).dll"
                "$env:windir\Microsoft.Net\Framework64\v4.0.30319\WPF\$($refAssemblyName.Name).dll"
            )
            $fxPath = $fxPaths |
                Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
                Where-Object { [System.Reflection.Assembly]::ReflectionOnlyLoadFrom($_).GetName().FullName -eq $refAssemblyName.FullName }
            if ($fxPath) {
                continue
            }

            # Print the reference.
            Write-Output "    $($refAssemblyName.FullName)"

            # Add new references to the queue.
            if (!$hashtable[$refAssemblyName.FullName]) {
                $queue += $refAssemblyName
                $hashtable[$refAssemblyName.FullName] = $true
            }
        }
    }
}

<#
.SYNOPSIS
Gets a credentials object that can be used with the TFS extended client SDK.

.DESCRIPTION
The agent job token is used to construct the credentials object. The identity associated with the token depends on the scope selected in the build/release definition (either the project collection build/release service identity, or the project build/release service identity).

Refer to Get-VstsTfsService for a more simple to get a TFS service object.

*** DO NOT USE Agent.ServerOMDirectory *** See https://github.com/Microsoft/vsts-task-lib/tree/master/powershell/Docs/UsingOM.md for reliable usage when working with the TFS extended client SDK from a task.

.PARAMETER OMDirectory
Directory where the extended client object model DLLs are located. If the DLLs for the credential types are not already loaded, an attempt will be made to automatically load the required DLLs from the object model directory.

If not specified, defaults to the directory of the entry script for the task.

*** DO NOT USE Agent.ServerOMDirectory *** See https://github.com/Microsoft/vsts-task-lib/tree/master/powershell/Docs/UsingOM.md for reliable usage when working with the TFS extended client SDK from a task.

.EXAMPLE
#
# Refer to Get-VstsTfsService for a more simple way to get a TFS service object.
#
$credentials = Get-VstsTfsClientCredentials
Add-Type -LiteralPath "$PSScriptRoot\Microsoft.TeamFoundation.VersionControl.Client.dll"
$tfsTeamProjectCollection = New-Object Microsoft.TeamFoundation.Client.TfsTeamProjectCollection(
    (Get-ActionInput -Name 'System.TeamFoundationCollectionUri' -Require),
    $credentials)
$versionControlServer = $tfsTeamProjectCollection.GetService([Microsoft.TeamFoundation.VersionControl.Client.VersionControlServer])
$versionControlServer.GetItems('$/*').Items | Format-List
#>
function Get-TfsClientCredentials {
    [CmdletBinding()]
    param([string]$OMDirectory)

    Trace-EnteringInvocation -InvocationInfo $MyInvocation
    $originalErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Stop'

        # Get the endpoint.
        $endpoint = Get-Endpoint -Name SystemVssConnection -Require

        # Validate the type can be found.
        $null = Get-OMType -TypeName 'Microsoft.TeamFoundation.Client.TfsClientCredentials' -OMKind 'ExtendedClient' -OMDirectory $OMDirectory -Require

        # Construct the credentials.
        $credentials = New-Object Microsoft.TeamFoundation.Client.TfsClientCredentials($false) # Do not use default credentials.
        $credentials.AllowInteractive = $false
        $credentials.Federated = New-Object Microsoft.TeamFoundation.Client.OAuthTokenCredential([string]$endpoint.auth.parameters.AccessToken)
        return $credentials
    } catch {
        $ErrorActionPreference = $originalErrorActionPreference
        Write-Error $_
    } finally {
        Trace-LeavingInvocation -InvocationInfo $MyInvocation
    }
}

<#
.SYNOPSIS
Gets a TFS extended client service.

.DESCRIPTION
Gets an instance of an ITfsTeamProjectCollectionObject.

*** DO NOT USE Agent.ServerOMDirectory *** See https://github.com/Microsoft/vsts-task-lib/tree/master/powershell/Docs/UsingOM.md for reliable usage when working with the TFS extended client SDK from a task.

.PARAMETER TypeName
Namespace-qualified type name of the service to get.

.PARAMETER OMDirectory
Directory where the extended client object model DLLs are located. If the DLLs for the types are not already loaded, an attempt will be made to automatically load the required DLLs from the object model directory.

If not specified, defaults to the directory of the entry script for the task.

*** DO NOT USE Agent.ServerOMDirectory *** See https://github.com/Microsoft/vsts-task-lib/tree/master/powershell/Docs/UsingOM.md for reliable usage when working with the TFS extended client SDK from a task.

.PARAMETER Uri
URI to use when initializing the service. If not specified, defaults to System.TeamFoundationCollectionUri.

.PARAMETER TfsClientCredentials
Credentials to use when initializing the service. If not specified, the default uses the agent job token to construct the credentials object. The identity associated with the token depends on the scope selected in the build/release definition (either the project collection build/release service identity, or the project build/release service identity).

.EXAMPLE
$versionControlServer = Get-VstsTfsService -TypeName Microsoft.TeamFoundation.VersionControl.Client.VersionControlServer
$versionControlServer.GetItems('$/*').Items | Format-List
#>
function Get-TfsService {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TypeName,

        [string]$OMDirectory,

        [string]$Uri,

        $TfsClientCredentials)

    Trace-EnteringInvocation -InvocationInfo $MyInvocation
    $originalErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Stop'

        # Default the URI to the collection URI.
        if (!$Uri) {
            $Uri = Get-TaskVariable -Name System.TeamFoundationCollectionUri -Require
        }

        # Default the credentials.
        if (!$TfsClientCredentials) {
            $TfsClientCredentials = Get-TfsClientCredentials -OMDirectory $OMDirectory
        }

        # Validate the project collection type can be loaded.
        $null = Get-OMType -TypeName 'Microsoft.TeamFoundation.Client.TfsTeamProjectCollection' -OMKind 'ExtendedClient' -OMDirectory $OMDirectory -Require

        # Load the project collection object.
        $tfsTeamProjectCollection = New-Object Microsoft.TeamFoundation.Client.TfsTeamProjectCollection($Uri, $TfsClientCredentials)

        # Validate the requested type can be loaded.
        $type = Get-OMType -TypeName $TypeName -OMKind 'ExtendedClient' -OMDirectory $OMDirectory -Require

        # Return the service object.
        return $tfsTeamProjectCollection.GetService($type)
    } catch {
        $ErrorActionPreference = $originalErrorActionPreference
        Write-Error $_
    } finally {
        Trace-LeavingInvocation -InvocationInfo $MyInvocation
    }
}

<#
.SYNOPSIS
Gets a credentials object that can be used with the VSTS REST SDK.

.DESCRIPTION
The agent job token is used to construct the credentials object. The identity associated with the token depends on the scope selected in the build/release definition (either the project collection build/release service identity, or the project service build/release identity).

Refer to Get-VstsVssHttpClient for a more simple to get a VSS HTTP client.

*** DO NOT USE Agent.ServerOMDirectory *** See https://github.com/Microsoft/vsts-task-lib/tree/master/powershell/Docs/UsingOM.md for reliable usage when working with the VSTS REST SDK from a task.

.PARAMETER OMDirectory
Directory where the REST client object model DLLs are located. If the DLLs for the credential types are not already loaded, an attempt will be made to automatically load the required DLLs from the object model directory.

If not specified, defaults to the directory of the entry script for the task.

*** DO NOT USE Agent.ServerOMDirectory *** See https://github.com/Microsoft/vsts-task-lib/tree/master/powershell/Docs/UsingOM.md for reliable usage when working with the VSTS REST SDK from a task.

.EXAMPLE
#
# Refer to Get-VstsTfsService for a more simple way to get a TFS service object.
#
# This example works using the 14.x .NET SDK. A Newtonsoft.Json 6.0 to 8.0 binding
# redirect may be required when working with the 15.x SDK. Or use Get-VstsVssHttpClient
# to avoid managing the binding redirect.
#
$vssCredentials = Get-VstsVssCredentials
$collectionUrl = New-Object System.Uri((Get-ActionInput -Name 'System.TeamFoundationCollectionUri' -Require))
Add-Type -LiteralPath "$PSScriptRoot\Microsoft.TeamFoundation.Core.WebApi.dll"
$projectHttpClient = New-Object Microsoft.TeamFoundation.Core.WebApi.ProjectHttpClient($collectionUrl, $vssCredentials)
$projectHttpClient.GetProjects().Result
#>
function Get-VssCredentials {
    [CmdletBinding()]
    param([string]$OMDirectory)

    Trace-EnteringInvocation -InvocationInfo $MyInvocation
    $originalErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Stop'

        # Get the endpoint.
        $endpoint = Get-Endpoint -Name SystemVssConnection -Require

        # Check if the VssOAuthAccessTokenCredential type is available.
        if ((Get-OMType -TypeName 'Microsoft.VisualStudio.Services.OAuth.VssOAuthAccessTokenCredential' -OMKind 'WebApi' -OMDirectory $OMDirectory)) {
            # Create the federated credential.
            $federatedCredential = New-Object Microsoft.VisualStudio.Services.OAuth.VssOAuthAccessTokenCredential($endpoint.auth.parameters.AccessToken)
        } else {
            # Validate the fallback type can be loaded.
            $null = Get-OMType -TypeName 'Microsoft.VisualStudio.Services.Client.VssOAuthCredential' -OMKind 'WebApi' -OMDirectory $OMDirectory -Require

            # Create the federated credential.
            $federatedCredential = New-Object Microsoft.VisualStudio.Services.Client.VssOAuthCredential($endpoint.auth.parameters.AccessToken)
        }

        # Return the credentials.
        return New-Object Microsoft.VisualStudio.Services.Common.VssCredentials(
            (New-Object Microsoft.VisualStudio.Services.Common.WindowsCredential($false)), # Do not use default credentials.
            $federatedCredential,
            [Microsoft.VisualStudio.Services.Common.CredentialPromptType]::DoNotPrompt)
    } catch {
        $ErrorActionPreference = $originalErrorActionPreference
        Write-Error $_
    } finally {
        Trace-LeavingInvocation -InvocationInfo $MyInvocation
    }
}

<#
.SYNOPSIS
Gets a VSS HTTP client.

.DESCRIPTION
Gets an instance of an VSS HTTP client.

*** DO NOT USE Agent.ServerOMDirectory *** See https://github.com/Microsoft/vsts-task-lib/tree/master/powershell/Docs/UsingOM.md for reliable usage when working with the VSTS REST SDK from a task.

.PARAMETER TypeName
Namespace-qualified type name of the HTTP client to get.

.PARAMETER OMDirectory
Directory where the REST client object model DLLs are located. If the DLLs for the credential types are not already loaded, an attempt will be made to automatically load the required DLLs from the object model directory.

If not specified, defaults to the directory of the entry script for the task.

*** DO NOT USE Agent.ServerOMDirectory *** See https://github.com/Microsoft/vsts-task-lib/tree/master/powershell/Docs/UsingOM.md for reliable usage when working with the VSTS REST SDK from a task.

# .PARAMETER Uri
# URI to use when initializing the HTTP client. If not specified, defaults to System.TeamFoundationCollectionUri.

# .PARAMETER VssCredentials
# Credentials to use when initializing the HTTP client. If not specified, the default uses the agent job token to construct the credentials object. The identity associated with the token depends on the scope selected in the build/release definition (either the project collection build/release service identity, or the project build/release service identity).

# .PARAMETER WebProxy
# WebProxy to use when initializing the HTTP client. If not specified, the default uses the proxy configuration agent current has.

# .PARAMETER ClientCert
# ClientCert to use when initializing the HTTP client. If not specified, the default uses the client certificate agent current has.

# .PARAMETER IgnoreSslError
# Skip SSL server certificate validation on all requests made by this HTTP client. If not specified, the default is to validate SSL server certificate.

.EXAMPLE
$projectHttpClient = Get-VstsVssHttpClient -TypeName Microsoft.TeamFoundation.Core.WebApi.ProjectHttpClient
$projectHttpClient.GetProjects().Result
#>
function Get-VssHttpClient {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TypeName,

        [string]$OMDirectory,

        [string]$Uri,

        $VssCredentials,
        
        $WebProxy = (Get-WebProxy),
        
        $ClientCert = (Get-ClientCertificate),
        
        [switch]$IgnoreSslError)

    Trace-EnteringInvocation -InvocationInfo $MyInvocation
    $originalErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Stop'

        # Default the URI to the collection URI.
        if (!$Uri) {
            $Uri = Get-TaskVariable -Name System.TeamFoundationCollectionUri -Require
        }

        # Cast the URI.
        [uri]$Uri = New-Object System.Uri($Uri)

        # Default the credentials.
        if (!$VssCredentials) {
            $VssCredentials = Get-VssCredentials -OMDirectory $OMDirectory
        }

        # Validate the type can be loaded.
        $null = Get-OMType -TypeName $TypeName -OMKind 'WebApi' -OMDirectory $OMDirectory -Require

        # Update proxy setting for vss http client
        [Microsoft.VisualStudio.Services.Common.VssHttpMessageHandler]::DefaultWebProxy = $WebProxy
        
        # Update client certificate setting for vss http client
        $null = Get-OMType -TypeName 'Microsoft.VisualStudio.Services.Common.VssHttpRequestSettings' -OMKind 'WebApi' -OMDirectory $OMDirectory -Require
        $null = Get-OMType -TypeName 'Microsoft.VisualStudio.Services.WebApi.VssClientHttpRequestSettings' -OMKind 'WebApi' -OMDirectory $OMDirectory -Require
        [Microsoft.VisualStudio.Services.Common.VssHttpRequestSettings]$Settings = [Microsoft.VisualStudio.Services.WebApi.VssClientHttpRequestSettings]::Default.Clone()

        if ($ClientCert) {
            $null = Get-OMType -TypeName 'Microsoft.VisualStudio.Services.WebApi.VssClientCertificateManager' -OMKind 'WebApi' -OMDirectory $OMDirectory -Require
            $null = [Microsoft.VisualStudio.Services.WebApi.VssClientCertificateManager]::Instance.ClientCertificates.Add($ClientCert)
            
            $Settings.ClientCertificateManager = [Microsoft.VisualStudio.Services.WebApi.VssClientCertificateManager]::Instance
        }        

        # Skip SSL server certificate validation
        [bool]$SkipCertValidation = (Get-TaskVariable -Name Agent.SkipCertValidation -AsBool) -or $IgnoreSslError
        if ($SkipCertValidation) {
            if ($Settings.GetType().GetProperty('ServerCertificateValidationCallback')) {
                Write-Verbose "Ignore any SSL server certificate validation errors.";
                $Settings.ServerCertificateValidationCallback = [VstsTaskSdk.VstsHttpHandlerSettings]::UnsafeSkipServerCertificateValidation
            }
            else {
                # OMDirectory has older version of Microsoft.VisualStudio.Services.Common.dll
                Write-Verbose "The version of 'Microsoft.VisualStudio.Services.Common.dll' does not support skip SSL server certificate validation."
            }
        }

        # Try to construct the HTTP client.
        Write-Verbose "Constructing HTTP client."
        try {
            return New-Object $TypeName($Uri, $VssCredentials, $Settings)
        } catch {
            # Rethrow if the exception is not due to Newtonsoft.Json DLL not found.
            if ($_.Exception.InnerException -isnot [System.IO.FileNotFoundException] -or
                $_.Exception.InnerException.FileName -notlike 'Newtonsoft.Json, *') {

                throw
            }

            # Default the OMDirectory to the directory of the entry script for the task.
            if (!$OMDirectory) {
                $OMDirectory = [System.IO.Path]::GetFullPath("$PSScriptRoot\..\..")
                Write-Verbose "Defaulted OM directory to: '$OMDirectory'"
            }

            # Test if the Newtonsoft.Json DLL exists in the OM directory.
            $newtonsoftDll = [System.IO.Path]::Combine($OMDirectory, "Newtonsoft.Json.dll")
            Write-Verbose "Testing file path: '$newtonsoftDll'"
            if (!(Test-Path -LiteralPath $newtonsoftDll -PathType Leaf)) {
                Write-Verbose 'Not found. Rethrowing exception.'
                throw
            }

            # Add a binding redirect and try again. Parts of the Dev15 preview SDK have a
            # dependency on the 6.0.0.0 Newtonsoft.Json DLL, while other parts reference
            # the 8.0.0.0 Newtonsoft.Json DLL.
            Write-Verbose "Adding assembly resolver."
            $onAssemblyResolve = [System.ResolveEventHandler] {
                param($sender, $e)

                if ($e.Name -like 'Newtonsoft.Json, *') {
                    Write-Verbose "Resolving '$($e.Name)'"
                    return [System.Reflection.Assembly]::LoadFrom($newtonsoftDll)
                }

                Write-Verbose "Unable to resolve assembly name '$($e.Name)'"
                return $null
            }
            [System.AppDomain]::CurrentDomain.add_AssemblyResolve($onAssemblyResolve)
            try {
                # Try again to construct the HTTP client.
                Write-Verbose "Trying again to construct the HTTP client."
                return New-Object $TypeName($Uri, $VssCredentials, $Settings)
            } finally {
                # Unregister the assembly resolver.
                Write-Verbose "Removing assemlby resolver."
                [System.AppDomain]::CurrentDomain.remove_AssemblyResolve($onAssemblyResolve)
            }
        }
    } catch {
        $ErrorActionPreference = $originalErrorActionPreference
        Write-Error $_
    } finally {
        Trace-LeavingInvocation -InvocationInfo $MyInvocation
    }
}

<#
.SYNOPSIS
Gets a VstsTaskSdk.VstsWebProxy

.DESCRIPTION
Gets an instance of a VstsTaskSdk.VstsWebProxy that has same proxy configuration as Build/Release agent.

VstsTaskSdk.VstsWebProxy implement System.Net.IWebProxy interface.

.EXAMPLE
$webProxy = Get-VstsWebProxy
$webProxy.GetProxy(New-Object System.Uri("https://github.com/Microsoft/vsts-task-lib"))
#>
function Get-WebProxy {
    [CmdletBinding()]
    param()

    Trace-EnteringInvocation -InvocationInfo $MyInvocation
    try {
        # Min agent version that supports proxy
        Assert-Agent -Minimum '2.105.7'

        $proxyUrl = Get-TaskVariable -Name Agent.ProxyUrl
        $proxyUserName = Get-TaskVariable -Name Agent.ProxyUserName
        $proxyPassword = Get-TaskVariable -Name Agent.ProxyPassword
        $proxyBypassListJson = Get-TaskVariable -Name Agent.ProxyBypassList
        [string[]]$ProxyBypassList = ConvertFrom-Json -InputObject $ProxyBypassListJson
        
        return New-Object -TypeName VstsTaskSdk.VstsWebProxy -ArgumentList @($proxyUrl, $proxyUserName, $proxyPassword, $proxyBypassList)
    }
    finally {
        Trace-LeavingInvocation -InvocationInfo $MyInvocation
    }
}

<#
.SYNOPSIS
Gets a client certificate for current connected TFS instance

.DESCRIPTION
Gets an instance of a X509Certificate2 that is the client certificate Build/Release agent used.

.EXAMPLE
$x509cert = Get-ClientCertificate
WebRequestHandler.ClientCertificates.Add(x509cert)
#>
function Get-ClientCertificate {
    [CmdletBinding()]
    param()

    Trace-EnteringInvocation -InvocationInfo $MyInvocation
    try {
        # Min agent version that supports client certificate
        Assert-Agent -Minimum '2.122.0'

        [string]$clientCert = Get-TaskVariable -Name Agent.ClientCertArchive
        [string]$clientCertPassword = Get-TaskVariable -Name Agent.ClientCertPassword
        
        if ($clientCert -and (Test-Path -LiteralPath $clientCert -PathType Leaf)) {
            return New-Object -TypeName System.Security.Cryptography.X509Certificates.X509Certificate2 -ArgumentList @($clientCert, $clientCertPassword)
        }        
    }
    finally {
        Trace-LeavingInvocation -InvocationInfo $MyInvocation
    }
}

########################################
# Private functions.
########################################
function Get-OMType {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TypeName,

        [ValidateSet('ExtendedClient', 'WebApi')]
        [Parameter(Mandatory = $true)]
        [string]$OMKind,

        [string]$OMDirectory,

        [switch]$Require)

    Trace-EnteringInvocation -InvocationInfo $MyInvocation
    try {
        # Default the OMDirectory to the directory of the entry script for the task.
        if (!$OMDirectory) {
            $OMDirectory = [System.IO.Path]::GetFullPath("$PSScriptRoot\..\..")
            Write-Verbose "Defaulted OM directory to: '$OMDirectory'"
        }

        # Try to load the type.
        $errorRecord = $null
        Write-Verbose "Testing whether type can be loaded: '$TypeName'"
        $ErrorActionPreference = 'Ignore'
        try {
            # Failure when attempting to cast a string to a type, transfers control to the
            # catch handler even when the error action preference is ignore. The error action
            # is set to Ignore so the $Error variable is not polluted.
            $type = [type]$TypeName

            # Success.
            Write-Verbose "The type was loaded successfully."
            return $type
        } catch {
            # Store the error record.
            $errorRecord = $_
        }

        $ErrorActionPreference = 'Stop'
        Write-Verbose "The type was not loaded."

        # Build a list of candidate DLL file paths from the namespace.
        $dllPaths = @( )
        $namespace = $TypeName
        while ($namespace.LastIndexOf('.') -gt 0) {
            # Trim the next segment from the namespace.
            $namespace = $namespace.SubString(0, $namespace.LastIndexOf('.'))

            # Derive potential DLL file paths based on the namespace and OM kind (i.e. extended client vs web API).
            if ($OMKind -eq 'ExtendedClient') {
                if ($namespace -like 'Microsoft.TeamFoundation.*') {
                    $dllPaths += [System.IO.Path]::Combine($OMDirectory, "$namespace.dll")
                }
            } else {
                if ($namespace -like 'Microsoft.TeamFoundation.*' -or
                    $namespace -like 'Microsoft.VisualStudio.Services' -or
                    $namespace -like 'Microsoft.VisualStudio.Services.*') {

                    $dllPaths += [System.IO.Path]::Combine($OMDirectory, "$namespace.WebApi.dll")
                    $dllPaths += [System.IO.Path]::Combine($OMDirectory, "$namespace.dll")
                }
            }
        }

        foreach ($dllPath in $dllPaths) {
            # Check whether the DLL exists.
            Write-Verbose "Testing leaf path: '$dllPath'"
            if (!(Test-Path -PathType Leaf -LiteralPath "$dllPath")) {
                Write-Verbose "Not found."
                continue
            }

            # Load the DLL.
            Write-Verbose "Loading assembly: $dllPath"
            try {
                Add-Type -LiteralPath $dllPath
            } catch {
                # Write the information to the verbose stream and proceed to attempt to load the requested type.
                #
                # The requested type may successfully load now. For example, the type used with the 14.0 Web API for the
                # federated credential (VssOAuthCredential) resides in Microsoft.VisualStudio.Services.Client.dll. Even
                # though loading the DLL results in a ReflectionTypeLoadException when Microsoft.ServiceBus.dll (approx 3.75mb)
                # is not present, enough types are loaded to use the VssOAuthCredential federated credential with the Web API
                # HTTP clients.
                Write-Verbose "$($_.Exception.GetType().FullName): $($_.Exception.Message)"
                if ($_.Exception -is [System.Reflection.ReflectionTypeLoadException]) {
                    for ($i = 0 ; $i -lt $_.Exception.LoaderExceptions.Length ; $i++) {
                        $loaderException = $_.Exception.LoaderExceptions[$i]
                        Write-Verbose "LoaderExceptions[$i]: $($loaderException.GetType().FullName): $($loaderException.Message)"
                    }
                }
            }

            # Try to load the type.
            Write-Verbose "Testing whether type can be loaded: '$TypeName'"
            $ErrorActionPreference = 'Ignore'
            try {
                # Failure when attempting to cast a string to a type, transfers control to the
                # catch handler even when the error action preference is ignore. The error action
                # is set to Ignore so the $Error variable is not polluted.
                $type = [type]$TypeName

                # Success.
                Write-Verbose "The type was loaded successfully."
                return $type
            } catch {
                $errorRecord = $_
            }

            $ErrorActionPreference = 'Stop'
            Write-Verbose "The type was not loaded."
        }

        # Check whether to propagate the error.
        if ($Require) {
            Write-Error $errorRecord
        }
    } finally {
        Trace-LeavingInvocation -InvocationInfo $MyInvocation
    }
}

# SIG # Begin signature block
# MIInnwYJKoZIhvcNAQcCoIInkDCCJ4wCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDHnexhTvdi65ta
# GC2EoafY//c7J46ZI88EwI2sfoBaAqCCDYEwggX/MIID56ADAgECAhMzAAACUosz
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
# BgEEAYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAvBgkqhkiG9w0BCQQxIgQgkBXrdJYV
# xlW9WevRPbyUrdEHJSyYEY2EaCYjZYk11xEwNAYKKwYBBAGCNwIBDDEmMCSgEoAQ
# AFQAZQBzAHQAUwBpAGcAbqEOgAxodHRwOi8vdGVzdCAwDQYJKoZIhvcNAQEBBQAE
# ggEAqIKpEP2MfKGqYWBrdh7AGr38jWc57CLcR1TCtNvEevrVM86qIXOajjJGO8tl
# 4RX4bubLtfsgufyytgz7jSIhSqf4cIEK6/zRCtKVmJ91VPFeQClOxFG9UemAOl/m
# SDt7PEofsXgum+XiK22ITA6T+0OfF2j2XwuFntObuvTYs/BrfVTxwjFQHC1IRBKX
# 55gGGwi9DthCDt6WhNLE6cEAb7Qf5gZDJscllep3l+gMi6u1IK/mMqweq9HnJZ36
# 2VEQG0aY0Z68REWUoTEgosUEJDgWJjmx9/EpjJMMV93vjnR24idXubSkWArDbyAO
# H2jopPm6ceJnpM9rG9YhzRV4bKGCFwwwghcIBgorBgEEAYI3AwMBMYIW+DCCFvQG
# CSqGSIb3DQEHAqCCFuUwghbhAgEDMQ8wDQYJYIZIAWUDBAIBBQAwggFVBgsqhkiG
# 9w0BCRABBKCCAUQEggFAMIIBPAIBAQYKKwYBBAGEWQoDATAxMA0GCWCGSAFlAwQC
# AQUABCB5MgrLVvbWE+1J7ogjVXygJa4oxbImD9/uN8OQCE9deQIGYrHNUbPLGBMy
# MDIyMDcwNzIxNDIyNC4zNTlaMASAAgH0oIHUpIHRMIHOMQswCQYDVQQGEwJVUzET
# MBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMV
# TWljcm9zb2Z0IENvcnBvcmF0aW9uMSkwJwYDVQQLEyBNaWNyb3NvZnQgT3BlcmF0
# aW9ucyBQdWVydG8gUmljbzEmMCQGA1UECxMdVGhhbGVzIFRTUyBFU046NjBCQy1F
# MzgzLTI2MzUxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2Wg
# ghFfMIIHEDCCBPigAwIBAgITMwAAAaZZRYM5TZ7rSwABAAABpjANBgkqhkiG9w0B
# AQsFADB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UE
# BxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYD
# VQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDAeFw0yMjAzMDIxODUx
# MjFaFw0yMzA1MTExODUxMjFaMIHOMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2Fz
# aGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENv
# cnBvcmF0aW9uMSkwJwYDVQQLEyBNaWNyb3NvZnQgT3BlcmF0aW9ucyBQdWVydG8g
# UmljbzEmMCQGA1UECxMdVGhhbGVzIFRTUyBFU046NjBCQy1FMzgzLTI2MzUxJTAj
# BgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2UwggIiMA0GCSqGSIb3
# DQEBAQUAA4ICDwAwggIKAoICAQDZmL97UiPnyfzUCZ48+ybwp3Pl5tKyqHvWCg+D
# LzGArpe3oHa0/87+bxW0IIzUO+Ou9nzcHms7ZEeuVfMtvbuTy9rH9NafrnIXtGbu
# LUooPhrEOmUJfbYz0QGP9yEwRw3iGMr6vFp3vfuzaDy4cQ0junbV+2ArkOM3Ez90
# hOjLweG+TYoIXbb6GVWmJNZV6Y1E33ZiqF9QAatbCW1C0p0otEHeL75d5mfY8cL/
# XUf55WT+tpa2WGauyz7Rw+gZZnJQeT0/PQ50ptbI2mZxR6yszrJquRpZi+UhboAg
# mTqCs9d9xSXkGhTHFwWUgkIzQAVgWxyEQhNcrBxxvNw3aJ0ZpwvBDpWHkcE1s/0A
# s+qtK4jiG2MgvwNgYFBKbvf/RMpq07MjK9v80vBnRMm0OVu39Fq3K5igf2OtvoOk
# 5nzkvDbVPi9YxqCjRukOUZXycGbvCf0PXZeDschyrsu/PsJuh7Be7gIs6bFoet1F
# GqCvzhkIgRtzSfpHn+XlqZ72uGSX4QJ6mEwGQ9bh4H/FX0I55dAQdmF8yvVmk6nX
# vHfvKgsVSq+YSWL2zvl9/tpOTwoq1Cv0m6K3l/sVIVWkBIVQ2KpWrcj7bSO2diK5
# ITM8Bb3PqdEHsjIjZqNnAWXo8fInAznFIncMpg1GKhjxOzAPL7Slt33nkkmCbAhJ
# LlDv7wIDAQABo4IBNjCCATIwHQYDVR0OBBYEFDpUITv8xpaivfVJDS/xrvwK8jfY
# MB8GA1UdIwQYMBaAFJ+nFV0AXmJdg/Tl0mWnG1M1GelyMF8GA1UdHwRYMFYwVKBS
# oFCGTmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY3JsL01pY3Jvc29m
# dCUyMFRpbWUtU3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNybDBsBggrBgEFBQcBAQRg
# MF4wXAYIKwYBBQUHMAKGUGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMv
# Y2VydHMvTWljcm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBDQSUyMDIwMTAoMSkuY3J0
# MAwGA1UdEwEB/wQCMAAwEwYDVR0lBAwwCgYIKwYBBQUHAwgwDQYJKoZIhvcNAQEL
# BQADggIBAIDA8Vg06Rqi5xaD4Zv4g38BxhfMa9jW6yZfHoBINk4UybE39MARPmUL
# J2H60ZlwW3urAly1Te9Kj7iPjhGzeTDmouwbntf+I+VU5Fqrh+RmXlWrdjfnQ+5U
# lFqdHVPI/rgYQS+RhUpqA1VZvs1thkdo7jyNb9ueACU29peOfGp5ZCYxr5mJ9gbU
# Utd4f8A0e4a0GiOwYHch1gFefhxI+VIayK677cCYor0mlBAN6iumSv62SEL/7jkQ
# 5DjcPtqRxyBNUl5v1iJYa1UthyKIH69yY6r2YqJ+iyUg++NY/MVQy4gpcAG7KR6F
# RY8bcQXDI6j8emlgiUvL40qE54ZFeDzueZqrDO0PF0ERkIQO8OMzUDibvZA+MRXW
# KT1Jizf3WiHBBJaHwYxs/rBHdQeMqqiJN7thuFcoE1xZrYS/HIUqO6/hiL06lioU
# gP7Gp0uDd4woAgntxU0ibKeIOZ8Gry71gLc3DiL0kaKxpgHjdJtsIMwSveU/6oKx
# hg10qLNSTQ1kVQZz9KrMNUKKuRtA/Icb0D7N1+Nygb9RiZdMKOa3AvvTjFsSZQet
# 4LU6ELANQhK2KGCzGbVMyS++I8GZP4K6RxEISIQd7J3gvMMxiibn7e2Dvx1gqbsH
# QoSI8p05wYfshRjHYN8EayGznMP4ipl2aKTE0DDnJiHiMCQHswOwMIIHcTCCBVmg
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
# bGVzIFRTUyBFU046NjBCQy1FMzgzLTI2MzUxJTAjBgNVBAMTHE1pY3Jvc29mdCBU
# aW1lLVN0YW1wIFNlcnZpY2WiIwoBATAHBgUrDgMCGgMVAGp0M62VvUwfd1Xuz2uF
# D2qNn3ytoIGDMIGApH4wfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0
# b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3Jh
# dGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAwDQYJ
# KoZIhvcNAQEFBQACBQDmcWNJMCIYDzIwMjIwNzA3MTc1MTA1WhgPMjAyMjA3MDgx
# NzUxMDVaMHcwPQYKKwYBBAGEWQoEATEvMC0wCgIFAOZxY0kCAQAwCgIBAAICHOwC
# Af8wBwIBAAICETgwCgIFAOZytMkCAQAwNgYKKwYBBAGEWQoEAjEoMCYwDAYKKwYB
# BAGEWQoDAqAKMAgCAQACAwehIKEKMAgCAQACAwGGoDANBgkqhkiG9w0BAQUFAAOB
# gQDIp9x1P/kEhUV5FyYFCfsKMpkGUo50eZ6YDrtT0TIUlW2ltxdoaZ8a/CZnJf+f
# b1UM+jM2755R9b+JhTjwX/AUrntmtQ+01YVQJ72Lx3UrahAqWaG9glNGSU7j5rAJ
# 9KjcVr/Tnet86He4OQ09X3gh5N4iC9RD54XME4cL5+hMOjGCBA0wggQJAgEBMIGT
# MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdS
# ZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMT
# HU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwAhMzAAABpllFgzlNnutLAAEA
# AAGmMA0GCWCGSAFlAwQCAQUAoIIBSjAaBgkqhkiG9w0BCQMxDQYLKoZIhvcNAQkQ
# AQQwLwYJKoZIhvcNAQkEMSIEIEYlrFtYjJB4EyYkF7Y/IjB1TLIsRfQRdH9R744x
# LVUwMIH6BgsqhkiG9w0BCRACLzGB6jCB5zCB5DCBvQQggwsZi8M/dH1r4TCmyUwE
# Girdw6F3ogIX6fEw/bYEqw0wgZgwgYCkfjB8MQswCQYDVQQGEwJVUzETMBEGA1UE
# CBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9z
# b2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQ
# Q0EgMjAxMAITMwAAAaZZRYM5TZ7rSwABAAABpjAiBCCTgVtbWGf2HZ88vXawU1YH
# rK7WWy2NwBugvweE+GGwLzANBgkqhkiG9w0BAQsFAASCAgCtWwRb+11gZkGAcT2y
# MWbtATpAoW2oHZgF2CF1T+utZNqUw9o5eJSf6QKyhWtB3DB+IumINmL43iHmQBsX
# 8rzTn4xvV3kjHcdraRZMBAtUtWu45vf7Tm7LdbRvykKHDdQlHCQE5yTNAsJYaGdI
# 10bHjgaRsgaa/BsU4SffXbJDne2JXnU6gMgmHS47KRa/bPRe1/ejiazfjnWkWn+A
# NKM3W5VPwzrL0Z+XD3vjqYis7NzT6ZkNH8OAQRLu4IRQYyRHjFT62j1jq3PVZ6A6
# XSB2oR1ME8PGGqu+ikDTNO/bqoPoW2+FG1KsykjKButv98ZSgPSS7YVLQYWdRHDZ
# GL8pWCzu0NVhwyQ1itqfVuKX7As0C4qcfnDb2N/zjXH7MdyxmvxXCyTgPK0rSXlC
# QW40qIQDZasGioPPjWdeFzJSSqtA/ylbidH72qgiir2pNwRQ6/BvmTg5S1qEG7Uy
# rHAvgKUxGbCNJa6DHutjPbsKlxml5zEzKnAtZH7erCHL5p1tbrhvq4ErtFCbetR/
# GuquafoIpRpitf6ZjkDSQv2HDAuyORtuP7T1bMgb2mI+I7KjqNA0HylrSzp8P1nx
# CgD/P+z3n9lhe8wnC3+T0dFyK5MA7+tR7kDbig5+6PFXdO82GcbkfQRd/I4JkupP
# 9vhmXKvkz8ziBWEl26A/+DLMZg==
# SIG # End signature block
