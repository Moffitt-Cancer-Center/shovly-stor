# Varonis' sample code(s) are provided on an "as is" and "as available" basis and without any warranty of any kind.  
# Any use of Varonis' sample code(s) is optional at client's sole discretion, responsibility and risk.
# Varonis does not make any commitment with respect to Varonis' sample code(s), their specific functions or their availability, reliability, or ability to meet client's needs.
# Client acknowledges that Varonis may, in its sole discretion, modify, discontinue or update the Varonis' sample code(s) from time to time, without notice and for any reason.

<#
.SYNOPSIS
    Replace outdated authorizers in Varonis authorization rules.

.DESCRIPTION
    This script finds authorization rules under specified resources and replaces
    outdated authorizers with new ones using the Varonis GraphQL API.

.PARAMETER Endpoint
    Varonis GraphQL API endpoint (e.g., https://your-instance.varonis.com/api/graphql/)

.PARAMETER ApiKey
    Varonis API key for authentication

.PARAMETER TenantId
    Varonis tenant ID

.PARAMETER ResourcePath
    Full path of the resource to update (e.g., \\server\share\folder)

.PARAMETER OldAuthorizerSamAccountNames
    Comma-separated list of SamAccountNames of authorizers to remove

.PARAMETER NewAuthorizerSamAccountNames
    Comma-separated list of SamAccountNames of authorizers to add

.EXAMPLE
    .\Update-AuthorizationRules.ps1 `
        -Endpoint "https://your-instance.varonis.com/api/graphql/" `
        -ApiKey "vkey1_..." `
        -TenantId "00000000-0000-0000-0000-000000000000" `
        -ResourcePath "\\server\share\folder" `
        -OldAuthorizerSamAccountNames "olduser,anotherold" `
        -NewAuthorizerSamAccountNames "newuser,anothernew"
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
#// ...existing code...

# Log what the script is doing to .\logs
$logFolder = $logsPath
$envUser = $env:USERNAME
$envHost = $env:COMPUTERNAME
$currDate = Get-Date -Format "yyyyMMdd_HHmmss"
$psVersion = $PSVersionTable.PSVersion.ToString()
$logFileName = "Transcript-$envUser-$envHost-$currDate-PS$psVersion _DAG_ReplaceAuthRuleAuthorizer.log"
$logFilePath = Join-Path -Path $logFolder -ChildPath $logFileName

# Start the transcript
Start-Transcript -Path $logFilePath

# Import modules
Import-Module (Join-Path $modulesPath "authentication.psm1") -Force
Import-Module (Join-Path $modulesPath "DAG_client_graphql.psm1") -Force
Import-Module (Join-Path $modulesPath "config_manager.psm1") -Force
Import-Module (Join-Path $modulesPath "dag_checkjobstatus.psm1") -Force
Import-Module (Join-Path $modulesPath "userNameSplitter.psm1") -Force

# Handle tenant URL and API key - try config first, then command line, then prompts
if (-not $origin -and -not $apiKey) {
    # Try to get both from config file
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
    # Handle individual parameters with fallback to prompts
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

<#
need to import a csv to read from, should have rulename, old auth, new auth 
foreach loop through every row 
Steps 
    1 - check if rule name is found, break loop if not 
    2 - add new authorizer to rule, wait for job to complete, check for success, break loop if failed 
    3 - remove old authorizer from rule, wait for job to complete, check for success, LOG only if failed 
#>


# Get the CSV file from the Config directory (2 levels up from Samples to src, then into Config)
$csvPath = Join-Path (Split-Path (Split-Path $scriptDir -Parent) -Parent) "Config\ReplaceAuthRuleAuthorizer.csv"

# Verify the file exists before importing
if (-not (Test-Path $csvPath)) {
    Write-Error "CSV file not found at: $csvPath"
    Stop-Transcript
    exit 1
}

# Import the CSV
$authRuleUpdates = Import-Csv -Path $csvPath

Write-Host "Loaded $($authRuleUpdates.Count) rule update(s) from CSV" -ForegroundColor Green

foreach ($update in $authRuleUpdates){
    write-host "Processing rule update for resource: $($update.entity)" -ForegroundColor Cyan
    $addSuccess = $false
    if ($update.type -eq 'group')
    {
        #need to process groups input 
        $asyncQuery = get-content (Join-Path $graphqlPath "async_getAuthRuleGroups.graphql") -Raw
        $groupItem = Split-SamAccountName $update.entity
        $vars = @{
            groupInput = @{
                directoryServices = @{
                    name = @{ eq = $groupItem.Domain }
                }
                samAccountName = @{ eq = $groupItem.Username }
            }
        }
        Write-Verbose "Query: $asyncQuery`nVars: $($vars | ConvertTo-Json -Depth 5)"
        try {
            $jobFull = $graphqlClient.ExecuteQuery($asyncQuery, $vars)
        } catch {
            Write-Host "GraphQL error fetching auth rules for group $($update.entity): $($_.Exception.Message)" -ForegroundColor Red
            continue
        }
        
        $jobID = $jobfull.governedGroupAuthorizationRulesAsync.jobId
        
        Write-Verbose "JobID: $($jobID | ConvertTo-Json -Depth 5)"
        $vars = @{id = $jobID}
        $resultQuery = get-content (join-path $graphqlPath "queryjob_getAuthRulesGroup.graphql") -Raw
        
        Write-Verbose "Result Query: $resultQuery`nVars: $($vars | ConvertTo-Json -Depth 5)"
        
        try {
            $queryJobFull = $graphqlClient.ExecuteQuery($resultQuery,$vars)
        } catch {
            Write-Host "GraphQL error querying job results for group $($update.entity): $($_.Exception.Message)" -ForegroundColor Red
            continue
        }
        
        #get the jobStatus to sent to checkstatus now 
        $queryJobStatus = $queryJobFull.governedGroupAuthorizationRulesQueryJob.jobStatus
        
        Write-Verbose "Query Job Full: $($queryJobFull | ConvertTo-Json -Depth 5)"
    
        if ($queryJobStatus -eq "PENDING")
        {
            $timeoutCounter = 0 
            while ($queryJobStatus -ne "COMPLETED"){
                if ($timeoutCounter -eq 10){ break }
                $timeoutCounter++
                Start-Sleep -Seconds 5
                try {
                    $queryJobFull = $graphqlClient.ExecuteQuery($resultQuery,$vars)
                } catch {
                    Write-Host "GraphQL error polling job status for group $($update.entity): $($_.Exception.Message)" -ForegroundColor Red
                    break
                }
                #get the jobStatus to sent to checkstatus now 
                $queryJobStatus = $queryJobFull.governedGroupAuthorizationRulesQueryJob.jobStatus
            }
        }
        $queryResult = $queryJobFull.governedGroupAuthorizationRulesQueryJob.results
        $queryResult | ConvertTo-Json -Depth 5 
        if (-not $queryResult){ Write-Host "no rules found for $($update.entity), moving on" -ForegroundColor Yellow; continue }
        if ($queryResult.Count -gt 1){ Write-Host "more than 1 rule found for $($update.entity), this script is not designed to handle that, moving on" -ForegroundColor Yellow; continue }
        $entityID = $queryResult.id
        $newAuthorizer = Split-SamAccountName $update.newAuthorizer 

        $vars = @{
            id = $entityID
            authorizers = @(
                @{
                    level = [int]$update.level
                    account = @{
                        samAccountName = $newAuthorizer.Username
                        directoryServices = @{
                            name = $newAuthorizer.Domain
                        }
                    }
                }
            )
        }

        $asyncQuery = Get-Content (Join-Path $graphqlPath "async_AddAuthRuleAuthorizer_group.graphql") -Raw
        Write-Verbose "Query: $asyncQuery`nVars: $($vars | ConvertTo-Json -Depth 5)"

        try {
            $jobFull = $graphqlclient.ExecuteQuery($asyncQuery, $vars)
        } catch {
            Write-Host "GraphQL error adding authorizer to group $($update.entity): $($_.Exception.Message)" -ForegroundColor Red
            continue
        }
        
        $jobID = $jobFull.addGovernedGroupAuthorizersToRuleAsync.jobId
        Write-Verbose "JobID: $($jobID | ConvertTo-Json -Depth 5)"

        $vars = @{id = $jobID}
        $resultQuery = Get-Content (Join-Path $graphqlPath "result_AddAuthRuleAuthorizer_group.graphql") -Raw

        try {
            $queryJobFull = $graphqlClient.ExecuteQuery($resultQuery, $vars)
        } catch {
            Write-Host "GraphQL error checking add authorizer result for group $($update.entity): $($_.Exception.Message)" -ForegroundColor Red
            continue
        }
        
        $queryJobStatus = $queryJobFull.governedGroupAuthorizationRuleMutationJob.jobStatus
        Write-Verbose "Query Job Full: $($queryJobFull | ConvertTo-Json -Depth 5)"
        

        if ($queryJobStatus -ne "COMPLETED")
        {
            $timeoutCounter = 0 
            while ($queryJobStatus -ne "COMPLETED"){
                if ($timeoutCounter -eq 10){ break }
                Write-Verbose "timeout counter: $timeoutCounter"
                $timeoutCounter++
                Start-Sleep -Seconds 5
                try {
                    $queryJobFull = $graphqlClient.ExecuteQuery($resultQuery, $vars)
                } catch {
                    Write-Host "GraphQL error polling add authorizer result for group $($update.entity): $($_.Exception.Message)" -ForegroundColor Red
                    break
                }
                Write-Verbose "Query Job Full: $($queryJobFull | ConvertTo-Json -Depth 5)"
                $queryJobStatus = $queryJobFull.governedGroupAuthorizationRuleMutationJob.jobStatus
            }
        }
        $queryResult = $queryJobFull.governedGroupAuthorizationRuleMutationJob.results
        Write-Verbose "Result: $($queryJobFull | ConvertTo-Json -Depth 5)"
        
        if (-not $queryResult.succeeded){ Write-Host "Something has gone wrong $($queryResult.extensions | ConvertTo-Json -depth 5)" -ForegroundColor Red; continue }
        else {Write-Host "Completed add authorizer: $($update.newAuthorizer) to $($update.entity)" -ForegroundColor Green; $addSuccess = $true }
        if ($addSuccess){
            #proceed to remove old authorizer 
            $oldAuthorizer = Split-SamAccountName $update.oldAuthorizer

            $vars = @{
                id = $entityID
                authorizers = @(
                    @{
                        level = [int]$update.level
                        account = @{
                            samAccountName = $oldAuthorizer.Username
                            directoryServices = @{
                                name = $oldAuthorizer.Domain
                            }
                        }
                    }
                )
            }

            $asyncQuery = Get-Content (Join-Path $graphqlPath "async_RemoveAuthRuleAuthorizer_group.graphql") -Raw
            Write-Verbose "Query: $asyncQuery`nVars: $($vars | ConvertTo-Json -Depth 5)"

            try {
                $jobFull = $graphqlclient.ExecuteQuery($asyncQuery, $vars)
            } catch {
                Write-Host "GraphQL error removing authorizer from group $($update.entity): $($_.Exception.Message)" -ForegroundColor Red
                continue
            }
            
            $jobID = $jobFull.removeGovernedGroupAuthorizersFromRuleAsync.jobId
            Write-Verbose "JobID: $($jobID | ConvertTo-Json -Depth 5)"

            $vars = @{id = $jobID}
            $resultQuery = Get-Content (Join-Path $graphqlPath "result_RemoveAuthRuleAuthorizer_group.graphql") -Raw

            try {
                $queryJobFull = $graphqlClient.ExecuteQuery($resultQuery, $vars)
            } catch {
                Write-Host "GraphQL error checking remove authorizer result for group $($update.entity): $($_.Exception.Message)" -ForegroundColor Red
                continue
            }
            
            $queryJobStatus = $queryJobFull.governedGroupAuthorizationRuleMutationJob.jobStatus
            Write-Verbose "Query Job Full: $($queryJobFull | ConvertTo-Json -Depth 5)"
            

            if ($queryJobStatus -ne "COMPLETED")
            {
                $timeoutCounter = 0 
                while ($queryJobStatus -ne "COMPLETED"){
                    if ($timeoutCounter -eq 10){ break }
                    Write-Verbose "timeout counter: $timeoutCounter"
                    $timeoutCounter++
                    Start-Sleep -Seconds 5
                    try {
                        $queryJobFull = $graphqlClient.ExecuteQuery($resultQuery, $vars)
                    } catch {
                        Write-Host "GraphQL error polling remove authorizer result for group $($update.entity): $($_.Exception.Message)" -ForegroundColor Red
                        break
                    }
                    Write-Verbose "Query Job Full: $($queryJobFull | ConvertTo-Json -Depth 5)"
                    $queryJobStatus = $queryJobFull.governedGroupAuthorizationRuleMutationJob.jobStatus
                }
            }
            $queryResult = $queryJobFull.governedGroupAuthorizationRuleMutationJob.results
            Write-Verbose "Result: $($queryResult | ConvertTo-Json -Depth 5)"
            
            if (-not $queryResult.succeeded){ Write-Host "Failed to remove old authorizer from $($update.entity): $($queryResult.extensions | ConvertTo-Json -depth 5)" -ForegroundColor Yellow }
            else {Write-Host "Successfully removed old authorizer: $($update.oldAuthorizer) from $($update.entity)" -ForegroundColor Green}
        }
    }
    elseif ($update.type -eq 'folder')
    {
        #need to process folders input 
        $asyncQuery = get-content (Join-Path $graphqlPath "async_getAuthRuleFolders.graphql") -Raw
        $vars = @{
            path = $($update.entity)
        }
        Write-Verbose "Query: $asyncQuery`nVars: $($vars | ConvertTo-Json -Depth 5)"
        try {
            $jobFull = $graphqlClient.ExecuteQuery($asyncQuery, $vars)
        } catch {
            Write-Host "GraphQL error fetching auth rules for folder $($update.entity): $($_.Exception.Message)" -ForegroundColor Red
            continue
        }
        
        $jobID = $jobFull.governedResourceAuthorizationRulesAsync.jobId
        

        Write-Verbose "JobID: $($jobID | ConvertTo-Json -Depth 5)"
        $vars = @{id = $jobID}
        $resultQuery = get-content (join-path $graphqlPath "queryjob_getAuthRulesFolders.graphql") -Raw
        
        Write-Verbose "Result Query: $resultQuery`nVars: $($vars | ConvertTo-Json -Depth 5)"
        
        try {
            $queryJobFull = $graphqlClient.ExecuteQuery($resultQuery,$vars)
        } catch {
            Write-Host "GraphQL error querying job results for folder $($update.entity): $($_.Exception.Message)" -ForegroundColor Red
            continue
        }
        
        #get the jobStatus to sent to checkstatus now 
        $queryJobStatus = $queryJobFull.governedResourceAuthorizationRulesQueryJob.jobStatus
        
        Write-Verbose "Query Job Full: $($queryJobFull | ConvertTo-Json -Depth 5)"
        

        if ($queryJobStatus -eq "PENDING")
        {
            $timeoutCounter = 0 
            while ($queryJobStatus -ne "COMPLETED"){
                if ($timeoutCounter -eq 10){ break }
                $timeoutCounter++
                Write-Verbose "timeout counter: $timeoutCounter"
                Start-Sleep -Seconds 5
                try {
                    $queryJobFull = $graphqlClient.ExecuteQuery($resultQuery,$vars)
                } catch {
                    Write-Host "GraphQL error polling job status for folder $($update.entity): $($_.Exception.Message)" -ForegroundColor Red
                    break
                }
                Write-Verbose "Query Job Full: $($queryJobFull | ConvertTo-Json -Depth 5)"
                #get the jobStatus to sent to checkstatus now 
                $queryJobStatus = $queryJobFull.governedResourceAuthorizationRulesQueryJob.jobStatus
            }
        }
        $queryResult = $queryJobFull.governedResourceAuthorizationRulesQueryJob.results
        $queryResult | ConvertTo-Json -Depth 5 
        if (-not $queryResult){ Write-Host "no rules found for $($update.entity), moving on" -ForegroundColor Yellow; continue }
        if ($queryResult.Count -gt 1){ Write-Host "more than 1 rule found for $($update.entity), this script is not designed to handle that, moving on" -ForegroundColor Yellow; continue }

        $entityID = $queryResult.id
        
        #working until here!!

        $newAuthorizer = Split-SamAccountName $update.newAuthorizer 

        $vars = @{
            id = $entityID
            authorizers = @(
                @{
                    level = [int]$update.level
                    account = @{
                        samAccountName = $newAuthorizer.Username
                        directoryServices = @{
                            name = $newAuthorizer.Domain
                        }
                    }
                }
            )
        }

        $asyncQuery = Get-Content (Join-Path $graphqlPath "async_AddAuthRuleAuthorizer.graphql") -Raw
        Write-Verbose "Query: $asyncQuery`nVars: $($vars | ConvertTo-Json -Depth 5)"

        try {
            $jobFull = $graphqlclient.ExecuteQuery($asyncQuery, $vars)
        } catch {
            Write-Host "GraphQL error adding authorizer to folder $($update.entity): $($_.Exception.Message)" -ForegroundColor Red
            continue
        }
        
        $jobID = $jobFull.addGovernedResourceAuthorizersToRuleAsync.jobId
        Write-Verbose "JobID: $($jobID | ConvertTo-Json -Depth 5)"

        $vars = @{id = $jobID}
        $resultQuery = Get-Content (Join-Path $graphqlPath "result_AddAuthRuleAuthorizer.graphql") -Raw

        try {
            $queryJobFull = $graphqlClient.ExecuteQuery($resultQuery, $vars)
        } catch {
            Write-Host "GraphQL error checking add authorizer result for folder $($update.entity): $($_.Exception.Message)" -ForegroundColor Red
            continue
        }
        
        $queryJobStatus = $queryJobFull.governedResourceAuthorizationRuleMutationJob.jobStatus
        Write-Verbose "Query Job Full: $($queryJobFull | ConvertTo-Json -Depth 5)"
        

        if ($queryJobStatus -ne "COMPLETED")
        {
            $timeoutCounter = 0 
            while ($queryJobStatus -ne "COMPLETED"){
                if ($timeoutCounter -eq 10){ break }
                $timeoutCounter++
                Write-Verbose "timeout counter: $timeoutCounter"
                Start-Sleep -Seconds 5
                try {
                    $queryJobFull = $graphqlClient.ExecuteQuery($resultQuery, $vars)
                } catch {
                    Write-Host "GraphQL error polling add authorizer result for group $($update.entity): $($_.Exception.Message)" -ForegroundColor Red
                    break
                }
                Write-Verbose "Query Job Full: $($queryJobFull | ConvertTo-Json -Depth 5)"
                $queryJobStatus = $queryJobFull.governedResourceAuthorizationRuleMutationJob.jobStatus
            }
        }
        $queryResult = $queryJobFull.governedResourceAuthorizationRuleMutationJob.results
        Write-Verbose "Result: $($queryResult | ConvertTo-Json -Depth 5)"
        
        if (-not $queryResult.succeeded){ Write-Host "Something has gone wrong $($queryResult.extensions | ConvertTo-Json -depth 5)" -ForegroundColor Red; continue }
        else {Write-Host "Completed adding authorizer $($update.newAuthorizer) to $($update.entity)" -ForegroundColor Green; $addSuccess = $true }
        if ($addSuccess){
            #proceed to remove old authorizer 
            $oldAuthorizer = Split-SamAccountName $update.oldAuthorizer

            $vars = @{
                id = $entityID
                authorizers = @(
                    @{
                        level = [int]$update.level
                        account = @{
                            samAccountName = $oldAuthorizer.Username
                            directoryServices = @{
                                name = $oldAuthorizer.Domain
                            }
                        }
                    }
                )
            }

            $asyncQuery = Get-Content (Join-Path $graphqlPath "async_RemoveAuthRuleAuthorizer.graphql") -Raw
            Write-Verbose "Query: $asyncQuery`nVars: $($vars | ConvertTo-Json -Depth 5)"

            try {
                $jobFull = $graphqlclient.ExecuteQuery($asyncQuery, $vars)
            } catch {
                Write-Host "GraphQL error removing authorizer from folder $($update.entity): $($_.Exception.Message)" -ForegroundColor Red
                continue
            }
            
            $jobID = $jobFull.removeGovernedResourceAuthorizersFromRuleAsync.jobId
            Write-Verbose "JobID: $($jobID | ConvertTo-Json -Depth 5)"

            $vars = @{id = $jobID}
            $resultQuery = Get-Content (Join-Path $graphqlPath "result_RemoveAuthRuleAuthorizer.graphql") -Raw

            try {
                $queryJobFull = $graphqlClient.ExecuteQuery($resultQuery, $vars)
            } catch {
                Write-Host "GraphQL error checking remove authorizer result for folder $($update.entity): $($_.Exception.Message)" -ForegroundColor Red
                continue
            }
            
            $queryJobStatus = $queryJobFull.governedResourceAuthorizationRuleMutationJob.jobStatus
            Write-Verbose "Query Job Full: $($queryJobFull | ConvertTo-Json -Depth 5)"
            

            if ($queryJobStatus -ne "COMPLETED")
            {
                $timeoutCounter = 0 
                while ($queryJobStatus -ne "COMPLETED"){
                    if ($timeoutCounter -eq 10){ break }
                    Write-Verbose "timeout counter: $timeoutCounter"
                    $timeoutCounter++
                    Start-Sleep -Seconds 5
                    try {
                        $queryJobFull = $graphqlClient.ExecuteQuery($resultQuery, $vars)
                    } catch {
                        Write-Host "GraphQL error polling remove authorizer result for folder $($update.entity): $($_.Exception.Message)" -ForegroundColor Red
                        break
                    }
                    Write-Verbose "Query Job Full: $($queryJobFull | ConvertTo-Json -Depth 5)"
                    $queryJobStatus = $queryJobFull.governedResourceAuthorizationRuleMutationJob.jobStatus
                }
            }
            $queryResult = $queryJobFull.governedResourceAuthorizationRuleMutationJob.results
            Write-Verbose "Result: $($queryResult | ConvertTo-Json -Depth 5)"
            
            if (-not $queryResult.succeeded){ Write-Host "Failed to remove old authorizer from $($update.entity): $($queryResult.extensions | ConvertTo-Json -depth 5)" -ForegroundColor Yellow }
            else {Write-Host "Successfully removed old authorizer $($update.oldAuthorizer) from $($update.entity)" -ForegroundColor Green}
        }
    }
    else 
    {
        Write-Host "Unknown type $($update.type) for entity $($update.entity), skipping" -ForegroundColor Yellow
        continue
    }
}


