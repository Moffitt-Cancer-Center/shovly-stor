# Varonis’ sample code(s) are provided on an “as is” and “as available” basis and without any warranty of any kind.  
# Any use of Varonis’ sample code(s) is optional at client’s sole discretion, responsibility and risk.
# Varonis does not make any commitment with respect to Varonis’ sample code(s), their specific functions or their availability, reliability, or ability to meet client’s needs.
# Client acknowledges that Varonis may, in its sole discretion, modify, discontinue or update the Varonis’ sample code(s) from time to time, without notice and for any reason.

param(   
    [Parameter(Mandatory=$true)]
    [string]$EntityName,
    
    [Parameter(Mandatory=$true)]
    [string]$QueryFilePath,

    [Parameter(Mandatory=$false)]
    [hashtable]$QueryVariables
)

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Get-GraphQLFiles {
    param(
        [string]$QueryFilePath
    )
    
    # Define the GraphQL file mappings for the provided query file
    $fileMap = @{
            Query = $QueryFilePath
            ExportJob = "..\..\Gql\Common\exportJob.gql"
            ExportNext = "..\..\Gql\Common\exportNext.gql"
        }
            
    # Get the script directory to look for GraphQL files
    $scriptDir = Split-Path -Parent $MyInvocation.ScriptName
    if (-not $scriptDir) {
        $scriptDir = Get-Location
    }
    
    # Check if files exist and return full paths
    $result = @{}
    foreach ($key in $fileMap.Keys) {
        $filePath = $fileMap[$key]
        # Only make Query path absolute if it's not already
        if ($key -eq "Query" -and -not (Test-Path $filePath)) {
            $filePath = Join-Path $scriptDir $filePath
        } elseif ($key -ne "Query") {
            $filePath = Join-Path $scriptDir $filePath
        }
        if (-not (Test-Path $filePath)) {
            throw "GraphQL file not found: $filePath"
        }
        $result[$key] = $filePath
    }
    
    return $result
}

function Get-VaronisAccessToken {
    param(
        [string]$AccessTokenUrl,
        [string]$ApiKey
    )
    
    $headers = @{
        "x-api-key" = $ApiKey
        "Content-Type" = "application/x-www-form-urlencoded"
    }
    
    $body = "grant_type=varonis_custom"
    
    try {
        $response = Invoke-RestMethod -Uri $AccessTokenUrl -Method Post -Headers $headers -Body $body
        return $response.access_token
    }
    catch {
        throw "Error getting access token: $($_.Exception.Message)"
    }
}

function Submit-GraphQLQuery {
    param(
        [string]$Endpoint,
        [string]$AccessTokenUrl,
        [string]$ApiKey,
        [string]$Query,
        [hashtable]$Variables
    )
    
    # Get fresh access token for each request
    $accessToken = Get-VaronisAccessToken -AccessTokenUrl $AccessTokenUrl -ApiKey $ApiKey
    
    $headers = @{
        "Authorization" = "Bearer $accessToken"
        "Content-Type" = "application/json"
    }
    
    $body = @{
        query = $Query
        variables = $Variables
    } | ConvertTo-Json -Depth 10
    
    # Print the actual request data before sending
    Write-Host "`n--- GraphQL Request ---"
    Write-Host "Endpoint: $Endpoint"
    Write-Host "Body:`n$body"
    Write-Host "--- End GraphQL Request ---`n"

    try {
        $response = Invoke-RestMethod -Uri $Endpoint -Method Post -Headers $headers -Body $body
        
        if ($response.errors) {
            throw "GraphQL errors: $($response.errors | ConvertTo-Json)"
        }
        
        Write-Host "result = $($response.data | ConvertTo-Json -Depth 5)"
        
        # Dynamic job ID extraction based on export type
        $jobId = $null
        if ($response.data.auditExportAsync) {
            $jobId = $response.data.auditExportAsync.jobId
        }
        elseif ($response.data.eventsExportAsync) {
            $jobId = $response.data.eventsExportAsync.jobId
        }
        else {
            throw "Unable to extract job ID from response"
        }
        
        Write-Host "Query submitted successfully. Job ID: $jobId"
        return $jobId
    }
    catch {
        throw "Query submission failed: $($_.Exception.Message)"
    }
}

