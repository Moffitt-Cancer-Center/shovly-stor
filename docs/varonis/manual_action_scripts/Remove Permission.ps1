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

function Get-PhysicalPermissions {
    param (
        [object]$Config,
        [int]$FilerId,
        [string]$DirEntityIdx,
        [int]$PathDepth
    )

    $token = Get-AccessToken($Config)
    $url = "https://$($Config.domain)/api/graphql"
    $headers = @{
        "Authorization" = "Bearer $token"
        "Content-Type" = "application/json"
    }

    # GraphQL query to get physical permissions asynchronously
    $query = @"
    query aceIdQuery {
        physicalPermissionsAsync (
            where: {
                isUniquePermission: {eq: true}
                resource: {pathDepth: {eq: $PathDepth}}
                dataSource: {id: {eq: $FilerId}}
            }
        ) {
            jobId
            jobProgress
            jobStatus
            results {
                resource {
                    id
                    name
                    path
                }
                identity {
                    id
                    directoryServices {name, id}
                    name
                }
                permissionFlag {name}
                aceId
            }
        }
    }
"@
    $body = @{ query = $query } | ConvertTo-Json

    try {
        $response = Invoke-RestMethod -Uri $url -Method Post -Headers $headers -Body $body
        $jobId = $response.data.physicalPermissionsAsync.jobId
        $jobStatus = $response.data.physicalPermissionsAsync.jobStatus

        # Poll for job completion if status is "EXECUTING"
        while ($jobStatus -eq "EXECUTING") {
            Start-Sleep -Seconds 2

            # Query for job results
            $pollQuery = @"
            query aceIdResults {
                physicalPermissionsQueryJob (
                    jobId: "$jobId"
                ) {
                    jobId
                    jobProgress
                    jobStatus
                    results {
                        resource {
                            id
                            name
                            path
                        }
                        identity {
                            id
                            directoryServices {name, id}
                            name
                        }
                        permissionFlag {name}
                        aceId
                    }
                }
            }
"@
            $pollBody = @{ query = $pollQuery } | ConvertTo-Json
            $pollResponse = Invoke-RestMethod -Uri $url -Method Post -Headers $headers -Body $pollBody
            $jobStatus = $pollResponse.data.physicalPermissionsQueryJob.jobStatus

            # If job is complete, get the results
            if ($jobStatus -ne "EXECUTING") {
                $results = $pollResponse.data.physicalPermissionsQueryJob.results
                return $results
            }
        }

        # If job completed immediately, return the results
        if ($response.data.physicalPermissionsAsync.results) {
            $results = $response.data.physicalPermissionsAsync.results
            return $results
        }
    } catch {
        Write-Host "ERROR: Failed to retrieve physical permissions. $_"
        exit 1
    }
}

