# Tested with PowerShell 5.1

# Varonis’ sample code(s) are provided on an “as is” and “as available” basis and without any warranty of any kind.  
# Any use of Varonis’ sample code(s) is optional at client’s sole discretion, responsibility and risk.
# Varonis does not make any commitment with respect to Varonis’ sample code(s), their specific functions or their availability, reliability, or ability to meet client’s needs.
# Client acknowledges that Varonis may, in its sole discretion, modify, discontinue or update the Varonis’ sample code(s) from time to time, without notice and for any reason.

#Fill in this with the type of get query you want to run 
param(
    [Parameter(Mandatory=$true, HelpMessage="Set the query type from one of 'RootResource' 'GovernedFolders' 'GovernedGroups'")]
    [ValidateSet("RootResource", "GovernedFolders", "GovernedGroups")]
    [string]$querytype,

    [Parameter(Mandatory=$false, HelpMessage="Specify the Tenant URL")]
    [Alias("TenantUrl","URL")]
    [string]$origin,

    [Parameter(Mandatory=$false, HelpMessage="Specify the API Key")]
    [Alias("Key")]
    [string]$apiKey
)

# Get the current script directory
$global:scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Construct the path to the Modules folder
#// ...existing code...
$global:scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Go up 1 level to PowerShell folder, then find Config\Modules and Config\Logs
$global:modulesPath = Join-Path (Split-Path $scriptDir -Parent) "Config\Modules"
$global:logsPath = Join-Path (Split-Path $scriptDir -Parent) "Config\Logs"

# Path to unified GraphQL queries
$global:graphqlPath = Join-Path (Split-Path (Split-Path $scriptDir -Parent) -Parent) "Config\graphql"
#// ...existing code...

# Log what the script is doing to .\logs
$logFolder = $logsPath
$envUser = $env:USERNAME
$envHost = $env:COMPUTERNAME
$currDate = Get-Date -Format "yyyyMMdd_HHmmss"
$psVersion = $PSVersionTable.PSVersion.ToString()
$logFileName = "Transcript-$envUser-$envHost-$currDate-PS$psVersion _DAG_getBaseFolder.log"
$logFilePath = Join-Path -Path $logFolder -ChildPath $logFileName

# Start the transcript
Start-Transcript -Path $logFilePath

# Import modules
Import-Module (Join-Path $modulesPath "authentication.psm1") -Force
Import-Module (Join-Path $modulesPath "DAG_client_graphql.psm1") -Force
Import-Module (Join-Path $modulesPath "config_manager.psm1") -Force
Import-Module (Join-Path $modulesPath "dag_checkjobstatus.psm1") -Force

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

if ($querytype -eq "RootResource") {
    Write-Host "Get Root Resources from DAG API" -ForegroundColor Green
    $asyncquery_file = Join-Path $graphqlPath "async_getBaseFolders.graphql"
    $checkstatusquery_file = Join-Path $graphqlPath "CheckStatus_GoverenedResources.graphql"
    $reportquery_file = Join-Path $graphqlPath "queryjob_governedresources.graphql"
}
elseif ($querytype -eq "GovernedFolders") {
    Write-Host "Get Governed Folders from DAG API" -ForegroundColor Green
    $asyncquery_file = Join-Path $graphqlPath "async_getManagedFolders.graphql"
    $checkstatusquery_file = Join-Path $graphqlPath "CheckStatus_GoverenedResources.graphql"
    $reportquery_file = Join-Path $graphqlPath "queryjob_governedresources.graphql"
}
elseif ($querytype -eq "GovernedGroups") {
    Write-Host "Get Governed Groups from DAG API" -ForegroundColor Green
    $asyncquery_file = Join-Path $graphqlPath "async_getDAGgroups.graphql"
    $checkstatusquery_file = Join-Path $graphqlPath "CheckStatus_GoverenedGroups.graphql"
    $reportquery_file = Join-Path $graphqlPath "queryjob_GovernedGroups.graphql"
}




# *** END CONFIGURATION SECTION *** #

### Instantiate communication classes ###