function Get-JobStatus {
    param(
        [string]$Endpoint,
        [string]$AccessTokenUrl,
        [string]$ApiKey,
        [string]$ExportJobQuery,
        [string]$JobId
    )
    
    # Get fresh access token for each request
    $accessToken = Get-VaronisAccessToken -AccessTokenUrl $AccessTokenUrl -ApiKey $ApiKey
    
    $headers = @{
        "Authorization" = "Bearer $accessToken"
        "Content-Type" = "application/json"
    }
    
    $variables = @{
        job_id = $JobId
    }
    
    $body = @{
        query = $ExportJobQuery
        variables = $variables
    } | ConvertTo-Json -Depth 10
    
    try {
        $response = Invoke-RestMethod -Uri $Endpoint -Method Post -Headers $headers -Body $body
        
        if ($response.errors) {
            throw "GraphQL errors: $($response.errors | ConvertTo-Json)"
        }
        
        $jobInfo = $response.data.exportJob
        return @{
            status = $jobInfo.jobStatus
            dataUrl = $jobInfo.dataUrl
            hasMoreData = $jobInfo.hasMoreData
            nextExportCursor = $jobInfo.nextExportCursor
            jobId = $jobInfo.jobId
        }
    }
    catch {
        throw "Status check failed: $($_.Exception.Message)"
    }
}

function Submit-ExportNext {
    param(
        [string]$Endpoint,
        [string]$AccessTokenUrl,
        [string]$ApiKey,
        [string]$ExportNextQuery,
        [string]$Cursor
    )
    
    # Get fresh access token for each request
    $accessToken = Get-VaronisAccessToken -AccessTokenUrl $AccessTokenUrl -ApiKey $ApiKey
    
    $headers = @{
        "Authorization" = "Bearer $accessToken"
        "Content-Type" = "application/json"
    }
    
    $variables = @{
        cursor = $Cursor
    }
    
    $body = @{
        query = $ExportNextQuery
        variables = $variables
    } | ConvertTo-Json -Depth 10
    
    try {
        $response = Invoke-RestMethod -Uri $Endpoint -Method Post -Headers $headers -Body $body
        
        if ($response.errors) {
            throw "GraphQL errors: $($response.errors | ConvertTo-Json)"
        }
        
        $jobInfo = $response.data.exportNextAsync
        return @{
            status = $jobInfo.jobStatus
            dataUrl = $jobInfo.dataUrl
            hasMoreData = $jobInfo.hasMoreData
            nextExportCursor = $jobInfo.nextExportCursor
            jobId = $jobInfo.jobId
        }
    }
    catch {
        throw "Export next failed: $($_.Exception.Message)"
    }
}

function Wait-ForJobCompletion {
    param(
        [string]$Endpoint,
        [string]$AccessTokenUrl,
        [string]$ApiKey,
        [string]$ExportJobQuery,
        [string]$JobId,
        [int]$PollInterval = 25
    )
    
    while ($true) {
        try {
            $statusInfo = Get-JobStatus -Endpoint $Endpoint -AccessTokenUrl $AccessTokenUrl -ApiKey $ApiKey -ExportJobQuery $ExportJobQuery -JobId $JobId
            $status = $statusInfo.status
            
            switch ($status) {
                "COMPLETED" {
                    Write-Host "Job completed successfully!"
                    return $statusInfo
                }
                "FAILED" {
                    Write-Host "Job failed"
                    return $statusInfo
                }
                { $_ -in @("CREATED", "EXECUTING") } {
                    Write-Host "Job status: $status"
                    Start-Sleep -Seconds $PollInterval
                }
                "YIELDED_NO_RESULTS" {
                    Write-Host "Job yielded no results"
                    return $statusInfo
                }
                default {
                    Write-Host "Unexpected job status: $status"
                    Start-Sleep -Seconds $PollInterval
                }
            }
        }
        catch {
            Write-Host "Error checking job status: $($_.Exception.Message)"
            Start-Sleep -Seconds $PollInterval
        }
    }
}

function Download-Results {
    param(
        [string]$DataUrl,
        [string]$AccessTokenUrl,
        [string]$ApiKey,
        [string]$AvroFilename
    )
    
    # Get fresh access token for each request
    $accessToken = Get-VaronisAccessToken -AccessTokenUrl $AccessTokenUrl -ApiKey $ApiKey
    
    $headers = @{
        "Authorization" = "Bearer $accessToken"
    }
    
    try {
        Invoke-WebRequest -Uri $DataUrl -Headers $headers -OutFile $AvroFilename
        Write-Host "Results saved to $AvroFilename"
    }
    catch {
        throw "Results download failed: $($_.Exception.Message)"
    }
}

function Test-JobCompletionStatus {
    param(
        [hashtable]$JobStatus
    )
    
    switch ($JobStatus.status) {
        "FAILED" {
            Write-Host "Query failed or timed out!"
            exit 1
        }
        "YIELDED_NO_RESULTS" {
            Write-Host "Query yielded no results! Ending export"
            exit 0
        }
    }
}