function Remove-Permission {
    param (
        [object]$Config,
        [int]$SidId,
        [string]$AceIds,
        [int]$FilerId,
        [string]$DirEntityIdx
    )

    $token = Get-AccessToken($Config)
    $url = "https://$($Config.domain)/api/graphql"
    $headers = @{
        "Authorization" = "Bearer $token"
        "Content-Type" = "application/json"
    }

    # GraphQL mutation to remove permission
    $mutation = @"
    mutation removePermission {
        createActionRequest (input: {
            createOption: PENDING_REVIEW
            requestOrigin: MANUAL_ACTIONS
            requestInput: {
                removePermission: {
                    cifs: {
                        configuration: {
                            account: {
                                sidId: $SidId
                            }
                            aceIds: "$AceIds"
                            resource: {
                                filerId: $FilerId
                                dirEntityIdx: "$DirEntityIdx"
                            }
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
            if ($result.status -eq "INTERNAL_ERROR" -or $result.status -like "*ERROR*") {
                Write-Host "    Action Request ID: $($result.actionRequestId)" -ForegroundColor Red
                Write-Host "    Status: $($result.status)" -ForegroundColor Red
            } else {
                Write-Host "    Action Request ID: $($result.actionRequestId)" -ForegroundColor Green
                Write-Host "    Status: $($result.status)" -ForegroundColor Green
            }
            
            if ($result.failureMessage) {
                Write-Host "    Failure Message: $($result.failureMessage)" -ForegroundColor Red
            }
            Write-Host ""
        }
        
        # If any result is not SUCCESS, show the mutation for debugging
        if ($results | Where-Object { $_.status -ne "SUCCESS" }) {
            Write-Host "Mutation that was executed:" -ForegroundColor Yellow
            Write-Host $mutation -ForegroundColor Cyan
        }
        
        return $results
    } catch {
        Write-Host "`nERROR: Failed to execute remove permission mutation. $_" -ForegroundColor Red
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

    Write-Host "`n--- Remove Permission ---" -ForegroundColor Cyan

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
    $folderPath = Read-Host "`nEnter the folder path (e.g., C:\Windows)"
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

    # Get permissions for the folder
    Write-Host "`nFetching permissions for the folder..."
    $permissions = Get-PhysicalPermissions -Config $config -FilerId $filerId -DirEntityIdx $dirEntityIdx -PathDepth $pathDepth
    
    if ($permissions.Count -eq 0) {
        throw "No unique permissions found for this folder"
    }

    # Filter permissions for the selected folder
    $folderPermissions = $permissions | Where-Object { $_.resource.id -eq $dirEntityIdx }
    
    if ($folderPermissions.Count -eq 0) {
        throw "No permissions found for the selected folder"
    }

    # Display all permissions on the folder
    Write-Host "`n--- Permissions on this folder ---" -ForegroundColor Cyan
    for ($i = 0; $i -lt $folderPermissions.Count; $i++) {
        $perm = $folderPermissions[$i]
        $domain = $perm.identity.directoryServices.name
        $user = $perm.identity.name
        $permission = $perm.permissionFlag.name
        Write-Host "$($i + 1). $domain\$user - $permission" -ForegroundColor White
    }

    # Select permission to remove
    $permChoice = Read-Host "`nEnter the number of the permission to remove (1-$($folderPermissions.Count))"
    $permIndex = [int]$permChoice - 1
    
    if ($permIndex -lt 0 -or $permIndex -ge $folderPermissions.Count) {
        throw "Invalid permission selection"
    }
    
    $selectedPermission = $folderPermissions[$permIndex]

    $sidId = [int]$selectedPermission.identity.id
    $aceIds = $selectedPermission.aceId
    $domainName = $selectedPermission.identity.directoryServices.name
    $samAccountName = $selectedPermission.identity.name

    # Display summary
    Write-Host "`n--- Summary ---" -ForegroundColor Cyan
    $summaryTimestamp = Get-Date -Format "dddd, MMMM d, yyyy h:mm:ss tt"
    Write-Host "Timestamp: $summaryTimestamp" -ForegroundColor Green
    Write-Host "Data Source: $($selectedDataSource.name)" -ForegroundColor Green
    Write-Host "Filer ID: $filerId" -ForegroundColor Green
    Write-Host "Folder Path: $($selectedResource.path)" -ForegroundColor Green
    Write-Host "DirEntityIdx: $dirEntityIdx" -ForegroundColor Green
    Write-Host "Account: $domainName\$samAccountName" -ForegroundColor Green
    Write-Host "SidId: $sidId" -ForegroundColor Green
    Write-Host "Permission: $($selectedPermission.permissionFlag.name)" -ForegroundColor Green
    Write-Host "AceId: $aceIds" -ForegroundColor Green

    # Remove permission
    Write-Host "`nRemoving permission..."
    $removeResult = Remove-Permission -Config $config `
                                     -SidId $sidId `
                                     -AceIds $aceIds `
                                     -FilerId $filerId `
                                     -DirEntityIdx $dirEntityIdx

    # Display detailed results
    Write-Host "`n--- Results ---" -ForegroundColor Cyan
    $hasNonSuccess = $false
    foreach ($result in $removeResult.Results) {
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
        Write-Host $removeResult.Mutation -ForegroundColor Cyan
    }

} catch {
    Write-Host "ERROR: An error occurred in the main script. $_"
    exit 1
}

# Pause to allow user to see the results
Read-Host "`nPress Enter to exit"
