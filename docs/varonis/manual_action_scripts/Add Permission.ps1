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

function Get-DataSources {
    param (
        [object]$Config,
        [string]$Type = "WINDOWS"
    )

    $token = Get-AccessToken($Config)
    $url = "https://$($Config.domain)/api/graphql"
    $headers = @{
        "Authorization" = "Bearer $token"
        "Content-Type" = "application/json"
    }

    # GraphQL query to get data sources asynchronously
    $query = @"
    query getDataSourcesQuery {
        dataSourcesAsync (
            where: {
                type: {eq: $Type}
            }
        ) {
            jobId
            jobProgress
            jobStatus
            results {
                name
                id
            }
        }
    }
"@
    $body = @{ query = $query } | ConvertTo-Json

    try {
        $response = Invoke-RestMethod -Uri $url -Method Post -Headers $headers -Body $body
        $jobId = $response.data.dataSourcesAsync.jobId
        $jobStatus = $response.data.dataSourcesAsync.jobStatus

        # Poll for job completion if status is "EXECUTING"
        while ($jobStatus -eq "EXECUTING") {
            Start-Sleep -Seconds 2

            # Query for job results
            $pollQuery = @"
            query getDataSourcesResult {
                dataSourcesQueryJob (
                    jobId: "$jobId"
                ) {
                    jobId
                    jobStatus
                    results {
                        name
                        id
                    }
                }
            }
"@
            $pollBody = @{ query = $pollQuery } | ConvertTo-Json
            $pollResponse = Invoke-RestMethod -Uri $url -Method Post -Headers $headers -Body $pollBody
            $jobStatus = $pollResponse.data.dataSourcesQueryJob.jobStatus

            # If job is complete, get the results
            if ($jobStatus -ne "EXECUTING") {
                $results = $pollResponse.data.dataSourcesQueryJob.results
                return @($results)
            }
        }

        # If job completed immediately, return the results
        if ($response.data.dataSourcesAsync.results) {
            $results = $response.data.dataSourcesAsync.results
            return @($results)
        }
        
        return @()
    } catch {
        Write-Host "ERROR: Failed to retrieve data sources. $_"
        exit 1
    }
}

function Get-Resources {
    param (
        [object]$Config,
        [int]$FilerId,
        [int]$PathDepth
    )

    $token = Get-AccessToken($Config)
    $url = "https://$($Config.domain)/api/graphql"
    $headers = @{
        "Authorization" = "Bearer $token"
        "Content-Type" = "application/json"
    }

    # GraphQL query to get resources asynchronously
    $query = @"
    query getResourcesQuery {
        resourcesAsync (where: {
            pathDepth: {eq: $PathDepth}
            dataSource: {id: {eq: $FilerId}}
        }) {
            jobId
            jobProgress
            jobStatus
            results {
                name
                path
                id
            }
        }
    }
"@
    $body = @{ query = $query } | ConvertTo-Json

    try {
        $response = Invoke-RestMethod -Uri $url -Method Post -Headers $headers -Body $body
        $jobId = $response.data.resourcesAsync.jobId
        $jobStatus = $response.data.resourcesAsync.jobStatus

        # Poll for job completion if status is "EXECUTING"
        while ($jobStatus -eq "EXECUTING") {
            Start-Sleep -Seconds 2

            # Query for job results
            $pollQuery = @"
            query getResourcesResult {
                resourcesQueryJob (
                    jobId: "$jobId"
                ) {
                    jobId
                    jobProgress
                    jobStatus
                    results {
                        name
                        path
                        id
                    }
                }
            }
"@
            $pollBody = @{ query = $pollQuery } | ConvertTo-Json
            $pollResponse = Invoke-RestMethod -Uri $url -Method Post -Headers $headers -Body $pollBody
            $jobStatus = $pollResponse.data.resourcesQueryJob.jobStatus

            # If job is complete, get the results
            if ($jobStatus -ne "EXECUTING") {
                $results = $pollResponse.data.resourcesQueryJob.results
                return @($results)
            }
        }

        # If job completed immediately, return the results
        if ($response.data.resourcesAsync.results) {
            $results = $response.data.resourcesAsync.results
            return @($results)
        }
        
        return @()
    } catch {
        Write-Host "ERROR: Failed to retrieve resources. $_"
        exit 1
    }
}

