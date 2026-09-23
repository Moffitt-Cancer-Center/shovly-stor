# Varonis' sample code(s) are provided on an "as is" and "as available" basis and without any warranty of any kind.
# Any use of Varonis' sample code(s) is optional at client's sole discretion, responsibility and risk.
# Varonis does not make any commitment with respect to Varonis' sample code(s), their specific functions or their availability, reliability, or ability to meet client's needs.
# Client acknowledges that Varonis may, in its sole discretion, modify, discontinue or update the Varonis' sample code(s) from time to time, without notice and for any reason.

<#
.SYNOPSIS
    Remove (un-manage) Varonis governed folders in bulk. THIS IS PERMANENT.

.DESCRIPTION
    Reads a CSV of folder paths and removes each folder from DAG governance
    using the Varonis GraphQL API's removeGovernedResourcesAsync mutation.
    Once a folder is removed it must be re-added and re-configured from
    scratch, so the script requires a typed confirmation before it does
    anything.

.PARAMETER origin
    Varonis tenant URL (e.g., https://your-instance.varonis.com)

.PARAMETER apiKey
    Varonis API key for authentication

.PARAMETER PathsFile
    Path to a CSV file with a "path" column, one folder path per row.
    Defaults to src\Config\RemoveGovernedResources.csv

.EXAMPLE
    .\RemoveGovernedResources.ps1
    .\RemoveGovernedResources.ps1 -origin "https://your-instance.varonis.com" -apiKey "vkey1_..." -PathsFile "C:\lists\foldersToRemove.csv"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false, HelpMessage="Specify the Tenant URL")]
    [Alias("TenantUrl","URL")]
    [string]$origin,

    [Parameter(Mandatory=$false, HelpMessage="Specify the API Key")]
    [Alias("Key")]
    [string]$apiKey,

    [Parameter(Mandatory=$false, HelpMessage="Path to a CSV file with a 'path' column")]
    [string]$PathsFile
)

# Get the current script directory
$global:scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Go up 1 level to PowerShell folder, then find Config\Modules and Config\Logs
$global:modulesPath = Join-Path (Split-Path $global:scriptDir -Parent) "Config\Modules"
$global:logsPath = Join-Path (Split-Path $global:scriptDir -Parent) "Config\Logs"
# Path to unified GraphQL queries
$global:graphqlPath = Join-Path (Split-Path (Split-Path $scriptDir -Parent) -Parent) "Config\graphql"

# Log what the script is doing to .\logs
$logFolder = $logsPath
$envUser = $env:USERNAME
$envHost = $env:COMPUTERNAME
$currDate = Get-Date -Format "yyyyMMdd_HHmmss"
$psVersion = $PSVersionTable.PSVersion.ToString()
$logFileName = "Transcript-$envUser-$envHost-$currDate-PS$psVersion _DAG_RemoveGovernedResources.log"
$logFilePath = Join-Path -Path $logFolder -ChildPath $logFileName

# Start the transcript
Start-Transcript -Path $logFilePath

# Import modules
Import-Module (Join-Path $modulesPath "authentication.psm1") -Force
Import-Module (Join-Path $modulesPath "DAG_client_graphql.psm1") -Force
Import-Module (Join-Path $modulesPath "config_manager.psm1") -Force
Import-Module (Join-Path $modulesPath "dag_checkjobstatus.psm1") -Force

# Resolve the paths file (default lives alongside the other sample input files in Config)
if (-not $PathsFile) {
    $PathsFile = Join-Path (Split-Path (Split-Path $scriptDir -Parent) -Parent) "Config\RemoveGovernedResources.csv"
}

if (-not (Test-Path $PathsFile)) {
    Write-Error "Paths file not found at: $PathsFile"
    Stop-Transcript
    exit 1
}

$folderPaths = Import-Csv -Path $PathsFile |
    ForEach-Object { $_.path.Trim() } |
    Where-Object { $_ } |
    Select-Object -Unique

if (-not $folderPaths -or $folderPaths.Count -eq 0) {
    Write-Error "No folder paths found in: $PathsFile"
    Stop-Transcript
    exit 1
}

Write-Host "Loaded $($folderPaths.Count) folder path(s) from $PathsFile" -ForegroundColor Cyan
$folderPaths | ForEach-Object { Write-Host "  $_" }

# Removal is permanent - require an explicit typed confirmation before continuing
$verify = 'REMOVE'
Write-Host ""
Write-Host "Removing a folder from DAG governance is PERMANENT and cannot be undone." -ForegroundColor Red
Write-Host "The $($folderPaths.Count) folder(s) listed above will be un-managed." -ForegroundColor Red
$UserConfirm = Read-Host "Type $verify to confirm you understand this action is permanent"

if ($UserConfirm -ne $verify) { Write-Host 'Failed verify, ending script' -ForegroundColor Red; Stop-Transcript; exit }