function Convert-DateTimeToString {
    param(
        [object]$Object
    )
    
    if ($Object -is [DateTime]) {
        return $Object.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    }
    elseif ($Object -is [hashtable] -or $Object -is [PSCustomObject]) {
        $converted = @{}
        foreach ($key in $Object.Keys) {
            $converted[$key] = Convert-DateTimeToString -Object $Object[$key]
        }
        return $converted
    }
    elseif ($Object -is [array]) {
        return @($Object | ForEach-Object { Convert-DateTimeToString -Object $_ })
    }
    else {
        return $Object
    }
}

function Save-ResultsToFile {
    param(
        [object]$Results,
        [string]$Filename
    )
    
    $convertedResults = Convert-DateTimeToString -Object $Results
    $convertedResults | ConvertTo-Json -Depth 10 | Out-File -FilePath $Filename -Encoding UTF8
    Write-Host "Results saved to $Filename"
}
function Get-ConfigFile {
    return "config.json"
}

# Main script execution
try {
    Write-Host "Starting Varonis API query for $EntityName export"
    Write-Host "Varonis API query variables:`n$($QueryVariables | ConvertTo-Json -Depth 5)"
    
    # Get GraphQL files based on export type
    $gqlFiles = Get-GraphQLFiles -QueryFilePath $QueryFilePath
    Write-Host "Using GraphQL files:"
    Write-Host "  Query: $($gqlFiles.Query)"
    Write-Host "  Export Job: $($gqlFiles.ExportJob)"
    Write-Host "  Export Next: $($gqlFiles.ExportNext)"
    
    # Read configuration
    $ConfigFile = Get-ConfigFile
    if (-not (Test-Path $ConfigFile)) {
        throw "Config file not found: $ConfigFile"
    }
    $config = Get-Content $ConfigFile | ConvertFrom-Json
    
    $domain = $config.domain
    $endpoint = "https://$domain/api/graphql"
    $accessTokenUrl = "https://$domain/api/authentication/api_keys/token"
    $apiKey = $config.api_key
    
    Write-Host "Using domain: $domain"
    Write-Host "GraphQL endpoint: $endpoint"
    Write-Host "Token endpoint: $accessTokenUrl"
    
    # Read GraphQL queries
    $query = Get-Content $gqlFiles.Query -Raw
    $exportJobQuery = Get-Content $gqlFiles.ExportJob -Raw
    $exportNextQuery = Get-Content $gqlFiles.ExportNext -Raw
        
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $baseFolder = "exports_$($EntityName.ToLower())_$timestamp"
    
    if (-not (Test-Path $baseFolder)) {
        New-Item -ItemType Directory -Path $baseFolder | Out-Null
    }
    
    # Submit initial query (token will be refreshed inside the function)
    $jobId = Submit-GraphQLQuery -Endpoint $endpoint -AccessTokenUrl $accessTokenUrl -ApiKey $apiKey -Query $query -Variables $QueryVariables
    
    while ($true) {
        # Wait for completion (token will be refreshed for each status check)
        $jobStatus = Wait-ForJobCompletion -Endpoint $endpoint -AccessTokenUrl $accessTokenUrl -ApiKey $apiKey -ExportJobQuery $exportJobQuery -JobId $jobId
        Test-JobCompletionStatus -JobStatus $jobStatus
        
        # Generate filename with timestamp
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $baseFilename = "$($EntityName.ToLower())_result_$timestamp"
        $baseFilePath = Join-Path $baseFolder "$baseFilename"
        
        Write-Host "Downloading..."
        $filenameAvro = "$baseFilePath.avro"
        # Token will be refreshed inside Download-Results function
        Download-Results -DataUrl $jobStatus.dataUrl -AccessTokenUrl $accessTokenUrl -ApiKey $apiKey -AvroFilename $filenameAvro
        Write-Host "Downloaded file: $filenameAvro"

        # Check if hasMoreData is false - if so, stop the export
        if ($jobStatus.hasMoreData -eq $false) {
            Write-Host "No more data to export. Export completed successfully!"
            break
        }

        Write-Host "Calling exportNextAsync"
        # Token will be refreshed inside Submit-ExportNext function
        $nextResult = Submit-ExportNext -Endpoint $endpoint -AccessTokenUrl $accessTokenUrl -ApiKey $apiKey -ExportNextQuery $exportNextQuery -Cursor $jobStatus.nextExportCursor
        $jobId = $nextResult.jobId
    }
}
catch {
    Write-Host "Error: $($_.Exception.Message)"
    exit 1
}