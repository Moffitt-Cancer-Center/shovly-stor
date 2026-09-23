# Varonis' sample code(s) are provided on an "as is" and "as available" basis and without any warranty of any kind.  
# Any use of Varonis' sample code(s) is optional at client's sole discretion, responsibility and risk.
# Varonis does not make any commitment with respect to Varonis' sample code(s), their specific functions or their availability, reliability, or ability to meet client's needs.
# Client acknowledges that Varonis may, in its sole discretion, modify, discontinue or update the Varonis' sample code(s) from time to time, without notice and for any reason.

<#
.SYNOPSIS
    Remove owners from Varonis governed folders and groups in bulk.

.DESCRIPTION
    This script reads a CSV of entity/owner pairs and removes the specified owner
    from each folder or group using the Varonis GraphQL API.

.PARAMETER origin
    Varonis tenant URL (e.g., https://your-instance.varonis.com)

.PARAMETER apiKey
    Varonis API key for authentication

.EXAMPLE
    .\BulkRemoveOwners.ps1
    .\BulkRemoveOwners.ps1 -origin "https://your-instance.varonis.com" -apiKey "vkey1_..."
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false, HelpMessage="Specify the Tenant URL")]
    [Alias("TenantUrl","URL")]
    [string]$origin,

    [Parameter(Mandatory=$false, HelpMessage="Specify the API Key")]
    [Alias("Key")]
    [string]$apiKey
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
$logFileName = "Transcript-$envUser-$envHost-$currDate-PS$psVersion _DAG_BulkRemoveOwners.log"
$logFilePath = Join-Path -Path $logFolder -ChildPath $logFileName

# Start the transcript
Start-Transcript -Path $logFilePath

# Import modules
Import-Module (Join-Path $modulesPath "authentication.psm1") -Force
Import-Module (Join-Path $modulesPath "DAG_client_graphql.psm1") -Force
Import-Module (Join-Path $modulesPath "config_manager.psm1") -Force
Import-Module (Join-Path $modulesPath "dag_checkjobstatus.psm1") -Force
Import-Module (Join-Path $modulesPath "userNameSplitter.psm1") -Force

$verify = 'Verified'
$UserConfirm = read-host "Removing users in bulk can be very dangerous if done wrong, please enter $verify to confirm you are aware of this"

if ($UserConfirm -ne $verify){Write-Host 'Failed verify, ending script' -ForegroundColor Red; exit}

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

# Get the CSV file from the Config directory
$csvPath = Join-Path (Split-Path (Split-Path $scriptDir -Parent) -Parent) "Config\BulkRemoveOwners.csv"

if (-not (Test-Path $csvPath)) {
    Write-Error "CSV file not found at: $csvPath"
    Stop-Transcript
    exit 1
}

$ownerRemovals = Import-Csv -Path $csvPath

Write-Host "Loaded $($ownerRemovals.Count) removal(s) from CSV" -ForegroundColor Green

foreach ($removal in $ownerRemovals) {
    Write-Host "Processing owner removal for: $($removal.entity)" -ForegroundColor Cyan

    if ($removal.type -eq 'folder') {
        $ownerParts = Split-SamAccountName $removal.owner

        $vars = @{
            displayPath = $removal.entity
            ownerName   = $ownerParts.Username
            ownerDomain = $ownerParts.Domain
        }

        $asyncQuery = Get-Content (Join-Path $graphqlPath "async_removeFolderOwner.graphql") -Raw
        Write-Verbose "Query: $asyncQuery`nVars: $($vars | ConvertTo-Json -Depth 5)"

        try {
            $jobFull = $graphqlClient.ExecuteQuery($asyncQuery, $vars)
        } catch {
            Write-Host "GraphQL error removing owner from folder $($removal.entity): $($_.Exception.Message)" -ForegroundColor Red
            continue
        }

        $jobID = $jobFull.removeGovernedResourceOwnersAsync.jobId
        Write-Verbose "JobID: $jobID"

        $statusQuery = Get-Content (Join-Path $graphqlPath "CheckStatus_RemoveFolder.graphql") -Raw
        $statusVars  = @{ id = $jobID }

        try {
            $statusFull = $graphqlClient.ExecuteQuery($statusQuery, $statusVars)
        } catch {
            Write-Host "GraphQL error checking removal status for folder $($removal.entity): $($_.Exception.Message)" -ForegroundColor Red
            continue
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
                    Write-Host "GraphQL error polling removal status for folder $($removal.entity): $($_.Exception.Message)" -ForegroundColor Red
                    break
                }
                $jobStatus = $statusFull.governedResourceMutationJob.jobStatus
                Write-Verbose "timeout counter: $timeoutCounter, status: $jobStatus"
            }
        }

        $jobResult = $statusFull.governedResourceMutationJob.results
        Write-Verbose "Result: $($jobResult | ConvertTo-Json -Depth 5)"

        if (-not $jobResult.succeeded) {
            Write-Host "Failed to remove owner $($removal.owner) from folder $($removal.entity): $($jobResult.extensions | ConvertTo-Json -Depth 5)" -ForegroundColor Red
        } else {
            Write-Host "Successfully removed owner $($removal.owner) from folder $($removal.entity)" -ForegroundColor Green
        }
    }
    elseif ($removal.type -eq 'group') {
        $groupParts = Split-SamAccountName $removal.entity
        $ownerParts = Split-SamAccountName $removal.owner

        $vars = @{
            groupName   = $groupParts.Username
            groupDomain = $groupParts.Domain
            ownerName   = $ownerParts.Username
            ownerDomain = $ownerParts.Domain
        }

        $asyncQuery = Get-Content (Join-Path $graphqlPath "async_removeGroupOwner.graphql") -Raw
        Write-Verbose "Query: $asyncQuery`nVars: $($vars | ConvertTo-Json -Depth 5)"

        try {
            $jobFull = $graphqlClient.ExecuteQuery($asyncQuery, $vars)
        } catch {
            Write-Host "GraphQL error removing owner from group $($removal.entity): $($_.Exception.Message)" -ForegroundColor Red
            continue
        }

        $jobID = $jobFull.removeGovernedGroupOwnersAsync.jobId
        Write-Verbose "JobID: $jobID"

        $statusQuery = Get-Content (Join-Path $graphqlPath "CheckStatus_removeGroup.graphql") -Raw
        $statusVars  = @{ id = $jobID }

        try {
            $statusFull = $graphqlClient.ExecuteQuery($statusQuery, $statusVars)
        } catch {
            Write-Host "GraphQL error checking removal status for group $($removal.entity): $($_.Exception.Message)" -ForegroundColor Red
            continue
        }

        $jobStatus = $statusFull.governedGroupMutationJob.jobStatus
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
                    Write-Host "GraphQL error polling removal status for group $($removal.entity): $($_.Exception.Message)" -ForegroundColor Red
                    break
                }
                $jobStatus = $statusFull.governedGroupMutationJob.jobStatus
                Write-Verbose "timeout counter: $timeoutCounter, status: $jobStatus"
            }
        }

        if ($jobStatus -eq "COMPLETED") {
            Write-Host "Successfully removed owner $($removal.owner) from group $($removal.entity)" -ForegroundColor Green
        } else {
            Write-Host "Job did not complete for group $($removal.entity) (status: $jobStatus)" -ForegroundColor Red
        }
    }
    else {
        Write-Host "Unknown type '$($removal.type)' for entity $($removal.entity), skipping" -ForegroundColor Yellow
        continue
    }
}

Stop-Transcript