# Create an authentication manager
$auth = New-Authentication -Origin $origin -ApiKey $apiKey

# Create a GraphQL client
$graphqlClient = New-GraphqlClient -Origin $origin -Auth $auth

#obtain Job ID for the query to run 
#For query changes, edit the appropriate GraphQL file based on query type
$asyncquery = Get-Content -Path $asyncquery_file -Raw

#extract the ID only from the grpahql results
Write-Host "Getting Job ID"
$jobID = $GraphqlClient.ExecuteQuery($asyncquery)
$jobID | ConvertTo-Json | Out-Null
#get the jobid directly
if ($querytype -eq "RootResource") {
    $id = $jobID.governedResourcesAsync.jobId
}
elseif ($querytype -eq "GovernedFolders") {
    $id = $jobID.governedResourcesAsync.jobId
}
elseif ($querytype -eq "GovernedGroups") {
    $id = $jobID.governedGroupsAsync.jobId
}
Write-Host "Job ID Obtained" -ForegroundColor Green

#confirm the query is done before moving on
# Read the GraphQL query from the file
$checkstatusquery = Get-Content -Path $checkstatusquery_file -Raw

# Create variables object for the GraphQL query
$variables = @{
    id = $id
}

# Execute the query with variables
$jobstatus = $GraphqlClient.ExecuteQuery($checkstatusquery, $variables)
#extract only the status of the job
$jobstatus | ConvertTo-Json | Out-Null
#$checkstatus = $jobstatus.governedResourcesQueryJob.jobStatus
if($querytype -eq "RootResource") {
    $checkstatus = $jobstatus.governedResourcesQueryJob.jobStatus
}
elseif ($querytype -eq "GovernedFolders") {
    $checkstatus = $jobstatus.governedResourcesQueryJob.jobStatus
}
elseif ($querytype -eq "GovernedGroups") {
    $checkstatus = $jobstatus.governedGroupsQueryJob.jobStatus
}

#confirm if we have failed, or completed
$result = $null
$result = TestJob -jobstatus $checkstatus

#result of true means we need to wait, loop until true, and if we fail break out 
$i = 1
$result = $true
while ($result -eq $true)
{
    #Write-Host "$result is the current value to check" 
    if ($result -eq $true){
    Write-Host "This is check number $i we are checking if we should still wait for the Job, and the result is: $result because the job status is $checkstatus" -ForegroundColor Yellow
    $jobstatus = $GraphqlClient.ExecuteQuery($checkstatusquery, $variables)
    $jobstatus | ConvertTo-Json | Out-Null
    #$checkstatus = $jobstatus.governedResourcesQueryJob.jobStatus
if($querytype -eq "RootResource") {
    $checkstatus = $jobstatus.governedResourcesQueryJob.jobStatus
}
elseif ($querytype -eq "GovernedFolders") {
    $checkstatus = $jobstatus.governedResourcesQueryJob.jobStatus
}
elseif ($querytype -eq "GovernedGroups") {
    $checkstatus = $jobstatus.governedGroupsQueryJob.jobStatus
}
    $i = $i+1
    Start-Sleep -Seconds 10
    $result = TestJob -jobstatus $checkstatus
   }
   elseif ($result -eq "Critical Failure")
   {
    Write-Host "Critical Failure" -ForegroundColor Red
    break
   }
}

#Get the actual data using the job id now 

$reportqueryquery = Get-Content -Path $reportquery_file -Raw

#process and print the results of the query
$resultlist = $GraphqlClient.ExecuteQuery($reportqueryquery, $variables)
#$result = $resultlist.governedResourcesQueryJob.results
if($querytype -eq "RootResource") {
    $result = $resultlist.governedResourcesQueryJob.results
}
elseif ($querytype -eq "GovernedFolders") {
    $result = $resultlist.governedResourcesQueryJob.results
}
elseif ($querytype -eq "GovernedGroups") {
    $result = $resultlist.governedGroupsQueryJob.results
}
$result #change this depending on where it needs to go


# Clean up variables
$apiKey = $null

# Stop logging
Stop-Transcript