# Handle tenant URL and API key - try config first, then command line, then prompts
if (-not $origin -and -not $apiKey) {
    try {
        if (Test-Configuration) {
            Write-Host "Using credentials from configuration file" -ForegroundColor Green
            $origin = Get-TenantUrl
            $apiKey = Get-ApiKey
        } else {
            Write-Warning "Configuration not available or invalid, prompting for credentials"
            Import-Module (Join-Path $modulesPath "request_tenantinfo.psm1") -Force
            $origin = tenanturl
            $apiKey = apikey
        }
    } catch {
        Write-Warning "Error reading configuration: $($_.Exception.Message)"
        Import-Module (Join-Path $modulesPath "request_tenantinfo.psm1") -Force
        $origin = tenanturl
        $apiKey = apikey
    }
} else {
    Import-Module (Join-Path $modulesPath "request_tenantinfo.psm1") -Force

    if ($origin -eq $null -or $origin -eq "") {
        $origin = tenanturl
    } elseif ($null -ne $origin) {
        $origin = TenantUrl -origin $origin
    }

    if ($apiKey -eq $null -or $apiKey -eq "") {
        $apiKey = apikey
    } elseif ($null -ne $apiKey) {
        $apiKey = ApiKey -apiKey $apiKey
    }
}

# Create an authentication manager
$auth = New-Authentication -Origin $origin -ApiKey $apiKey

# Create a GraphQL client
$graphqlClient = New-GraphqlClient -Origin $origin -Auth $auth

$asyncQuery = Get-Content (Join-Path $graphqlPath "async_removeGovernedResources.graphql") -Raw
$statusQuery = Get-Content (Join-Path $graphqlPath "CheckStatus_RemoveGovernedResources.graphql") -Raw

$succeeded = @()
$failed = @()

# Submit every path in a single mutation call instead of one call per folder
$removeInputs = @($folderPaths | ForEach-Object { @{ displayPath = $_ } })
$vars = @{ removeGovernedResourcesInput = $removeInputs }
Write-Verbose "Query: $asyncQuery`nVars: $($vars | ConvertTo-Json -Depth 5)"

try {
    $jobFull = $graphqlClient.ExecuteQuery($asyncQuery, $vars)
} catch {
    Write-Error "GraphQL error submitting removal for $($folderPaths.Count) folder(s): $($_.Exception.Message)"
    Stop-Transcript
    exit 1
}

$jobID = $jobFull.removeGovernedResourcesAsync.jobId
Write-Verbose "JobID: $jobID"

$statusVars = @{ id = $jobID }

try {
    $statusFull = $graphqlClient.ExecuteQuery($statusQuery, $statusVars)
} catch {
    Write-Error "GraphQL error checking removal status: $($_.Exception.Message)"
    Stop-Transcript
    exit 1
}

$jobStatus = $statusFull.governedResourceMutationJob.jobStatus
Write-Verbose "Job status: $jobStatus"

if ($jobStatus -ne "COMPLETED") {
    $timeoutCounter = 0
    while ($jobStatus -ne "COMPLETED") {
        if ($timeoutCounter -eq 10) { break }
        $timeoutCounter++
        Start-Sleep -Seconds 5
        try {
            $statusFull = $graphqlClient.ExecuteQuery($statusQuery, $statusVars)
        } catch {
            Write-Host "GraphQL error polling removal status: $($_.Exception.Message)" -ForegroundColor Red
            break
        }
        $jobStatus = $statusFull.governedResourceMutationJob.jobStatus
        Write-Verbose "timeout counter: $timeoutCounter, status: $jobStatus"
    }
}

# The API does not guarantee results are returned in the same order the
# paths were submitted, so match each result back to its path by displayPath
# rather than by array index.
$jobResults = @($statusFull.governedResourceMutationJob.results)

if ($jobResults.Count -ne $folderPaths.Count) {
    Write-Warning "Expected $($folderPaths.Count) result(s) but received $($jobResults.Count)."
}

$resultsByPath = @{}
foreach ($result in $jobResults) {
    if ($result.result.displayPath) {
        $resultsByPath[$result.result.displayPath] = $result
    }
}

foreach ($path in $folderPaths) {
    $result = $resultsByPath[$path]

    if ($null -eq $result) {
        Write-Host "No result returned for folder $($path)" -ForegroundColor Red
        $failed += $path
    } elseif (-not $result.succeeded) {
        Write-Host "Failed to remove folder $($path): $($result.extensions | ConvertTo-Json -Depth 5)" -ForegroundColor Red
        $failed += $path
    } else {
        Write-Host "Successfully removed folder $path from DAG governance" -ForegroundColor Green
        $succeeded += $path
    }
}

Write-Host ""
Write-Host "Done. Removed: $($succeeded.Count), Failed: $($failed.Count)" -ForegroundColor Cyan
if ($failed.Count -gt 0) {
    Write-Host "Failed paths:" -ForegroundColor Yellow
    $failed | ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow }
}

Stop-Transcript
