# Tested with PowerShell 5.1
# Varonis’ sample code(s) are provided on an “as is” and “as available” basis and without any warranty of any kind.  
# Any use of Varonis’ sample code(s) is optional at client’s sole discretion, responsibility and risk.
# Varonis does not make any commitment with respect to Varonis’ sample code(s), their specific functions or their availability, reliability, or ability to meet client’s needs.
# Client acknowledges that Varonis may, in its sole discretion, modify, discontinue or update the Varonis' sample code(s) from time to time, without notice and for any reason.

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

# Construct the path to the logs folder and config folder
# Expected structure: ...\PowerShell\Samples (scriptDir) -> ...\PowerShell\Config
$global:logsPath = Join-Path (Split-Path $scriptDir -Parent) "Config\Logs"
$global:configPath  = Join-Path (Split-Path (Split-Path $scriptDir -Parent) -Parent) "Config"
$global:modulesPath = Join-Path (Split-Path $scriptDir -Parent) "Config\Modules"
$global:graphqlPath = Join-Path (Split-Path (Split-Path $scriptDir -Parent) -Parent) "Config\graphql"


# Log what the script is doing to .\logs
$logFolder = $logsPath
$envUser = $env:USERNAME
$envHost = $env:COMPUTERNAME
$currDate = Get-Date -Format "yyyyMMdd_HHmmss"
$psVersion = $PSVersionTable.PSVersion.ToString()
$logFileName = "Transcript-$envUser-$envHost-$currDate-PS$psVersion _DAG_mergeGroups.log"
$logFilePath = Join-Path -Path $logFolder -ChildPath $logFileName

# Start the transcript
Start-Transcript -Path $logFilePath

# Import modules
Import-Module (Join-Path $modulesPath "authentication.psm1")      -Force
Import-Module (Join-Path $modulesPath "DAG_client_graphql.psm1")   -Force
Import-Module (Join-Path $modulesPath "config_manager.psm1")       -Force
Import-Module (Join-Path $modulesPath "dag_checkjobstatus.psm1")   -Force
Import-Module (Join-Path $modulesPath "userNameSplitter.psm1")     -Force

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

    if (-not $origin) {
        $origin = tenanturl
    } elseif ($null -ne $origin) {
        $origin = TenantUrl -origin $origin
    }

    if (-not $apiKey) {
        $apiKey = apikey
    } elseif ($null -ne $apiKey) {
        $apiKey = ApiKey -apiKey $apiKey
    }
}

# Create auth manager and GraphQL client
$auth          = New-Authentication  -Origin $origin -ApiKey $apiKey
$graphqlClient = New-GraphqlClient   -Origin $origin -Auth $auth

# Load GraphQL query files
$asyncMembershipQuery    = Get-Content -Path (Join-Path $graphqlPath "async_getGroupMembers.graphql")                       -Raw
$queryjobMembershipQuery = Get-Content -Path (Join-Path $graphqlPath "queryjob_getGroupMembers.graphql")                    -Raw
$addMembersMutation      = Get-Content -Path (Join-Path $graphqlPath "createActionRequest_addMemberToGroup.graphql") -Raw

Write-Host "=== DAG Merge Groups Script ===" -ForegroundColor Cyan
Write-Host "This script orchestrates membership and permission requests to merge groups" -ForegroundColor Cyan
Write-Host ""

# Path to the merge groups CSV file (in the Config directory)
$mergeFile = Join-Path $configPath "mergeGroups.csv"

# Check if file exists
if (-not (Test-Path $mergeFile)) {
    Write-Host "Error: mergeGroups.csv not found at $mergeFile" -ForegroundColor Red
    Write-Host "Please create a mergeGroups.csv file in the Config directory with columns: Folder, SourceGroup, TargetGroup, Permission" -ForegroundColor Yellow
    Stop-Transcript
    exit 1
}

$items = @(Import-Csv $mergeFile)

# Check if CSV has any data
if (-not $items -or $items.Count -eq 0) {
    Write-Host "Error: No merge operations found in $mergeFile" -ForegroundColor Red
    Stop-Transcript
    exit 1
}

# Path to the request scripts (in Request Scripts subdirectory)
$requestScriptsPath = Join-Path $scriptDir "Request Scripts"
$membershipRequestScript = Join-Path $requestScriptsPath "membershipRequest.ps1"
$permissionRequestScript = Join-Path $requestScriptsPath "permissionRequest.ps1"