function Add-Permission {
    param (
        [object]$Config,
        [array]$Accounts,
        [int]$FilerId,
        [string]$DirEntityIdx,
        [string]$PermissionType, # "basic" or "custom"
        [string]$BasePermission = $null, # For basic permissions: ALLOW, MODIFY, etc.
        [string]$AceMask = $null, # For custom permissions
        [string]$AceFlags = $null # For custom permissions
    )

    $token = Get-AccessToken($Config)
    $url = "https://$($Config.domain)/api/graphql"
    $headers = @{
        "Authorization" = "Bearer $token"
        "Content-Type" = "application/json"
    }

    # Build accounts array from domain name and sam account name
    $accountsArray = ($Accounts | ForEach-Object { 
        "{domainAndSamAccountName: {domainName: `"$($_.DomainName)`" samAccountName: `"$($_.SamAccountName)`"}}" 
    }) -join ', '

    # Build permission configuration based on type
    if ($PermissionType -eq "basic") {
        $permissionConfig = @"
permission: {
                                aceType: ALLOW
                                permissionInput: {
                                    basePermission: $BasePermission
                                }
                            }
"@
    } else {
        $permissionConfig = @"
permission: {
                                aceType: ALLOW
                                permissionInput: {
                                    customPermission: {
                                        aceMask: $AceMask
                                        aceFlags: $AceFlags
                                    }
                                }
                            }
"@
    }

    # GraphQL mutation to add permission
    $mutation = @"
    mutation addPermission {
        createActionRequest (input: {
            createOption: PENDING_REVIEW
            requestOrigin: MANUAL_ACTIONS
            requestInput: {
                addPermission: {
                    cifs: {
                        configuration: {
                            accounts: [$accountsArray]
                            resource: {
                                filerId: $FilerId
                                dirEntityIdx: "$DirEntityIdx"
                            }
                            $permissionConfig
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
            Write-Host "    Status: $($result.status)" -ForegroundColor Green
            if ($result.failureMessage) {
                Write-Host "    Failure Message: $($result.failureMessage)" -ForegroundColor Red
            }
            Write-Host ""
        }
        
        return $results
    } catch {
        Write-Host "`nERROR: Failed to execute add permission mutation. $_" -ForegroundColor Red
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

    Write-Host "`n--- Add Permission ---" -ForegroundColor Cyan

    # Get data sources for CIFS-capable platforms
    $cifsDataSourceTypes = @("WINDOWS", "UNIX", "UNIX_SMB", "NET_APP", "NET_APP_CM", "DELL_UNITY", "DELL_POWER_STORE", "DELL_SMB", "DELL_EMC_POWER_SCALE_ONE_FS_ISILON", "HITACHI_NAS", "HP_NAS", "NASUNI", "QUMULO", "AMAZON_F_SX_FOR_WINDOWS", "AZURE_FILES", "AZURE_NET_APP_FILES")
    Write-Host "`nFetching CIFS data sources..."
    $dataSources = @()
    foreach ($dataSourceType in $cifsDataSourceTypes) {
        $dataSources += @(Get-DataSources -Config $config -Type $dataSourceType)
    }
    $dataSources = @($dataSources | Sort-Object -Property id -Unique)
    
    if ($dataSources.Count -eq 0) {
        throw "No CIFS data sources found"
    }

    # Sort data sources by ID (ascending)
    $dataSources = @($dataSources | Sort-Object -Property { [int]$_.id })

    # Display data sources
    Write-Host "`nAvailable Data Sources:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $dataSources.Count; $i++) {
        $ds = $dataSources[$i]
        Write-Host "$($i + 1). Name: $($ds.name), ID: $($ds.id)" -ForegroundColor White
    }

    # Select data source
    if ($dataSources.Count -eq 1) {
        $selectedDataSource = $dataSources[0]
        Write-Host "`nUsing data source: $($selectedDataSource.name) (ID: $($selectedDataSource.id))" -ForegroundColor Green
    } else {
        $dsChoice = Read-Host "`nEnter the number of the data source (1-$($dataSources.Count))"
        $dsIndex = [int]$dsChoice - 1
        
        if ($dsIndex -lt 0 -or $dsIndex -ge $dataSources.Count) {
            throw "Invalid data source selection"
        }
        
        $selectedDataSource = $dataSources[$dsIndex]
        Write-Host "Selected: $($selectedDataSource.name) (ID: $($selectedDataSource.id))" -ForegroundColor Green
    }

    $filerId = [int]$selectedDataSource.id

    # Get folder path and calculate depth
    $folderPath = Read-Host "`nEnter the folder path (e.g., C:\Packages)"
    if ([string]::IsNullOrWhiteSpace($folderPath)) {
        throw "Folder path cannot be empty"
    }

    # Calculate folder depth
    $pathDepth = ($folderPath.TrimEnd('\') -split '\\').Count
    Write-Host "Calculated folder depth: $pathDepth" -ForegroundColor Gray

    # Get resources at this depth
    Write-Host "`nFetching folders at depth $pathDepth..."
    $resources = @(Get-Resources -Config $config -FilerId $filerId -PathDepth $pathDepth)
    
    if ($resources.Count -eq 0) {
        throw "No folders found at depth $pathDepth"
    }

    # Search for matching folder
    $matchingResources = @($resources | Where-Object { $_.path -like "*$folderPath*" -or $_.path -eq $folderPath })

    if ($matchingResources.Count -eq 0) {
        Write-Host "`nNo exact match found. Showing all folders at depth ${pathDepth}:" -ForegroundColor Yellow
        for ($i = 0; $i -lt [Math]::Min($resources.Count, 20); $i++) {
            $res = $resources[$i]
            Write-Host "$($i + 1). Path: $($res.path), ID: $($res.id)" -ForegroundColor White
        }
        if ($resources.Count -gt 20) {
            Write-Host "... and $($resources.Count - 20) more folders" -ForegroundColor Gray
        }
        
        $resChoice = Read-Host "`nEnter the number of the folder (1-$($resources.Count))"
        $resIndex = [int]$resChoice - 1
        
        if ($resIndex -lt 0 -or $resIndex -ge $resources.Count) {
            throw "Invalid folder selection"
        }
        
        $selectedResource = $resources[$resIndex]
    } elseif ($matchingResources.Count -gt 1) {
        Write-Host "`nMultiple folders found matching '$folderPath':" -ForegroundColor Yellow
        for ($i = 0; $i -lt $matchingResources.Count; $i++) {
            $res = $matchingResources[$i]
            Write-Host "$($i + 1). Path: $($res.path), ID: $($res.id)" -ForegroundColor White
        }
        
        $resChoice = Read-Host "`nEnter the number of the folder (1-$($matchingResources.Count))"
        $resIndex = [int]$resChoice - 1
        
        if ($resIndex -lt 0 -or $resIndex -ge $matchingResources.Count) {
            throw "Invalid folder selection"
        }
        
        $selectedResource = $matchingResources[$resIndex]
    } else {
        $selectedResource = $matchingResources[0]
        Write-Host "`nFound folder:" -ForegroundColor Green
        Write-Host "  Path: $($selectedResource.path)" -ForegroundColor White
        Write-Host "  ID: $($selectedResource.id)" -ForegroundColor White
    }

    $dirEntityIdx = $selectedResource.id

    # Get account information (can add multiple users)
    Write-Host "`n--- Account Information ---" -ForegroundColor Cyan
    $accounts = @()
    
    do {
        Write-Host "`nEnter account details:" -ForegroundColor Cyan
        $domainName = Read-Host "Domain Name"
        if ([string]::IsNullOrWhiteSpace($domainName)) {
            throw "Domain Name cannot be empty"
        }
        
        $samAccountName = Read-Host "Sam Account Name"
        if ([string]::IsNullOrWhiteSpace($samAccountName)) {
            throw "Sam Account Name cannot be empty"
        }
        
        $accounts += @{
            DomainName = $domainName
            SamAccountName = $samAccountName
        }
        
        Write-Host "Added: $domainName\$samAccountName" -ForegroundColor Green
        
        $addAnother = Read-Host "`nAdd another user? (y/n)"
    } while ($addAnother -eq "y" -or $addAnother -eq "Y")

    # Ask for permission type
    Write-Host "`n--- Permission Type ---" -ForegroundColor Cyan
    Write-Host "1. Basic Permission"
    Write-Host "2. Custom Permission"
    $permTypeChoice = Read-Host "Enter choice (1 or 2)"

    if ($permTypeChoice -eq "1") {
        # Basic permission
        $permissionType = "basic"
        
        Write-Host "Select Base Permission:" -ForegroundColor Cyan
        Write-Host "1. FULL_CONTROL"
        Write-Host "2. LIST_FOLDER_CONTENT"
        Write-Host "3. MODIFY"
        Write-Host "4. READ_AND_EXECUTE"
        Write-Host "5. READ_ONLY"
        Write-Host "6. WRITE"
        $basePermChoice = Read-Host "Enter choice (1-6)"
        
        $basePermission = switch ($basePermChoice) {
            "1" { "FULL_CONTROL" }
            "2" { "LIST_FOLDER_CONTENT" }
            "3" { "MODIFY" }
            "4" { "READ_AND_EXECUTE" }
            "5" { "READ_ONLY" }
            "6" { "WRITE" }
            default { throw "Invalid base permission choice" }
        }
        
        $aceMask = $null
        $aceFlags = $null
    } else {
        # Custom permission
        $permissionType = "custom"
        
        Write-Host "`n--- Custom Permission ---" -ForegroundColor Cyan
        $aceMask = Read-Host "Enter AceMask (e.g., 1245631)"
        if ([string]::IsNullOrWhiteSpace($aceMask)) {
            throw "AceMask cannot be empty"
        }
        
        $aceFlags = Read-Host "Enter AceFlags (e.g., 11)"
        if ([string]::IsNullOrWhiteSpace($aceFlags)) {
            throw "AceFlags cannot be empty"
        }
        
        $basePermission = $null
    }

    # Display summary
    Write-Host "`n--- Summary ---" -ForegroundColor Cyan
    $summaryTimestamp = Get-Date -Format "dddd, MMMM d, yyyy h:mm:ss tt"
    Write-Host "Timestamp: $summaryTimestamp" -ForegroundColor Green
    Write-Host "Data Source: $($selectedDataSource.name)" -ForegroundColor Green
    Write-Host "Filer ID: $filerId" -ForegroundColor Green
    Write-Host "Folder Path: $($selectedResource.path)" -ForegroundColor Green
    Write-Host "DirEntityIdx: $dirEntityIdx" -ForegroundColor Green
    Write-Host "Accounts:" -ForegroundColor Green
    foreach ($account in $accounts) {
        Write-Host "  $($account.DomainName)\$($account.SamAccountName)" -ForegroundColor Green
    }
    if ($permissionType -eq "basic") {
        Write-Host "Permission Type: Basic" -ForegroundColor Green
        Write-Host "Base Permission: $basePermission" -ForegroundColor Green
    } else {
        Write-Host "Permission Type: Custom" -ForegroundColor Green
        Write-Host "AceMask: $aceMask" -ForegroundColor Green
        Write-Host "AceFlags: $aceFlags" -ForegroundColor Green
    }

    # Add permission
    Write-Host "`nAdding permission..."
    $addResult = Add-Permission -Config $config `
                               -Accounts $accounts `
                               -FilerId $filerId `
                               -DirEntityIdx $dirEntityIdx `
                               -PermissionType $permissionType `
                               -BasePermission $basePermission `
                               -AceMask $aceMask `
                               -AceFlags $aceFlags

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
