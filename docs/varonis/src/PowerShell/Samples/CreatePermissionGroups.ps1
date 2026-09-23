# Varonis' sample code(s) are provided on an "as is" and "as available" basis and without any warranty of any kind.
# Any use of Varonis' sample code(s) is optional at client's sole discretion, responsibility and risk.
# Varonis does not make any commitment with respect to Varonis' sample code(s), their specific functions or their availability, reliability, or ability to meet client's needs.
# Client acknowledges that Varonis may, in its sole discretion, modify, discontinue or update the Varonis' sample code(s) from time to time, without notice and for any reason.

<#
.SYNOPSIS
    Create new permission groups on Varonis governed folders in bulk, with optional bypass.

.DESCRIPTION
    Reads a CSV of folder / permissionType / makeTraverse / bypass rows and, for each row:
      1. Submits createGovernedResourceNewPermissionGroupsAsync to create the permission group.
      2. Polls the async job until COMPLETED, recording success or errors.
      3. If bypass = true and the create succeeded, submits updateGovernedGroupsAsync to set
         the newly created group as a bypass group and polls that job too.
    Results are exported to a timestamped CSV in Config\Logs.

.PARAMETER origin
    Varonis tenant URL (e.g. https://your-instance.varonis.com)

.PARAMETER apiKey
    Varonis API key for authentication

.PARAMETER csvPath
    Optional override path to the input CSV. Defaults to src\Config\CreatePermissionGroups.csv.

.EXAMPLE
    .\CreatePermissionGroups.ps1
    .\CreatePermissionGroups.ps1 -origin "https://your-instance.varonis.com" -apiKey "vkey1_..."
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false, HelpMessage="Specify the Tenant URL")]
    [Alias("TenantUrl","URL")]
    [string]$origin,

    [Parameter(Mandatory=$false, HelpMessage="Specify the API Key")]
    [Alias("Key")]
    [string]$apiKey,

    [Parameter(Mandatory=$false, HelpMessage="Override path to input CSV")]
    [string]$csvPath
)

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
$global:scriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$global:modulesPath = Join-Path (Split-Path $global:scriptDir -Parent) "Config\Modules"
$global:logsPath    = Join-Path (Split-Path $global:scriptDir -Parent) "Config\Logs"
$global:graphqlPath = Join-Path (Split-Path (Split-Path $global:scriptDir -Parent) -Parent) "Config\graphql"

# ---------------------------------------------------------------------------
# Transcript logging
# ---------------------------------------------------------------------------
$envUser     = $env:USERNAME
$envHost     = $env:COMPUTERNAME
$currDate    = Get-Date -Format "yyyyMMdd_HHmmss"
$psVersion   = $PSVersionTable.PSVersion.ToString()
$logFileName = "Transcript-$envUser-$envHost-$currDate-PS$psVersion _DAG_CreatePermissionGroups.log"
$logFilePath = Join-Path $global:logsPath $logFileName
Start-Transcript -Path $logFilePath

# ---------------------------------------------------------------------------
# Modules
# ---------------------------------------------------------------------------
Import-Module (Join-Path $global:modulesPath "authentication.psm1")    -Force
Import-Module (Join-Path $global:modulesPath "DAG_client_graphql.psm1") -Force
Import-Module (Join-Path $global:modulesPath "config_manager.psm1")     -Force
Import-Module (Join-Path $global:modulesPath "dag_checkjobstatus.psm1") -Force

# ---------------------------------------------------------------------------
# Auth
# ---------------------------------------------------------------------------
if (-not $origin -and -not $apiKey) {
    try {
        if (Test-Configuration) {
            Write-Host "Using credentials from configuration file" -ForegroundColor Green
            $origin = Get-TenantUrl
            $apiKey  = Get-ApiKey
        } else {
            Write-Warning "Configuration not available or invalid, prompting for credentials"
            Import-Module (Join-Path $global:modulesPath "request_tenantinfo.psm1") -Force
            $origin = tenanturl
            $apiKey  = apikey
        }
    } catch {
        Write-Warning "Error reading configuration: $($_.Exception.Message)"
        Import-Module (Join-Path $global:modulesPath "request_tenantinfo.psm1") -Force
        $origin = tenanturl
        $apiKey  = apikey
    }
} else {
    Import-Module (Join-Path $global:modulesPath "request_tenantinfo.psm1") -Force
    if (-not $origin) { $origin = tenanturl } else { $origin = TenantUrl -origin $origin }
    if (-not $apiKey)  { $apiKey = apikey   } else { $apiKey  = ApiKey   -apiKey $apiKey  }
}

