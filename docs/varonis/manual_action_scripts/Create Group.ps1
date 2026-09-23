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
        return $response.access_token
    } catch {
        Write-Host "ERROR: Failed to obtain access token. $_"
        exit 1
    }
}

function Get-OrganizationalUnits {
    param (
        [object]$Config
    )

    $token = Get-AccessToken($Config)
    $url = "https://$($Config.domain)/api/graphql"
    $headers = @{
        "Authorization" = "Bearer $token"
        "Content-Type" = "application/json"
    }

    # GraphQL query to get organizational units
    $query = @"
    query getOuIds {
        getOrganizationalUnits {
            organizationalUnits {
                domainName
                domainId
                ouId
                distinguishedName
            }
        }
    }
"@
    $body = @{ query = $query } | ConvertTo-Json

    try {
        $response = Invoke-RestMethod -Uri $url -Method Post -Headers $headers -Body $body
        $ous = $response.data.getOrganizationalUnits.organizationalUnits
        return $ous
    } catch {
        Write-Host "ERROR: Failed to retrieve organizational units. $_"
        exit 1
    }
}

function New-Group {
    param (
        [object]$Config,
        [string]$GroupName,
        [string]$Description,
        [int]$DomainId,
        [int]$OuId,
        [string]$GroupType, # SECURITY or DISTRIBUTION
        [string]$Scope # GLOBAL, LOCAL, or UNIVERSAL
    )

    $token = Get-AccessToken($Config)
    $url = "https://$($Config.domain)/api/graphql"
    $headers = @{
        "Authorization" = "Bearer $token"
        "Content-Type" = "application/json"
    }

    # Description is mandatory; send empty string when not provided
    $effectiveDescription = if ([string]::IsNullOrWhiteSpace($Description)) { "" } else { $Description }

    # GraphQL mutation to create group
    $mutation = @"
    mutation createGroup {
        createActionRequest (input: {
            createOption: PENDING_REVIEW
            requestOrigin: MANUAL_ACTIONS
            requestInput: {
                createGroup: {
                    activeDirectory: {
                        configuration: {
                            groupName: "$GroupName"
                            description: "$effectiveDescription"
                            domainId: $DomainId
                            ouId: $OuId
                            groupType: $GroupType
                            scope: $Scope
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
            foreach ($gqlItem in $response.errors) {
                Write-Host "  Message: $($gqlItem.message)" -ForegroundColor Red
                if ($gqlItem.extensions) {
                    Write-Host "  Extensions: $($gqlItem.extensions | ConvertTo-Json -Compress)" -ForegroundColor Red
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
            Write-Host "    Status: $($result.status)" -ForegroundColor Green
            if ($result.failureMessage) {
                Write-Host "    Failure Message: $($result.failureMessage)" -ForegroundColor Red
            }
            Write-Host ""
        }
        
        return $results
    } catch {
        Write-Host "`nERROR: Failed to execute create group mutation. $_" -ForegroundColor Red
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

    # Prompt for group details
    Write-Host "`n--- Group Information ---" -ForegroundColor Cyan
    
    $groupName = Read-Host "Enter Group Name"
    if ([string]::IsNullOrWhiteSpace($groupName)) {
        throw "Group name cannot be empty"
    }

    $description = Read-Host "Enter Group Description (optional)"

    # Prompt for OU name
    $ouName = Read-Host "Enter OU Name (e.g., 'System', 'Users', or a distinguished name)"
    if ([string]::IsNullOrWhiteSpace($ouName)) {
        throw "OU name cannot be empty"
    }

    # Get organizational units
    Write-Host "`nFetching organizational units..."
    $ous = Get-OrganizationalUnits -Config $config
    
    if ($ous.Count -eq 0) {
        throw "No organizational units found"
    }

    # Search for matching OUs (match by CN or full distinguished name)
    $matchingOus = $ous | Where-Object { 
        $_.distinguishedName -like "*CN=$ouName,*" -or 
        $_.distinguishedName -like "*OU=$ouName,*" -or 
        $_.distinguishedName -eq $ouName -or
        $_.distinguishedName -like "*$ouName*"
    }

    if ($matchingOus.Count -eq 0) {
        throw "No organizational units found matching '$ouName'"
    }

    # If multiple OUs found, let user choose
    if ($matchingOus.Count -gt 1) {
        Write-Host "`nMultiple OUs found matching '$ouName':" -ForegroundColor Yellow
        for ($i = 0; $i -lt $matchingOus.Count; $i++) {
            $ou = $matchingOus[$i]
            Write-Host "`n$($i + 1). Domain: $($ou.domainName)" -ForegroundColor Cyan
            Write-Host "   Domain ID: $($ou.domainId), OU ID: $($ou.ouId)" -ForegroundColor White
            Write-Host "   Distinguished Name: $($ou.distinguishedName)" -ForegroundColor Gray
        }
        
        $ouChoice = Read-Host "`nEnter the number of the OU to use (1-$($matchingOus.Count))"
        $ouIndex = [int]$ouChoice - 1
        
        if ($ouIndex -lt 0 -or $ouIndex -ge $matchingOus.Count) {
            throw "Invalid OU selection"
        }
        
        $selectedOu = $matchingOus[$ouIndex]
    } else {
        $selectedOu = $matchingOus[0]
        Write-Host "`nFound OU:" -ForegroundColor Green
        Write-Host "  Domain: $($selectedOu.domainName)" -ForegroundColor White
        Write-Host "  Domain ID: $($selectedOu.domainId), OU ID: $($selectedOu.ouId)" -ForegroundColor White
        Write-Host "  Distinguished Name: $($selectedOu.distinguishedName)" -ForegroundColor Gray
    }

    $domainId = $selectedOu.domainId
    $ouId = $selectedOu.ouId

    # Prompt for group type
    Write-Host "`nSelect Group Type:"
    Write-Host "1. SECURITY"
    Write-Host "2. DISTRIBUTION"
    $groupTypeChoice = Read-Host "Enter choice (1 or 2)"
    
    $groupType = switch ($groupTypeChoice) {
        "1" { "SECURITY" }
        "2" { "DISTRIBUTION" }
        default { throw "Invalid group type choice" }
    }

    # Prompt for scope
    Write-Host "`nSelect Group Scope:"
    Write-Host "1. GLOBAL"
    Write-Host "2. LOCAL"
    Write-Host "3. UNIVERSAL"
    $scopeChoice = Read-Host "Enter choice (1, 2, or 3)"
    
    $scope = switch ($scopeChoice) {
        "1" { "GLOBAL" }
        "2" { "LOCAL" }
        "3" { "UNIVERSAL" }
        default { throw "Invalid scope choice" }
    }

    # Display summary
    Write-Host "`n--- Summary ---" -ForegroundColor Cyan
    $summaryTimestamp = Get-Date -Format "dddd, MMMM d, yyyy h:mm:ss tt"
    Write-Host "Timestamp: $summaryTimestamp" -ForegroundColor Green
    Write-Host "Group Name: $groupName" -ForegroundColor Green
    Write-Host "Description: $description" -ForegroundColor Green
    Write-Host "OU: $($selectedOu.distinguishedName)" -ForegroundColor Green
    Write-Host "Domain: $($selectedOu.domainName)" -ForegroundColor Green
    Write-Host "Domain ID: $domainId" -ForegroundColor Green
    Write-Host "OU ID: $ouId" -ForegroundColor Green
    Write-Host "Group Type: $groupType" -ForegroundColor Green
    Write-Host "Scope: $scope" -ForegroundColor Green

    # Create group
    Write-Host "`nCreating group..."
    $createResult = New-Group -Config $config `
                              -GroupName $groupName `
                              -Description $description `
                              -DomainId $domainId `
                              -OuId $ouId `
                              -GroupType $groupType `
                              -Scope $scope

    # Display detailed results
    Write-Host "`n--- Results ---" -ForegroundColor Cyan
    $hasNonSuccess = $false
    foreach ($result in $createResult.Results) {
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
        Write-Host $createResult.Mutation -ForegroundColor Cyan
    }

} catch {
    Write-Host "ERROR: An error occurred in the main script. $_"
    exit 1
}

# Pause to allow user to see the results
Read-Host "`nPress Enter to exit"
