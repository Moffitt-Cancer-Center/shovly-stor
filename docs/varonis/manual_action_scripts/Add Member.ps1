# Varonis' sample code(s) are provided on an "as is" and "as available" basis and without any warranty of any kind.  
# Any use of Varonis' sample code(s) is optional at client's sole discretion, responsibility and risk.
# Varonis does not make any commitment with respect to Varonis' sample code(s), their specific functions or their availability, reliability, or ability to meet client's needs.
# Client acknowledges that Varonis may, in its sole discretion, modify, discontinue or update the Varonis' sample code(s) from time to time, without notice and for any reason.

# Set the security protocol to TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Get-AccessToken {
    param (
        [object]$Config
    )

    $url = "https://$($Config.domain)/api/authentication/api_keys/token"

    try {
        $response = Invoke-RestMethod -Method Post -Uri $url -Headers @{
            "x-api-key" = $Config.api_key
            "Content-Type" = "application/x-www-form-urlencoded"
        } -Body @{
            "grant_type" = "varonis_custom"
        }
       # Write-Host "Successfully obtained access token."
        return $response.access_token
    } catch {
        Write-Host "ERROR: Failed to obtain access token. $_"
        exit 1
    }
}

function Add-GroupMembership {
    param (
        [object]$Config,
        [string]$InputMethod, # "sidId" or "domainAndSamAccountName"
        [hashtable]$GroupInfo, # Contains either sidId or domainName+samAccountName
        [array]$MembersInfo # Array of hashtables containing either sidId or domainName+samAccountName
    )

    $token = Get-AccessToken($Config)
    $url = "https://$($Config.domain)/api/graphql"
    $headers = @{
        "Authorization" = "Bearer $token" # Authorization header with the access token
        "Content-Type" = "application/json" # Content-Type header
    }

    # Build the group configuration based on input method
    if ($InputMethod -eq "sidId") {
        $groupConfig = "{sidId: $($GroupInfo.sidId)}"
        $membersConfig = ($MembersInfo | ForEach-Object { "{sidId: $($_.sidId)}" }) -join ', '
    } else {
        $groupConfig = @"
{
                                domainAndSamAccountName: {
                                    domainName: "$($GroupInfo.domainName)"
                                    samAccountName: "$($GroupInfo.samAccountName)"
                                }
                            }
"@
        $membersArray = $MembersInfo | ForEach-Object {
            @"
{
                                domainAndSamAccountName: {
                                    domainName: "$($_.domainName)"
                                    samAccountName: "$($_.samAccountName)"
                                }
                            }
"@
        }
        $membersConfig = $membersArray -join ', '
    }

    # GraphQL mutation to add members to group
    $mutation = @"
    mutation addMembership {
        createActionRequest (input: {
            createOption: PENDING_REVIEW
            requestOrigin: MANUAL_ACTIONS
            requestInput: {
                addMemberToGroup: {
                    activeDirectory: {
                        configuration: {
                            group: $groupConfig
                            members: [$membersConfig]
                        }
                    }
                }
            }
        }) {
            requestResults {
                actionRequestId
                status
                failureMessage
            }
        }
    }
"@
    $body = @{ query = $mutation } | ConvertTo-Json

    try {
        $response = Invoke-RestMethod -Uri $url -Method Post -Headers $headers -Body $body
        
        # Check for GraphQL errors
        if ($response.errors) {
            Write-Host "`nGraphQL Errors:" -ForegroundColor Red
            foreach ($error in $response.errors) {
                Write-Host "  Message: $($error.message)" -ForegroundColor Red
                if ($error.extensions) {
                    Write-Host "  Extensions: $($error.extensions | ConvertTo-Json -Compress)" -ForegroundColor Red
                }
            }
            Write-Host "`nMutation that was attempted:" -ForegroundColor Yellow
            Write-Host $mutation -ForegroundColor Cyan
            exit 1
        }
        
        $results = $response.data.createActionRequest.requestResults
        
        # Display each result
        foreach ($result in $results) {
            Write-Host "    Action Request ID: $($result.actionRequestId)" -ForegroundColor Green
            Write-Host "    Status: $($result.status)"  -ForegroundColor Green
            if ($result.failureMessage) {
                Write-Host "    Failure Message: $($result.failureMessage)"  -ForegroundColor Red
            }
            Write-Host ""
        }
        
        return $results
    } catch {
        Write-Host "`nERROR: Failed to execute add membership mutation. $_" -ForegroundColor Red
        Write-Host "`nMutation that was attempted:" -ForegroundColor Yellow
        Write-Host $mutation -ForegroundColor Cyan
        exit 1
    }

    return @{
        Results = $results
        Mutation = $mutation
    }
}

