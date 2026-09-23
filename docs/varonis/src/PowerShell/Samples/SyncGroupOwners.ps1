# Varonis’ sample code(s) are provided on an “as is” and “as available” basis and without any warranty of any kind.  
# Any use of Varonis’ sample code(s) is optional at client’s sole discretion, responsibility and risk.
# Varonis does not make any commitment with respect to Varonis’ sample code(s), their specific functions or their availability, reliability, or ability to meet client’s needs.
# Client acknowledges that Varonis may, in its sole discretion, modify, discontinue or update the Varonis’ sample code(s) from time to time, without notice and for any reason.

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false, HelpMessage="Specify the Tenant URL")]
    [Alias("TenantUrl","URL")]
    [string]$origin,

    [Parameter(Mandatory=$false, HelpMessage="Specify the API Key")]
    [Alias("Key")]
    [string]$apiKey,

    [Parameter(Mandatory=$true, HelpMessage="How many days to look back for group creation")]
    [Alias("days")]
    [int]$daysBack
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
$logFileName = "Transcript-$envUser-$envHost-$currDate-PS$psVersion _DAG_SyncGroupOwners.log"
$logFilePath = Join-Path -Path $logFolder -ChildPath $logFileName


# Start the transcript
Start-Transcript -Path $logFilePath

# Import modules
Import-Module (Join-Path $modulesPath "ADHelper.psm1") -Force
Import-Module (Join-Path $modulesPath "authentication.psm1") -Force
Import-Module (Join-Path $modulesPath "DAG_client_graphql.psm1") -Force
Import-Module (Join-Path $modulesPath "config_manager.psm1") -Force
Import-Module (Join-Path $modulesPath "dag_checkjobstatus.psm1") -Force
Import-Module (Join-Path $modulesPath "userNameSplitter.psm1") -Force

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

# Check if the ActiveDirectory module is loaded
if (Get-Module -Name ActiveDirectory) 
    {
        Write-Host "Active Directory module is loaded." -ForegroundColor Green
    } 
else 
    {
        Write-Host "Active Directory module is NOT loaded, trying to load it." -ForegroundColor Red
        Import-Module ActiveDirectory -ErrorAction SilentlyContinue
            if (Get-Module -Name ActiveDirectory) 
            {
                Write-Host "Active Directory module is loaded." -ForegroundColor Green
            }
            else 
            {
                throw "Failed to load AD Module, please install and retry"
            }
    }

if ($daysBack -gt 0) {$daysBack = $daysBack * -1}
$since = (Get-Date).AddDays($daysBack)
Write-Host "Getting all groups since $since"
$allGroups = @(Get-ADGroup -LDAPFilter "(managedby=*)" -Properties managedby, whencreated, CanonicalName | Where-Object { [datetime]$_.WhenCreated -ge $since })
Write-Host "Found a total of $($allGroups.Count) items"
$addOwnerMutation = Get-Content (Join-Path $graphqlPath 'async_addGroupOwner.graphql') -Raw
$allJobsArray = @()
$statusLog = @()

foreach ($group in $allGroups)
{
    $groupName = Get-ADObjectName -ADObject $group
    $groupDomain = Get-ADOBjectDomain -ADObject $group
    $jobId = $null
    $status = "OK"
    $errorMsg = $null
    try { $ownerRaw = Get-ADUser -Identity $group.ManagedBy -Properties SamAccountName, CanonicalName -ErrorAction Stop }
    catch { $ownerRaw = $null }
    $ownerName = Get-ADObjectName -ADObject $ownerRaw
    $ownerDomain = Get-ADObjectDomain -ADObject $ownerRaw

    if (-not ($groupname -and $groupdomain -and $ownername -and $ownerDomain))
    {
        $status = "ERROR"
        $errorMsg = "Failed to resolve group or owner info"
        $statusLog += [PSCustomObject]@{
            GroupName = $groupName
            Status = $status
            JobID = $null
            Error = $errorMsg
        }
        Write-Host "One of the fields failed to resolve, please check" -ForegroundColor Red
        Write-Host "Found Group Name of: $groupName"
        Write-Host "Found Group Domain of: $groupDomain"
        Write-Host "Found Owner Name of: $ownerName"
        Write-Host "Found Owner Domain of: $ownerDomain"
        continue 
    }
    Write-Host "Planning to set $ownerDomain\$ownerName as DAG Owner on $groupDomain\$groupName" -ForegroundColor Cyan

    $vars = @{
            "groupName" = $groupName
            "groupDomain" = $groupDomain
            "ownerName" = $ownerName
            "ownerDomain" = $ownerDomain
        }
    try {
        $jobFull = $graphqlClient.ExecuteQuery($addOwnerMutation, $vars)
        $jobId = $jobFull.addGovernedGroupOwnersAsync.jobId
        $status = $jobFull.addGovernedGroupOwnersAsync.jobStatus
    } catch {
        $status = "ERROR"
        $errorMsg = $_.Exception.Message
    }
    $allJobsArray += $jobId
    $statusLog += [PSCustomObject]@{
        GroupName = $groupName
        Status = $status
        JobID = $jobId
        Error = $errorMsg
    }
    Write-Host "Group: $groupName | Status: $status | JobID: $jobId" -ForegroundColor Yellow
    if ($errorMsg) { Write-Host "Error: $errorMsg" -ForegroundColor Red }
}

#start loop of checkstatus 
$checkStatusQuery = Get-Content (Join-Path $graphqlPath 'CheckStatus_addGroup.graphql') -Raw
for ($i = 0; $i -lt $allJobsArray.Count; $i++) {
    $jobID = $allJobsArray[$i]
    $groupName = $statusLog[$i].GroupName
    if (-not $jobID) {
        Write-Host "No job ID for group $groupName, skipping status check." -ForegroundColor Red
        continue
    }
    $vars = @{"id" = $jobID}
    do {
        $checkstatus = $graphqlClient.ExecuteQuery($checkStatusQuery, $vars)
        $jobStatus = $checkstatus.governedGroupMutationJob.jobStatus
        Write-Host ("Polling job $jobID for group ${groupName}: Status = $jobStatus") -ForegroundColor Cyan
        $completed = TestJob -jobstatus $jobStatus
        if ($completed -eq $true) { Start-Sleep -Seconds 10 }
    } while ($completed -eq $true)
    if ($checkstatus.governedGroupMutationJob.results.succeeded -eq $false)
    {
        $extensionsJson = $checkstatus.governedGroupMutationJob.results.extensions | ConvertTo-Json -Depth 5
        Write-Host $extensionsJson
        # Update status log with extensions as error
        $statusLog[$i].Error = $extensionsJson
    }
    else {
        Write-Host "$($checkstatus | convertto-json -depth 5)"
    }
}

# After all jobs are processed, export status log to CSV
$statusLogFile = Join-Path (Split-Path $logsPath -Parent) "\Logs\StatusLog-SyncGroupOwners-$currDate.csv"
$statusLog | Export-Csv -Path $statusLogFile -NoTypeInformation -Force
Write-Host "Status log written to: $statusLogFile" -ForegroundColor Green