$auth          = New-Authentication  -Origin $origin -ApiKey $apiKey
$graphqlClient = New-GraphqlClient   -Origin $origin -Auth   $auth

# ---------------------------------------------------------------------------
# Input CSV
# ---------------------------------------------------------------------------
if (-not $csvPath) {
    $csvPath = Join-Path (Split-Path (Split-Path $global:scriptDir -Parent) -Parent) "Config\CreatePermissionGroups.csv"
}

if (-not (Test-Path $csvPath)) {
    Write-Error "Input CSV not found at: $csvPath"
    Stop-Transcript
    exit 1
}
$rows = @()
$rows = Import-Csv -Path $csvPath

# Validate required columns
$requiredColumns = @('folder','permissionType','makeTraverse','bypass')
$csvColumns = $rows[0].PSObject.Properties.Name
foreach ($col in $requiredColumns) {
    if ($col -notin $csvColumns) {
        Write-Error "CSV is missing required column: '$col'. Expected columns: $($requiredColumns -join ', ')"
        Stop-Transcript
        exit 1
    }
}

Write-Host "Loaded $($rows.Count) row(s) from: $csvPath" -ForegroundColor Green

# ---------------------------------------------------------------------------
# GraphQL queries
# ---------------------------------------------------------------------------
$createMutation   = Get-Content (Join-Path $global:graphqlPath "async_addFolderPermissionsNew.graphql") -Raw
$createPollQuery  = Get-Content (Join-Path $global:graphqlPath "queryjob_addFoldersResults.graphql")    -Raw
$bypassMutation   = Get-Content (Join-Path $global:graphqlPath "async_setGroupAsBypass.graphql")        -Raw
$bypassPollQuery  = Get-Content (Join-Path $global:graphqlPath "CheckStatus_addGroup.graphql")          -Raw

# ---------------------------------------------------------------------------
# Helper: poll a job until terminal state, return final response data
# ---------------------------------------------------------------------------
function Wait-ForJob {
    param(
        [string]$JobId,
        [string]$Query,
        [string]$ResultField,   # e.g. 'governedResourceMutationJob' or 'governedGroupMutationJob'
        [string]$Label
    )

    $vars = @{ id = $JobId }
    $timeoutCount = 0
    $maxPolls     = 30

    do {
        if ($timeoutCount -ge $maxPolls) {
            Write-Warning "[$Label] Job $JobId timed out after $maxPolls polls."
            break
        }
        $timeoutCount++

        try {
            $resp   = $graphqlClient.ExecuteQuery($Query, $vars)
            $job    = $resp.$ResultField
            $status = $job.jobStatus
        } catch {
            Write-Host "[$Label] Error polling job $JobId : $($_.Exception.Message)" -ForegroundColor Red
            return $null
        }

        Write-Host "[$Label] Job $JobId — status: $status (poll $timeoutCount)" -ForegroundColor Cyan
        $done = TestJob -jobstatus $status

        if ($done -eq $true) { Start-Sleep -Seconds 5 }
        elseif ($done -eq "Critical Failure") {
            Write-Host "[$Label] Job $JobId entered FAILED state." -ForegroundColor Red
            break
        }
    } while ($done -eq $true)

    return $job
}

# ---------------------------------------------------------------------------
# Main loop
# ---------------------------------------------------------------------------
$statusLog = @()