# Verify request scripts exist
if (-not (Test-Path $membershipRequestScript)) {
    Write-Host "Error: membershipRequest.ps1 not found at $membershipRequestScript" -ForegroundColor Red
    Stop-Transcript
    exit 1
}



Write-Host "  Membership: $membershipRequestScript" -ForegroundColor Cyan
Write-Host ""

# Process each merge item
$itemCount = $items.Count
Write-Host "Processing $itemCount merge operation(s)..." -ForegroundColor Yellow
Write-Host ""

# Track overall results
$successCount = 0
$failureCount = 0
$partialSuccessCount = 0
$skippedCount = 0

$currentItem = 1

# ─── Helper: run one membership async job and poll until complete ─────────────
function Invoke-MembershipJob {
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$WhereVariables
    )

    # Start the async job
    $jobResponse = $graphqlClient.ExecuteQuery($asyncMembershipQuery, $WhereVariables)
    $jobId = $jobResponse.membershipsAsync.jobId

    if (-not $jobId) {
        Write-Warning "  No jobId returned from membershipsAsync."
        return $null
    }

    Write-Host "  Job ID: $jobId" -ForegroundColor Gray

    # Variables shared by status-check and result queries
    $jobVars = @{ id = $jobId }

    # Initial status check
    $jobResponse  = $graphqlClient.ExecuteQuery($queryjobMembershipQuery, $jobVars)
    $checkstatus  = $jobResponse.membershipsQueryJob.jobStatus
    $pollResult   = TestJob -jobstatus $checkstatus

    $i = 1
    $pollResult = $true
    while ($pollResult -eq $true) {
        Write-Host "  Poll #$i - status: $checkstatus" -ForegroundColor Yellow
        $jobResponse = $graphqlClient.ExecuteQuery($queryjobMembershipQuery, $jobVars)
        $checkstatus = $jobResponse.membershipsQueryJob.jobStatus
        $i++
        Start-Sleep -Seconds 10
        $pollResult = TestJob -jobstatus $checkstatus
    }

    if ($pollResult -eq "Critical Failure") {
        Write-Host "  Job failed (Critical Failure)" -ForegroundColor Red
        return $null
    }

    # Completed - fetch final results
    $finalResponse = $graphqlClient.ExecuteQuery($queryjobMembershipQuery, $jobVars)
    return $finalResponse.membershipsQueryJob.results
}

