# Tested with PowerShell 5.1

# Varonis' sample code(s) are provided on an "as is" and "as available" basis and without any warranty of any kind.  
# Any use of Varonis' sample code(s) is optional at client's sole discretion, responsibility and risk.
# Varonis does not make any commitment with respect to Varonis' sample code(s), their specific functions or their availability, reliability, or ability to meet client's needs.
# Client acknowledges that Varonis may, in its sole discretion, modify, discontinue or update the Varonis' sample code(s) from time to time, without notice and for any reason.

<#
.SYNOPSIS
    Submit a membership request to DAG

.DESCRIPTION
    This script submits a membership request to add or remove a user from a group in DAG.
    It supports both command-line parameters and interactive prompts.

.PARAMETER Origin
    Tenant URL (e.g., https://tenant.varonis.io)

.PARAMETER ApiKey
    Access Control API key

.PARAMETER Group
    Group in format domain\accountname

.PARAMETER User
    User in format domain\accountname

.PARAMETER Action
    Access action (Grant or Revoke)

.PARAMETER Reason
    Reason for the request (required)

.PARAMETER AutoApprove
    Auto-approve the request (switch parameter)

.PARAMETER ExpirationDate
    Expiration date in format YYYY-MM-DDTHH:MM:SS or DD/MM/YYYY

.PARAMETER ActivationDate
    Activation date in format YYYY-MM-DDTHH:MM:SS or DD/MM/YYYY

.PARAMETER ExpirationDays
    Expiration days interval (positive integer)

.EXAMPLE
    .\membershipRequest.ps1
    (Interactive mode - will prompt for all required values)

.EXAMPLE
    .\membershipRequest.ps1 -Origin "https://tenant.varonis.io" -ApiKey "vkey_..." -Group "DOMAIN\GroupName" -User "DOMAIN\UserName" -Action Grant -Reason "Need access for project"

.EXAMPLE
    .\membershipRequest.ps1 -Group "DOMAIN\GroupName" -User "DOMAIN\UserName" -Action Grant -Reason "Need access" -AutoApprove -ExpirationDays 30
#>

param(
    [Parameter(Mandatory=$false, HelpMessage="Specify the Tenant URL")]
    [Alias("TenantUrl","URL")]
    [string]$Origin,

    [Parameter(Mandatory=$false, HelpMessage="Specify the API Key")]
    [Alias("Key")]
    [string]$ApiKey,

    [Parameter(Mandatory=$false, HelpMessage="Group in format domain\accountname")]
    [string]$Group,

    [Parameter(Mandatory=$false, HelpMessage="User in format domain\accountname")]
    [string]$User,

    [Parameter(Mandatory=$false, HelpMessage="Access action (Grant or Revoke)")]
    [ValidateSet("Grant", "Revoke", "grant", "revoke")]
    [string]$Action,

    [Parameter(Mandatory=$false, HelpMessage="Reason for the request")]
    [string]$Reason,

    [Parameter(Mandatory=$false, HelpMessage="Auto-approve the request")]
    [switch]$AutoApprove,

    [Parameter(Mandatory=$false, HelpMessage="Expiration date (YYYY-MM-DDTHH:MM:SS or DD/MM/YYYY)")]
    [string]$ExpirationDate,

    [Parameter(Mandatory=$false, HelpMessage="Activation date (YYYY-MM-DDTHH:MM:SS or DD/MM/YYYY)")]
    [string]$ActivationDate,

    [Parameter(Mandatory=$false, HelpMessage="Expiration days interval (positive integer)")]
    [int]$ExpirationDays
)

# Get the current script directory
$global:scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Construct paths to modules, logs, and GraphQL queries
$global:modulesPath = Join-Path (Split-Path (Split-Path $scriptDir -Parent) -Parent) "Config\Modules"
$global:logsPath = Join-Path (Split-Path (Split-Path $scriptDir -Parent) -Parent) "Config\Logs"
$global:graphqlPath = Join-Path (Split-Path (Split-Path (Split-Path $scriptDir -Parent) -Parent) -Parent) "Config\graphql"

# Log what the script is doing
$logFolder = $logsPath
$envUser = $env:USERNAME
$envHost = $env:COMPUTERNAME
$currDate = Get-Date -Format "yyyyMMdd_HHmmss"
$psVersion = $PSVersionTable.PSVersion.ToString()
$logFileName = "Transcript-$envUser-$envHost-$currDate-PS$psVersion _DAG_membershipRequest.log"
$logFilePath = Join-Path -Path $logFolder -ChildPath $logFileName

# Start the transcript
Start-Transcript -Path $logFilePath

Write-Host "=== DAG Membership Request Script ===" -ForegroundColor Cyan
Write-Host ""

# Import required modules
Import-Module (Join-Path $modulesPath "authentication.psm1") -Force
Import-Module (Join-Path $modulesPath "client_graphql.psm1") -Force
Import-Module (Join-Path $modulesPath "config_manager.psm1") -Force
Import-Module (Join-Path $modulesPath "dag_checkjobstatus.psm1") -Force
Import-Module (Join-Path $modulesPath "request_tenantinfo.psm1") -Force

#region Helper Functions

function Parse-DomainAccount {
    param(
        [string]$DomainAccount,
        [string]$FieldName
    )
    
    if ([string]::IsNullOrWhiteSpace($DomainAccount)) {
        return $null, $null
    }
    
    if ($DomainAccount -notlike "*\*") {
        Write-Host "Invalid $FieldName format. Please use domain\accountname." -ForegroundColor Red
        return $null, $null
    }
    
    $parts = $DomainAccount -split '\\', 2
    $domain = $parts[0].Trim()
    $account = $parts[1].Trim()
    
    if ([string]::IsNullOrWhiteSpace($domain) -or [string]::IsNullOrWhiteSpace($account)) {
        Write-Host "Invalid $FieldName format. Both domain and account name are required." -ForegroundColor Red
        return $null, $null
    }
    
    return $domain, $account
}

function Validate-Date {
    param(
        [string]$DateStr,
        [string]$FieldName
    )
    
    if ([string]::IsNullOrWhiteSpace($DateStr)) {
        return $null
    }
    
    try {
        # Try ISO format first (YYYY-MM-DDTHH:MM:SS)
        $parsedDate = [DateTime]::ParseExact($DateStr, "yyyy-MM-ddTHH:mm:ss", $null)
        return $parsedDate.ToString("yyyy-MM-ddTHH:mm:ss") + "Z"
    }
    catch {
        try {
            # Try DD/MM/YYYY format
            $parsedDate = [DateTime]::ParseExact($DateStr, "dd/MM/yyyy", $null)
            return $parsedDate.ToString("yyyy-MM-ddTHH:mm:ss") + "Z"
        }
        catch {
            Write-Host "Invalid $FieldName format. Please use ISO 8601 (YYYY-MM-DDTHH:MM:SS) or DD/MM/YYYY." -ForegroundColor Red
            return $null
        }
    }
}

function Get-ValidatedInput {
    param(
        [string]$Prompt,
        [string]$ValidationPattern,
        [string]$ErrorMessage,
        [bool]$Required = $true,
        [scriptblock]$CustomValidator = $null
    )
    
    while ($true) {
        $input = Read-Host $Prompt
        
        if ([string]::IsNullOrWhiteSpace($input)) {
            if (-not $Required) {
                return $null
            }
            Write-Host $ErrorMessage -ForegroundColor Red
            continue
        }
        
        if ($ValidationPattern -and $input -notmatch $ValidationPattern) {
            Write-Host $ErrorMessage -ForegroundColor Red
            continue
        }
        
        if ($CustomValidator) {
            $validationResult = & $CustomValidator $input
            if ($validationResult -eq $true) {
                return $input
            }
            continue
        }
        
        return $input
    }
}

#endregion

#region Handle Inputs

Write-Host "Gathering inputs..." -ForegroundColor Yellow

# Determine if we're in command-line mode (all required parameters provided)
$commandLineMode = $false
if ($Group -and $User -and $Action -and $Reason) {
    # Validate group format
    $groupDomain, $groupAccount = Parse-DomainAccount -DomainAccount $Group -FieldName "group"
    $userDomain, $userAccount = Parse-DomainAccount -DomainAccount $User -FieldName "user"
    
    if ($groupDomain -and $groupAccount -and $userDomain -and $userAccount) {
        $commandLineMode = $true
        Write-Host "All required fields provided via command line" -ForegroundColor Green
    }
    else {
        Write-Host "Invalid group or user format in command line parameters" -ForegroundColor Red
        Stop-Transcript
        exit 1
    }
}
elseif ($Group -or $User -or $Action -or $Reason) {
    Write-Host "When providing request fields via command line, all required fields (-Group, -User, -Action, -Reason) must be provided" -ForegroundColor Red
    Stop-Transcript
    exit 1
}

# Get Group information
if (-not $commandLineMode) {
    while ($true) {
        $groupInput = Read-Host "Group (domain\sam account name)"
        $groupDomain, $groupAccount = Parse-DomainAccount -DomainAccount $groupInput -FieldName "group"
        if ($groupDomain -and $groupAccount) {
            break
        }
    }
}

# Get User information
if (-not $commandLineMode) {
    while ($true) {
        $userInput = Read-Host "User (domain\sam account name)"
        $userDomain, $userAccount = Parse-DomainAccount -DomainAccount $userInput -FieldName "user"
        if ($userDomain -and $userAccount) {
            break
        }
    }
}

# Get Action
if (-not $commandLineMode) {
    while ($true) {
        $Action = Read-Host "Access Action (Grant or Revoke)"
        if ($Action -match '^(Grant|Revoke)$') {
            break
        }
        Write-Host "Invalid input. Please enter 'Grant' or 'Revoke'" -ForegroundColor Red
    }
}

# Normalize Action to uppercase
$Action = $Action.ToUpper()

# Get Reason
if (-not $commandLineMode) {
    while ([string]::IsNullOrWhiteSpace($Reason)) {
        $Reason = Read-Host "Reason"
        if ([string]::IsNullOrWhiteSpace($Reason)) {
            Write-Host "Reason is required and cannot be empty." -ForegroundColor Red
        }
    }
}

# Get AutoApprove (optional) - only prompt if not in command-line mode
$isAutoApprove = $false
if ($AutoApprove.IsPresent) {
    $isAutoApprove = $true
}
elseif (-not $commandLineMode) {
    $autoInput = Read-Host "Auto Approve? (yes/no, optional)"
    if ($autoInput -match '^(yes|true|y|1)$') {
        $isAutoApprove = $true
    }
}

# Get Expiration Date or Interval (optional) - only prompt if not in command-line mode
$expirationDateISO = $null
$expirationDaysInterval = $null

if ($ExpirationDate) {
    $expirationDateISO = Validate-Date -DateStr $ExpirationDate -FieldName "expiration date"
    if (-not $expirationDateISO) {
        Stop-Transcript
        exit 1
    }
}
elseif ($ExpirationDays -gt 0) {
    $expirationDaysInterval = $ExpirationDays
}
elseif (-not $commandLineMode) {
    $expInput = Read-Host "Expiration Date (YYYY-MM-DDTHH:MM:SS or DD/MM/YYYY, optional)"
    if (-not [string]::IsNullOrWhiteSpace($expInput)) {
        $expirationDateISO = Validate-Date -DateStr $expInput -FieldName "expiration date"
    }
    else {
        # Ask for interval if no date provided
        $intervalInput = Read-Host "Expiration Days Interval (positive integer, optional)"
        if (-not [string]::IsNullOrWhiteSpace($intervalInput)) {
            if ($intervalInput -match '^\d+$' -and [int]$intervalInput -gt 0) {
                $expirationDaysInterval = [int]$intervalInput
            }
            else {
                Write-Host "Invalid input. Expiration days interval must be a positive integer." -ForegroundColor Yellow
            }
        }
    }
}

# Get Activation Date (optional) - only prompt if not in command-line mode
$activationDateISO = $null
if ($ActivationDate) {
    $activationDateISO = Validate-Date -DateStr $ActivationDate -FieldName "activation date"
    if (-not $activationDateISO) {
        Stop-Transcript
        exit 1
    }
}
elseif (-not $commandLineMode) {
    $actInput = Read-Host "Activation Date (YYYY-MM-DDTHH:MM:SS or DD/MM/YYYY, optional)"
    if (-not [string]::IsNullOrWhiteSpace($actInput)) {
        $activationDateISO = Validate-Date -DateStr $actInput -FieldName "activation date"
    }
}

#endregion

#region Build Request Variables

# Build the variables hashtable for the GraphQL mutation
$variables = @{
    groupAccountName = $groupAccount
    groupDomainName = $groupDomain
    requestedForSamAccountName = $userAccount
    requestedForDirectoryServicesName = $userDomain
    accessAction = $Action
    reason = $Reason
    isAutoApprove = $isAutoApprove
}

# Add optional parameters only if they have values
if ($expirationDateISO) {
    $variables.expirationDate = $expirationDateISO
}
if ($activationDateISO) {
    $variables.activationDate = $activationDateISO
}
if ($expirationDaysInterval -gt 0) {
    $variables.expirationDaysInterval = $expirationDaysInterval
}

Write-Host ""
Write-Host "Request Variables:" -ForegroundColor Cyan
$variables | ConvertTo-Json -Depth 5 | Write-Host

#endregion

#region Handle Authentication

Write-Host ""
Write-Host "Setting up authentication..." -ForegroundColor Yellow

# Handle tenant URL and API key - try config first, then command line, then prompts
if (-not $Origin -and -not $ApiKey) {
    # Try to get both from config file
    try {
        if (Test-Configuration) {
            Write-Host "Using credentials from configuration file" -ForegroundColor Green
            $Origin = Get-TenantUrl
            $ApiKey = Get-ApiKey
        } else {
            Write-Warning "Configuration not available or invalid, prompting for credentials"
            $Origin = TenantUrl 
            $ApiKey = ApiKey
        }
    } catch {
        Write-Warning "Error reading configuration: $($_.Exception.Message)"
        $Origin = TenantUrl 
        $ApiKey = ApiKey
    }
} else {
    # Handle individual parameters with fallback to prompts
    if ([string]::IsNullOrWhiteSpace($Origin)) {
        $Origin = TenantUrl 
    } else {
        $Origin = TenantUrl -origin $Origin
    }
    
    if ([string]::IsNullOrWhiteSpace($ApiKey)) {
        $ApiKey = ApiKey
    } else {
        $ApiKey = ApiKey -apikey $ApiKey
    }
}

# Create an authentication manager
$auth = New-Authentication -Origin $Origin -ApiKey $ApiKey

# Create a GraphQL client
$graphqlClient = New-GraphqlClient -Origin $Origin -Auth $auth

Write-Host "Authentication successful" -ForegroundColor Green

#endregion

#region Execute Membership Request

Write-Host ""
Write-Host "Submitting membership request..." -ForegroundColor Yellow

# Load the mutation query
$asyncMutationFile = Join-Path $graphqlPath "async_submitMembershipRequest.graphql"
$asyncMutation = Get-Content -Path $asyncMutationFile -Raw

# Execute the mutation
try {
    $mutationResult = $graphqlClient.ExecuteQuery($asyncMutation, $variables)
    $jobId = $mutationResult.createGovernedMembershipRequestsAsync.jobId
    $jobStatus = $mutationResult.createGovernedMembershipRequestsAsync.jobStatus
    
    Write-Host "Mutation submitted successfully" -ForegroundColor Green
    Write-Host "Job ID: $jobId" -ForegroundColor Cyan
    Write-Host "Initial Job Status: $jobStatus" -ForegroundColor Cyan
}
catch {
    Write-Host "Error executing membership request mutation: $($_.Exception.Message)" -ForegroundColor Red
    Stop-Transcript
    exit 1
}

#endregion

#region Check Job Status and Get Results

Write-Host ""
Write-Host "Checking job status..." -ForegroundColor Yellow

# Load the status check query
$checkStatusFile = Join-Path $graphqlPath "result_submitRequest.graphql"
$checkStatusQuery = Get-Content -Path $checkStatusFile -Raw

# Variables for status check
$statusVariables = @{
    id = $jobId
}

# Poll until job is complete
$maxAttempts = 60  # Maximum 10 minutes (60 * 10 seconds)
$attempt = 1

while ($attempt -le $maxAttempts) {
    Start-Sleep -Seconds 10
    
    try {
        $statusResult = $graphqlClient.ExecuteQuery($checkStatusQuery, $statusVariables)
        $currentStatus = $statusResult.governedRequestMutationJob.jobStatus
        
        Write-Host "Attempt $attempt - Job Status: $currentStatus" -ForegroundColor Yellow
        
        if ($currentStatus -eq "COMPLETED") {
            Write-Host ""
            Write-Host "Job completed successfully!" -ForegroundColor Green
            
            # Display results
            $results = $statusResult.governedRequestMutationJob.results
            Write-Host ""
            Write-Host "=== Results ===" -ForegroundColor Cyan
            $results | ConvertTo-Json -Depth 10 | Write-Host
            
            # Check for any failures
            $failedResults = $results | Where-Object { $_.succeeded -eq $false }
            if ($failedResults) {
                Write-Host ""
                Write-Host "WARNING: Some requests failed:" -ForegroundColor Red
                foreach ($failed in $failedResults) {
                    Write-Host "  Error: $($failed.extensions.errorMessage)" -ForegroundColor Red
                    if ($failed.extensions.errorDetails) {
                        Write-Host "  Details: $($failed.extensions.errorDetails)" -ForegroundColor Red
                    }
                }
                # Set exit code to indicate failure
                $global:LASTEXITCODE = 1
                $exitCode = 1
            }
            else {
                Write-Host ""
                Write-Host "All requests succeeded!" -ForegroundColor Green
                
                # Display request IDs
                foreach ($result in $results) {
                    if ($result.result.id) {
                        Write-Host "Request ID: $($result.result.id)" -ForegroundColor Cyan
                    }
                }
                # Set exit code to indicate success
                $global:LASTEXITCODE = 0
                $exitCode = 0
            }
            
            break
        }
        elseif ($currentStatus -eq "FAILED") {
            Write-Host ""
            Write-Host "Job failed!" -ForegroundColor Red
            $results = $statusResult.governedRequestMutationJob.results
            if ($results) {
                Write-Host "Error details:" -ForegroundColor Red
                $results | ConvertTo-Json -Depth 10 | Write-Host
            }
            Stop-Transcript
            exit 1
        }
        elseif ($currentStatus -eq "PENDING") {
            # Continue waiting
        }
        else {
            Write-Host "Unknown job status: $currentStatus" -ForegroundColor Yellow
        }
        
        $attempt++
    }
    catch {
        Write-Host "Error checking job status: $($_.Exception.Message)" -ForegroundColor Red
        Stop-Transcript
        exit 1
    }
}

if ($attempt -gt $maxAttempts) {
    Write-Host ""
    Write-Host "Job did not complete within the expected time. Job ID: $jobId" -ForegroundColor Yellow
    Write-Host "You can check the status manually using the job ID." -ForegroundColor Yellow
    $exitCode = 1
}

# Ensure we have an exit code set (default to 1 if not set)
if (-not (Test-Path variable:exitCode)) {
    $exitCode = 1
}

#endregion

# Clean up variables
$ApiKey = $null

Write-Host ""
Write-Host "=== Script completed ===" -ForegroundColor Cyan

# Stop logging
Stop-Transcript

# Exit with the appropriate code
exit $exitCode