foreach ($row in $rows) {
    $folder         = $row.folder.Trim()
    $permissionType = $row.permissionType.Trim()
    $makeTraverse   = $row.makeTraverse.Trim() -eq 'true'
    $bypass         = $row.bypass.Trim()       -eq 'true'

    Write-Host "" 
    Write-Host "=== Processing: $folder | $permissionType | makeTraverse=$makeTraverse | bypass=$bypass ===" -ForegroundColor White

    $entry = [PSCustomObject]@{
        Folder          = $folder
        PermissionType  = $permissionType
        MakeTraverse    = $makeTraverse
        Bypass          = $bypass
        CreateJobId     = $null
        CreateStatus    = $null
        CreateSucceeded = $null
        CreateError     = $null
        BypassGroupName = $null
        BypassJobId     = $null
        BypassStatus    = $null
        BypassSucceeded = $null
        BypassError     = $null
    }

    # ------------------------------------------------------------------
    # Step 1: Submit create-permission-groups mutation
    # ------------------------------------------------------------------
    $createVars = @{
        displayPath      = $folder
        permissionTypeName = $permissionType
        makeTraverse     = $makeTraverse
    }

    try {
        $createResp  = $graphqlClient.ExecuteQuery($createMutation, $createVars)
        $createJobId = $createResp.createGovernedResourceNewPermissionGroupsAsync.jobId
        $createInitStatus = $createResp.createGovernedResourceNewPermissionGroupsAsync.jobStatus
    } catch {
        $entry.CreateStatus    = "SUBMIT_ERROR"
        $entry.CreateError     = $_.Exception.Message
        Write-Host "  [Create] Submit failed: $($_.Exception.Message)" -ForegroundColor Red
        $statusLog += $entry
        continue
    }

    $entry.CreateJobId = $createJobId
    Write-Host "  [Create] Submitted job $createJobId (initial status: $createInitStatus)" -ForegroundColor Yellow

    # ------------------------------------------------------------------
    # Step 2: Poll create job
    # ------------------------------------------------------------------
    $createJob = Wait-ForJob -JobId $createJobId -Query $createPollQuery `
        -ResultField "governedResourceMutationJob" -Label "Create"

    if ($null -eq $createJob) {
        $entry.CreateStatus    = "POLL_ERROR"
        $entry.CreateError     = "Null response while polling"
        $statusLog += $entry
        continue
    }

    $entry.CreateStatus = $createJob.jobStatus

    if ($createJob.jobStatus -ne "COMPLETED") {
        $entry.CreateSucceeded = $false
        $entry.CreateError     = "Job did not reach COMPLETED status (last status: $($createJob.jobStatus))"
        Write-Host "  [Create] $($entry.CreateError)" -ForegroundColor Red
        $statusLog += $entry
        continue
    }

    # Examine per-result success (results is a list; typically one entry per input)
    $createResults = @($createJob.results)
    $allSucceeded  = ($createResults | Where-Object { $_.succeeded -eq $false }).Count -eq 0
    $entry.CreateSucceeded = $allSucceeded

    if (-not $allSucceeded) {
        $errors = $createResults | Where-Object { $_.succeeded -eq $false } |
            ForEach-Object { $_.extensions | ConvertTo-Json -Depth 5 -Compress }
        $entry.CreateError = $errors -join " | "
        Write-Host "  [Create] One or more results failed: $($entry.CreateError)" -ForegroundColor Red
        $statusLog += $entry
        continue
    }

    Write-Host "  [Create] Succeeded (jobStatus=$($entry.CreateStatus))" -ForegroundColor Green

    # ------------------------------------------------------------------
    # Step 3: If bypass requested, find the created group and set bypass
    # ------------------------------------------------------------------
    if (-not $bypass) {
        $statusLog += $entry
        continue
    }

    # Extract created groups matching the requested permissionType from the result
    $createdGroups = @()
    foreach ($r in $createResults) {
        if ($null -eq $r.result) { continue }
        foreach ($perm in @($r.result.permissions)) {
            if ($null -eq $perm) { continue }
            if ($perm.permissionType.name -eq $permissionType) {
                $sam    = $perm.physicalPermission.identity.samAccountName
                $domain = $perm.physicalPermission.identity.directoryServices.name
                if ($sam -and $domain) {
                    $createdGroups += [PSCustomObject]@{ SamAccountName = $sam; Domain = $domain }
                }
            }
        }
    }

    if ($createdGroups.Count -eq 0) {
        $entry.BypassError = "Could not determine created group name from job result; bypass skipped."
        Write-Host "  [Bypass] $($entry.BypassError)" -ForegroundColor Yellow

        # Diagnostic: dump whatever the resource's permissions list actually contained so a
        # mismatch (wrong name, missing entry, empty list) can be diagnosed from the transcript.
        $rawPermissions = $createResults | ForEach-Object { $_.result.permissions } | Where-Object { $_ }
        if (@($rawPermissions).Count -gt 0) {
            Write-Host "  [Bypass] Diagnostic - permissions returned for this resource (looking for permissionType.name = '$permissionType'):" -ForegroundColor Yellow
            Write-Host ($rawPermissions | ConvertTo-Json -Depth 10) -ForegroundColor DarkYellow
        } else {
            Write-Host "  [Bypass] Diagnostic - the resource's 'permissions' list was empty in the poll result (no ACL entries returned at all)." -ForegroundColor Yellow
        }

        $statusLog += $entry
        continue
    }

    Write-Host "  [Bypass] Found $($createdGroups.Count) group(s) to set as bypass." -ForegroundColor Cyan

    # Set bypass on each matching group
    $bypassStatuses = @()
    $bypassErrors   = @()

    foreach ($g in $createdGroups) {
        Write-Host "  [Bypass] Setting bypass on $($g.Domain)\$($g.SamAccountName)" -ForegroundColor Cyan

        $bypassVars = @{
            groupName   = $g.SamAccountName
            groupDomain = $g.Domain
            isBypass    = $true
        }

        try {
            $bypassResp      = $graphqlClient.ExecuteQuery($bypassMutation, $bypassVars)
            $bypassJobId     = $bypassResp.updateGovernedGroupsAsync.jobId
            $bypassInitStatus = $bypassResp.updateGovernedGroupsAsync.jobStatus
        } catch {
            $bypassErrors += "$($g.Domain)\$($g.SamAccountName): SUBMIT_ERROR - $($_.Exception.Message)"
            Write-Host "  [Bypass] Submit failed for $($g.Domain)\$($g.SamAccountName): $($_.Exception.Message)" -ForegroundColor Red
            continue
        }

        Write-Host "  [Bypass] Submitted job $bypassJobId (initial status: $bypassInitStatus)" -ForegroundColor Yellow
        $entry.BypassJobId = $bypassJobId

        $bypassJob = Wait-ForJob -JobId $bypassJobId -Query $bypassPollQuery `
            -ResultField "governedGroupMutationJob" -Label "Bypass"

        if ($null -eq $bypassJob) {
            $bypassErrors += "$($g.Domain)\$($g.SamAccountName): POLL_ERROR"
            continue
        }

        $bypassStatuses += $bypassJob.jobStatus

        if ($bypassJob.jobStatus -ne "COMPLETED") {
            $bypassErrors += "$($g.Domain)\$($g.SamAccountName): Job did not reach COMPLETED status (last status: $($bypassJob.jobStatus))"
            Write-Host "  [Bypass] Job for $($g.Domain)\$($g.SamAccountName) did not complete (status: $($bypassJob.jobStatus))" -ForegroundColor Red
            continue
        }

        $bypassResultSucceeded = ($bypassJob.results | Where-Object { $_.succeeded -eq $false }).Count -eq 0

        if (-not $bypassResultSucceeded) {
            $errJson = $bypassJob.results | Where-Object { $_.succeeded -eq $false } |
                ForEach-Object { $_.extensions | ConvertTo-Json -Depth 5 -Compress }
            $bypassErrors += "$($g.Domain)\$($g.SamAccountName): $($errJson -join ' | ')"
            Write-Host "  [Bypass] Failed for $($g.Domain)\$($g.SamAccountName)" -ForegroundColor Red
        } else {
            Write-Host "  [Bypass] Succeeded for $($g.Domain)\$($g.SamAccountName)" -ForegroundColor Green
        }
    }

    $entry.BypassGroupName = ($createdGroups | ForEach-Object { "$($_.Domain)\$($_.SamAccountName)" }) -join "; "
    $entry.BypassStatus    = ($bypassStatuses | Sort-Object -Unique) -join "; "
    $entry.BypassSucceeded = ($bypassErrors.Count -eq 0)
    if ($bypassErrors.Count -gt 0) {
        $entry.BypassError = $bypassErrors -join " | "
    }

    $statusLog += $entry
}

# ---------------------------------------------------------------------------
# Export status log
# ---------------------------------------------------------------------------
$statusLogFile = Join-Path $global:logsPath "StatusLog-CreatePermissionGroups-$currDate.csv"
$statusLog | Export-Csv -Path $statusLogFile -NoTypeInformation -Force
Write-Host ""
Write-Host "Status log written to: $statusLogFile" -ForegroundColor Green

Stop-Transcript