# ─── Per-row loop: collect unique users from each source group ────────────────
foreach ($item in $items) {
    Write-Host "--- Item $currentItem of $itemCount ---" -ForegroundColor Cyan

    $sourceGroup = $item.SourceGroup
    $targetGroup = $item.TargetGroup

    if (-not $sourceGroup -or -not $targetGroup) {
        Write-Host "  Skipping: missing SourceGroup or TargetGroup." -ForegroundColor Yellow
        $skippedCount++
        $currentItem++
        continue
    }

    # Parse DOMAIN\GroupName
    $parsed = Split-SamAccountName -SamAccountName $sourceGroup
    if (-not $parsed) {
        Write-Host "  Skipping: could not parse SourceGroup '$sourceGroup'." -ForegroundColor Yellow
        $skippedCount++
        $currentItem++
        continue
    }

    $sourceDomain    = $parsed.Domain
    $sourceGroupName = $parsed.Username

    Write-Host "  Source : $sourceGroup" -ForegroundColor White
    Write-Host "  Target : $targetGroup" -ForegroundColor White
    Write-Host "  Getting members of '$sourceDomain\$sourceGroupName'..." -ForegroundColor White

    try {
        # Single async/queryjob call - API returns all members including from nested sub-groups
        $whereByName = @{
            where = @{
                group = @{
                    name = @{ contains = $sourceGroupName }
                }
            }
        }

        $results = Invoke-MembershipJob -WhereVariables $whereByName

        if (-not $results) {
            Write-Warning "  No results returned for group '$sourceGroupName'. Skipping."
            $skippedCount++
            $currentItem++
            continue
        }

        # Filter to entries whose directoryService matches the input domain
        $matchingResults = @($results | Where-Object { $_.group.directoryService.name -eq $sourceDomain })

        if ($matchingResults.Count -eq 0) {
            Write-Warning "  No results matched domain '$sourceDomain' for group '$sourceGroupName'. Skipping."
            $skippedCount++
            $currentItem++
            continue
        }

        # Collect unique users keyed by member id
        $uniqueUsers = @{}
        foreach ($entry in $matchingResults) {
            $member = $entry.member
            if ($member.type -eq "USER" -and -not $uniqueUsers.ContainsKey($member.id)) {
                $uniqueUsers[$member.id] = $member
            }
        }

        if ($uniqueUsers.Count -eq 0) {
            Write-Host "  No users found in source group. Skipping." -ForegroundColor Yellow
            $skippedCount++
        } else {
            Write-Host "  Found $($uniqueUsers.Count) unique user(s) in '$sourceGroup':" -ForegroundColor Green
            foreach ($userId in $uniqueUsers.Keys) {
                $u = $uniqueUsers[$userId]
                Write-Host "    - $($u.name) (id: $userId, domain: $($u.directoryServices.name))" -ForegroundColor Gray
            }

            # Parse target group into domain and SAM account name
            $targetParsed = Split-SamAccountName -SamAccountName $targetGroup.Trim()
            if (-not $targetParsed -or -not $targetParsed.Domain) {
                Write-Host "  Could not parse TargetGroup '$targetGroup'. Skipping." -ForegroundColor Yellow
                $skippedCount++
            } else {
                $targetDomain = $targetParsed.Domain
                $targetSam    = $targetParsed.Username

                # Build variables hashtable — members is an array of sidId objects
                $addMembersVars = @{
                    input = @{
                        requestInput  = @{
                            addMemberToGroup = @{
                                activeDirectory = @{
                                    configuration = @{
                                        members = @($uniqueUsers.Keys | ForEach-Object { @{ sidId = [int]$_ } })
                                        group   = @{
                                            domainAndSamAccountName = @{
                                                domainName     = $targetDomain
                                                samAccountName = $targetSam
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        requestOrigin = "MANUAL_ACTIONS"
                        createOption  = "EXECUTE_NOW"
                    }
                }

                Write-Host "  Submitting addMemberToGroup for $($uniqueUsers.Count) user(s) to '$targetGroup'..." -ForegroundColor White
                $mutationResponse = $graphqlClient.ExecuteQuery($addMembersMutation, $addMembersVars)
                $requestResults   = $mutationResponse.createActionRequest.requestResults

                $rowSucceeded = $true
                $rowHadAnySuccess = $false
                foreach ($result in $requestResults) {
                    if ($result.status -eq "FAILED" -or $result.failureMessage) {
                        Write-Host "    [FAIL] actionRequestId: $($result.actionRequestId) | $($result.failureMessage)" -ForegroundColor Red
                        $rowSucceeded = $false
                    } else {
                        Write-Host "    [OK]   actionRequestId: $($result.actionRequestId) | status: $($result.status)" -ForegroundColor Green
                        $rowHadAnySuccess = $true
                    }
                }

                if ($rowSucceeded) {
                    $successCount++
                } elseif ($rowHadAnySuccess) {
                    $partialSuccessCount++
                } else {
                    $failureCount++
                }
            }
        }
    } catch {
        Write-Host "  ERROR processing '$sourceGroup': $($_.Exception.Message)" -ForegroundColor Red
        $failureCount++
    }

    $currentItem++
    Write-Host ""
}

# Clean up credentials
$apiKey = $null

Write-Host "=== Merge Operations Summary ===" -ForegroundColor Cyan
Write-Host "Total items processed: $itemCount" -ForegroundColor White
Write-Host "Fully successful: $successCount" -ForegroundColor Green
Write-Host "Partially successful: $partialSuccessCount" -ForegroundColor Yellow
Write-Host "Failed: $failureCount" -ForegroundColor Red
Write-Host "Skipped (missing required fields): $skippedCount" -ForegroundColor Yellow
Write-Host ""

if ($failureCount -eq 0 -and $partialSuccessCount -eq 0 -and $skippedCount -eq 0) {
    Write-Host "All merge operations completed successfully!" -ForegroundColor Green
}
elseif ($failureCount -eq 0 -and $skippedCount -eq 0) {
    Write-Host "All merge operations completed with warnings. Check partial successes above." -ForegroundColor Yellow
}
else {
    Write-Host "Some merge operations encountered issues. Please review the errors above." -ForegroundColor Red
}

# Stop logging
Stop-Transcript