# Main Script
try {
    # Read configuration
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $ConfigFile = Join-Path $scriptDir "config.json"
    if (-not (Test-Path $ConfigFile)) {
        throw "Config file not found: $ConfigFile"
    }
    $config = Get-Content $ConfigFile | ConvertFrom-Json

    # Ask user for input method
    Write-Host "`nSelect input method:"
    Write-Host "1. Use SidId"
    Write-Host "2. Use Domain Name and SamAccountName"
    $inputChoice = Read-Host "Enter choice (1 or 2)"
    
    if ($inputChoice -eq "1") {
        # SidId method - user provides IDs directly
        $inputMethod = "sidId"
        
        # Prompt user for group SidId
        $groupSidId = Read-Host "`nEnter Group SidId"
        if ([string]::IsNullOrWhiteSpace($groupSidId)) {
            throw "Group SidId cannot be empty"
        }

        # Prompt user for member SidIds (comma-delimited)
        $memberSidIdsInput = Read-Host "Enter Member SidIds (comma-delimited)"
        if ([string]::IsNullOrWhiteSpace($memberSidIdsInput)) {
            throw "Member SidIds cannot be empty"
        }
        
        # Parse member SidIds from comma-delimited input
        $memberSidIds = $memberSidIdsInput -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }

        Write-Host "`nGroup SidId: $groupSidId" -ForegroundColor Green
        Write-Host "Member SidIds ($($memberSidIds.Count)):" -ForegroundColor Green
        $memberSidIds | ForEach-Object { Write-Host "    $_" -ForegroundColor Green }

        # Prepare data for mutation
        $groupInfo = @{ sidId = [int]$groupSidId }
        $membersInfo = $memberSidIds | ForEach-Object { @{ sidId = [int]$_ } }
        
    } elseif ($inputChoice -eq "2") {
        # Domain Name and SamAccountName method
        $inputMethod = "domainAndSamAccountName"
        
        # Prompt for group information
        Write-Host "`n--- Group Information ---"
        $groupDomain = Read-Host "Enter Group Domain Name"
        if ([string]::IsNullOrWhiteSpace($groupDomain)) {
            throw "Group domain name cannot be empty"
        }
        
        $groupSamAccountName = Read-Host "Enter Group SamAccountName"
        if ([string]::IsNullOrWhiteSpace($groupSamAccountName)) {
            throw "Group samAccountName cannot be empty"
        }

        # Prompt for members information
        Write-Host "`n--- Members Information ---"
        Write-Host "Enter members one at a time. Press Enter on Domain Name when done."
        $membersInfo = @()
        
        while ($true) {
            $memberDomain = Read-Host "`nEnter Member Domain Name (or press Enter to finish)"
            if ([string]::IsNullOrWhiteSpace($memberDomain)) {
                break
            }
            
            $memberSamAccountName = Read-Host "Enter Member SamAccountName"
            if ([string]::IsNullOrWhiteSpace($memberSamAccountName)) {
                Write-Host "SamAccountName cannot be empty. Skipping this member." -ForegroundColor Yellow
                continue
            }
            
            $membersInfo += @{
                domainName = $memberDomain
                samAccountName = $memberSamAccountName
            }
            Write-Host "Added member: $memberDomain\$memberSamAccountName" -ForegroundColor Green
        }
        
        if ($membersInfo.Count -eq 0) {
            throw "No members provided"
        }

        # Prepare data for mutation
        $groupInfo = @{
            domainName = $groupDomain
            samAccountName = $groupSamAccountName
        }
        
        Write-Host "`nGroup: $groupDomain\$groupSamAccountName" -ForegroundColor Green
        Write-Host "Members ($($membersInfo.Count)):" -ForegroundColor Green
        $membersInfo | ForEach-Object { Write-Host "    $($_.domainName)\$($_.samAccountName)" -ForegroundColor Green }
        
    } else {
        throw "Invalid choice. Please enter 1 or 2."
    }

    # Display summary
    Write-Host "`n--- Summary ---" -ForegroundColor Cyan
    $summaryTimestamp = Get-Date -Format "dddd, MMMM d, yyyy h:mm:ss tt"
    Write-Host "Timestamp: $summaryTimestamp" -ForegroundColor Green
    if ($inputMethod -eq "sidId") {
        Write-Host "Input Method: SidId" -ForegroundColor Green
        Write-Host "Group SidId: $($groupInfo.sidId)" -ForegroundColor Green
        Write-Host "Member SidIds:" -ForegroundColor Green
        foreach ($member in $membersInfo) {
            Write-Host "  $($member.sidId)" -ForegroundColor Green
        }
    } else {
        Write-Host "Input Method: Domain Name and SamAccountName" -ForegroundColor Green
        Write-Host "Group: $($groupInfo.domainName)\$($groupInfo.samAccountName)" -ForegroundColor Green
        Write-Host "Members:" -ForegroundColor Green
        foreach ($member in $membersInfo) {
            Write-Host "  $($member.domainName)\$($member.samAccountName)" -ForegroundColor Green
        }
    }

    # Add members to group
    Write-Host "`nAdding members to group..."
    $addResult = Add-GroupMembership -Config $config -InputMethod $inputMethod -GroupInfo $groupInfo -MembersInfo $membersInfo

    # Display detailed results
    Write-Host "`n--- Results ---" -ForegroundColor Cyan
    $hasNonSuccess = $false
    foreach ($result in $addResult.Results) {
        if ($result.status -ne "SUCCESS") {
            $hasNonSuccess = $true
        }
        $isError = $result.status -like "*ERROR*"
        Write-Host "Action Request ID: $($result.actionRequestId)" -ForegroundColor $(if ($isError) { "Yellow" } else { "Green" })
        Write-Host "Status: $($result.status)" -ForegroundColor $(if ($isError) { "Red" } else { "Green" })
        if ($result.failureMessage -and $result.failureMessage -ne "") {
            Write-Host "Failure Message: $($result.failureMessage)" -ForegroundColor Red
        } elseif ($isError) {
            Write-Host "Failure Message: No additional details provided" -ForegroundColor Yellow
        }
    }

    if ($hasNonSuccess) {
        Write-Host "`nMutation that was attempted:" -ForegroundColor Yellow
        Write-Host $addResult.Mutation -ForegroundColor Cyan
    }

} catch {
    Write-Host "ERROR: An error occurred in the main script. $_"
    exit 1
}

# Pause to allow user to see the results
Read-Host "`nPress Enter to exit"
