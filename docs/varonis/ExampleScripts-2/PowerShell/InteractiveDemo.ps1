# Varonis' sample code(s) are provided on an "as is" and "as available" basis and without any warranty of any kind.  
# Any use of Varonis' sample code(s) is optional at client's sole discretion, responsibility and risk.
# Varonis does not make any commitment with respect to Varonis' sample code(s), their specific functions or their availability, reliability, or ability to meet client's needs.
# Client acknowledges that Varonis may, in its sole discretion, modify, discontinue or update the Varonis' sample code(s) from time to time, without notice and for any reason.

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

#region Helper Functions

function Write-StepHeader {
    param([string]$Message, [int]$Delay = 800)
    
    Write-Host "`n" -NoNewline
    Write-Host "====================================================================" -ForegroundColor Cyan
    Write-Host "  $Message" -ForegroundColor Yellow
    Write-Host "====================================================================" -ForegroundColor Cyan
    Start-Sleep -Milliseconds $Delay
}

function Write-InfoMessage {
    param([string]$Message, [int]$Delay = 500)
    
    Write-Host "  [i] " -ForegroundColor Cyan -NoNewline
    Write-Host $Message -ForegroundColor White
    Start-Sleep -Milliseconds $Delay
}

function Write-SuccessMessage {
    param([string]$Message, [int]$Delay = 600)
    
    Write-Host "  [+] " -ForegroundColor Green -NoNewline
    Write-Host $Message -ForegroundColor White
    Start-Sleep -Milliseconds $Delay
}

function Write-WarningMessage {
    param([string]$Message, [int]$Delay = 600)
    
    Write-Host "  [!] " -ForegroundColor Yellow -NoNewline
    Write-Host $Message -ForegroundColor White
    Start-Sleep -Milliseconds $Delay
}

function Write-ErrorMessage {
    param([string]$Message)
    
    Write-Host "  [-] " -ForegroundColor Red -NoNewline
    Write-Host $Message -ForegroundColor White
}

function Write-ProgressBar {
    param([string]$Status, [int]$Delay = 1000)
    
    Write-Host "  " -NoNewline
    for ($i = 0; $i -lt 10; $i++) {
        Write-Host "#" -ForegroundColor Cyan -NoNewline
        Start-Sleep -Milliseconds ($Delay / 10)
    }
    Write-Host " $Status" -ForegroundColor Gray
}

function Show-WelcomeBanner {
    Clear-Host
    Write-Host ""
    Write-Host "====================================================================" -ForegroundColor Magenta
    Write-Host "                                                                    " -ForegroundColor Magenta
    Write-Host "         VARONIS DATA QUERY LAYER - INTERACTIVE DEMO" -ForegroundColor Yellow
    Write-Host "                                                                    " -ForegroundColor Magenta
    Write-Host "              Interactive Export Data Demonstration                 " -ForegroundColor White
    Write-Host "                                                                    " -ForegroundColor Magenta
    Write-Host "====================================================================" -ForegroundColor Magenta
    Write-Host ""
    Start-Sleep -Milliseconds 1500
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
        Write-InfoMessage "Requesting access token..."
        $response = Invoke-RestMethod -Uri $AccessTokenUrl -Method Post -Headers $headers -Body $body
        Write-SuccessMessage "Access token obtained successfully"
        return $response.access_token
    }
    catch {
        Write-ErrorMessage "Failed to get access token: $($_.Exception.Message)"
        throw
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
    
    Write-InfoMessage "Authenticating with Lab environment..."
    $accessToken = Get-VaronisAccessToken -AccessTokenUrl $AccessTokenUrl -ApiKey $ApiKey
    
    $headers = @{
        "Authorization" = "Bearer $accessToken"
        "Content-Type" = "application/json"
    }
    
    $body = @{
        query = $Query
        variables = $Variables
    } | ConvertTo-Json -Depth 10
    
    Write-Host ""
    Write-Host "  >> Submitting GraphQL Query..." -ForegroundColor Cyan
    Write-Host "  --------------------------------------------" -ForegroundColor DarkGray
    Write-Host "  | Endpoint: " -ForegroundColor DarkGray -NoNewline
    Write-Host $Endpoint -ForegroundColor Gray
    Write-Host "  | Query Variables:" -ForegroundColor DarkGray
    $Variables.GetEnumerator() | ForEach-Object {
        Write-Host "  |   - $($_.Key): " -ForegroundColor DarkGray -NoNewline
        Write-Host $_.Value -ForegroundColor Gray
    }
    Write-Host "  --------------------------------------------" -ForegroundColor DarkGray
    Start-Sleep -Milliseconds 1200

    try {
        $response = Invoke-RestMethod -Uri $Endpoint -Method Post -Headers $headers -Body $body
        
        if ($response.errors) {
            Write-ErrorMessage "GraphQL returned errors: $($response.errors | ConvertTo-Json)"
            throw "GraphQL errors encountered"
        }
        
        # Dynamic job ID extraction
        $jobId = $null
        if ($response.data.auditExportAsync) {
            $jobId = $response.data.auditExportAsync.jobId
        }
        elseif ($response.data.eventsExportAsync) {
            $jobId = $response.data.eventsExportAsync.jobId
        }
        else {
            Write-ErrorMessage "Unable to extract job ID from response"
            throw "Unable to extract job ID from response"
        }
        
        Write-SuccessMessage "Query submitted successfully!"
        Write-Host "  Job ID: " -ForegroundColor White -NoNewline
        Write-Host $jobId -ForegroundColor Cyan
        Start-Sleep -Milliseconds 800
        
        return $jobId
    }
    catch {
        Write-ErrorMessage "Query submission failed: $($_.Exception.Message)"
        throw
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
            Write-ErrorMessage "GraphQL errors: $($response.errors | ConvertTo-Json)"
            throw "GraphQL errors encountered"
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
        Write-ErrorMessage "Status check failed: $($_.Exception.Message)"
        throw
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
    
    Write-InfoMessage "Requesting next batch of data..."
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
            Write-ErrorMessage "GraphQL errors: $($response.errors | ConvertTo-Json)"
            throw "GraphQL errors encountered"
        }
        
        $jobInfo = $response.data.exportNextAsync
        Write-SuccessMessage "Next export job submitted"
        Start-Sleep -Milliseconds 600
        
        return @{
            status = $jobInfo.jobStatus
            dataUrl = $jobInfo.dataUrl
            hasMoreData = $jobInfo.hasMoreData
            nextExportCursor = $jobInfo.nextExportCursor
            jobId = $jobInfo.jobId
        }
    }
    catch {
        Write-ErrorMessage "Export next failed: $($_.Exception.Message)"
        throw
    }
}

function Get-AvroRecordCount {
    param([string]$AvroFilePath)
    
    try {
        $pythonCmd = Get-PythonExecutable
        $pythonScript = @"
import sys
from fastavro import reader
count = 0
with open(sys.argv[1], 'rb') as f:
    for _ in reader(f):
        count += 1
print(count)
"@
        $result = $pythonScript | & $pythonCmd - $AvroFilePath 2>&1
        if ($result -match '^\d+$') {
            return [int]$result
        }
        return 0
    }
    catch {
        return 0
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
    
    Write-Host ""
    Write-Host "  [*] Waiting for job completion..." -ForegroundColor Yellow
    $iteration = 0
    
    while ($true) {
        try {
            $statusInfo = Get-JobStatus -Endpoint $Endpoint -AccessTokenUrl $AccessTokenUrl -ApiKey $ApiKey -ExportJobQuery $ExportJobQuery -JobId $JobId
            $status = $statusInfo.status
            $iteration++
            
            switch ($status) {
                "COMPLETED" {
                    Write-Host ""
                    Write-SuccessMessage "Job completed successfully!"
                    Write-Host "  | Data URL available: " -ForegroundColor DarkGray -NoNewline
                    Write-Host "YES" -ForegroundColor Green
                    Write-Host "  | Has More Data: " -ForegroundColor DarkGray -NoNewline
                    if ($statusInfo.hasMoreData) {
                        Write-Host "YES" -ForegroundColor Yellow
                    } else {
                        Write-Host "NO" -ForegroundColor Green
                    }
                    Start-Sleep -Milliseconds 800
                    return $statusInfo
                }
                "FAILED" {
                    Write-Host ""
                    Write-ErrorMessage "Job failed"
                    return $statusInfo
                }
                { $_ -in @("CREATED", "EXECUTING") } {
                    Write-Host "  | Check #$iteration - Status: " -ForegroundColor DarkGray -NoNewline
                    Write-Host $status -ForegroundColor Yellow
                    Start-Sleep -Seconds $PollInterval
                }
                "YIELDED_NO_RESULTS" {
                    Write-Host ""
                    Write-WarningMessage "Job yielded no results"
                    return $statusInfo
                }
                default {
                    Write-Host "  | Check #$iteration - Unexpected status: " -ForegroundColor DarkGray -NoNewline
                    Write-Host $status -ForegroundColor Magenta
                    Start-Sleep -Seconds $PollInterval
                }
            }
        }
        catch {
            Write-ErrorMessage "Error checking job status: $($_.Exception.Message)"
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
    
    Write-InfoMessage "Preparing to download results..."
    $accessToken = Get-VaronisAccessToken -AccessTokenUrl $AccessTokenUrl -ApiKey $ApiKey
    
    $headers = @{
        "Authorization" = "Bearer $accessToken"
    }
    
    try {
        Write-Host "  >> Downloading data..." -ForegroundColor Cyan
        Write-ProgressBar "Transferring data"
        
        Invoke-WebRequest -Uri $DataUrl -Headers $headers -OutFile $AvroFilename
        
        $fileSize = (Get-Item $AvroFilename).Length
        $fileSizeKB = [math]::Round($fileSize / 1KB, 2)
        
        Write-SuccessMessage "Results downloaded successfully!"
        Write-Host "  | File: " -ForegroundColor DarkGray -NoNewline
        Write-Host $AvroFilename -ForegroundColor Cyan
        Write-Host "  | Size: " -ForegroundColor DarkGray -NoNewline
        Write-Host "$fileSizeKB KB" -ForegroundColor White
        Start-Sleep -Milliseconds 1000
    }
    catch {
        Write-ErrorMessage "Download failed: $($_.Exception.Message)"
        throw
    }
}

function Test-JobCompletionStatus {
    param([hashtable]$JobStatus)
    
    switch ($JobStatus.status) {
        "FAILED" {
            Write-ErrorMessage "Query failed or timed out!"
            Write-Host ""
            exit 1
        }
        "YIELDED_NO_RESULTS" {
            Write-WarningMessage "Query yielded no results! Ending export"
            Write-Host ""
            exit 0
        }
    }
}

function Get-GraphQLFiles {
    param([string]$QueryFilePath)
    
    $scriptDir = Split-Path -Parent $MyInvocation.ScriptName
    if (-not $scriptDir) {
        $scriptDir = Get-Location
    }
    
    $fileMap = @{
        Query = $QueryFilePath
        ExportJob = Join-Path $scriptDir "..\Gql\Common\exportJob.gql"
        ExportNext = Join-Path $scriptDir "..\Gql\Common\exportNext.gql"
    }
    
    $result = @{}
    foreach ($key in $fileMap.Keys) {
        $filePath = $fileMap[$key]
        if ($key -eq "Query" -and -not (Test-Path $filePath)) {
            $filePath = Join-Path $scriptDir $filePath
        }
        if (-not (Test-Path $filePath)) {
            Write-ErrorMessage "GraphQL file not found: $filePath"
            throw "GraphQL file not found: $filePath"
        }
        $result[$key] = $filePath
    }
    
    return $result
}

function Test-PythonCommand {
    param([string]$Command)
    
    try {
        $null = Get-Command $Command -ErrorAction Stop
    }
    catch {
        return $false
    }
    
    # Get-Command alone isn't enough: on Windows, "python"/"python3" can resolve to the
    # Microsoft Store execution-alias stub, which runs but prints a reinstall nag instead
    # of a real version - so verify the output actually looks like a Python version.
    $versionOutput = & $Command --version 2>&1
    return ($versionOutput -match '^Python \d+\.\d+')
}

function Get-PythonExecutable {
    # Try to find Python in PATH (cross-platform), skipping non-functional stubs
    foreach ($candidate in @("python3", "python")) {
        if (Test-PythonCommand -Command $candidate) {
            return $candidate
        }
    }
    
    throw "Python executable not found in PATH. Please install Python and ensure it's in your PATH."
}

#endregion

#region Main Script

try {
    # Show welcome banner
    Show-WelcomeBanner
    
    # Step 1: Get Lab Configuration
    Write-StepHeader "STEP 1: Lab Configuration Setup"
    
    Write-Host "  Please provide your Lab environment details:" -ForegroundColor White
    Write-Host ""
    
    # Get Lab Domain
    $labDomain = Read-Host "  Lab Domain (e.g., mylab.varonis-preprod.com)"
    if ([string]::IsNullOrWhiteSpace($labDomain)) {
        Write-ErrorMessage "Lab domain is required!"
        exit 1
    }
    Write-SuccessMessage "Lab domain set: $labDomain"
    
    # Get API Key
    $apiKey = Read-Host "  API Key"
    if ([string]::IsNullOrWhiteSpace($apiKey)) {
        Write-ErrorMessage "API key is required!"
        exit 1
    }
    Write-SuccessMessage "API key configured"
    
    # Build endpoints
    $endpoint = "https://$labDomain/api/graphql"
    $accessTokenUrl = "https://$labDomain/api/authentication/api_keys/token"
    
    Write-Host ""
    Write-InfoMessage "Endpoint configured: $endpoint"
    Start-Sleep -Milliseconds 1000
    
    # Step 2: Select Query
    Write-StepHeader "STEP 2: Query Selection"
    
    Write-Host "  Available queries in the repository:" -ForegroundColor White
    Write-Host ""
    
    # List available .gql files (exclude Common\ - those are internal job status/pagination queries, not selectable export types)
    $gqlDir = Join-Path $PSScriptRoot "..\Gql"
    $gqlFiles = Get-ChildItem -Path $gqlDir -Filter "*.gql" -Recurse | Where-Object { $_.DirectoryName -notlike "*\Common" }
    
    $index = 1
    $fileMap = @{}
    foreach ($file in $gqlFiles) {
        $relativePath = $file.FullName.Replace($gqlDir, "").TrimStart("\")
        Write-Host "    [$index] " -ForegroundColor Yellow -NoNewline
        Write-Host $relativePath -ForegroundColor Cyan
        $fileMap[$index] = $file.FullName
        $index++
    }
    
    Write-Host ""
    $queryChoice = Read-Host "  Select query number"
    
    if (-not $fileMap.ContainsKey([int]$queryChoice)) {
        Write-ErrorMessage "Invalid query selection!"
        exit 1
    }
    
    $selectedQueryPath = $fileMap[[int]$queryChoice]
    $selectedQueryName = (Get-Item $selectedQueryPath).BaseName
    Write-SuccessMessage "Selected query: $selectedQueryName"
    Start-Sleep -Milliseconds 800
    
    # Step 3: Query Parameters
    Write-StepHeader "STEP 3: Query Parameters"
    
    Write-Host "  Configure query parameters:" -ForegroundColor White
    Write-Host ""
    
    # Determine query type (check for eventsExport in any form)
    $isEventsQuery = $selectedQueryName -like "*eventsExport*"
    
    # Get start date
    $startDateInput = Read-Host "  Start Date (YYYY-MM-DD or press Enter for 7 days ago)"
    if ([string]::IsNullOrWhiteSpace($startDateInput)) {
        $startDate = (Get-Date).AddDays(-7)
        Write-InfoMessage "Using default: $($startDate.ToString('yyyy-MM-dd'))"
    } else {
        try {
            $startDate = [DateTime]::Parse($startDateInput)
            Write-SuccessMessage "Start date set: $($startDate.ToString('yyyy-MM-dd'))"
        } catch {
            Write-ErrorMessage "Invalid date format!"
            exit 1
        }
    }
    
    # Get end date (optional)
    $endDateInput = Read-Host "  End Date (YYYY-MM-DD or press Enter for now)"
    $endDate = $null
    if (-not [string]::IsNullOrWhiteSpace($endDateInput)) {
        try {
            $endDate = [DateTime]::Parse($endDateInput)
            Write-SuccessMessage "End date set: $($endDate.ToString('yyyy-MM-dd'))"
        } catch {
            Write-ErrorMessage "Invalid date format!"
            exit 1
        }
    } else {
        Write-InfoMessage "Using current time as end date"
    }
    
    # Build query variables based on query type
    if ($isEventsQuery) {
        # Events query requires dataSourceId
        $dataSourceIdInput = Read-Host "  Data Source ID (press Enter for default: 5)"
        $dataSourceId = 5
        if (-not [string]::IsNullOrWhiteSpace($dataSourceIdInput)) {
            try {
                $dataSourceId = [int]$dataSourceIdInput
                Write-SuccessMessage "Data Source ID set: $dataSourceId"
            } catch {
                Write-ErrorMessage "Invalid Data Source ID!"
                exit 1
            }
        } else {
            Write-InfoMessage "Using default Data Source ID: 5"
        }
        
        $queryVariables = @{
            data_source_id = $dataSourceId
            gte = $startDate.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
        }
        
        if ($null -ne $endDate) {
            $queryVariables.lt = $endDate.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
        }
    } else {
        # Audit/Resources queries
        $queryVariables = @{
            gte = $startDate.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
        }
        
        if ($null -ne $endDate) {
            $queryVariables.lt = $endDate.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
        }
    }
    
    Start-Sleep -Milliseconds 1000
    
    # Step 4: Execute Export
    Write-StepHeader "STEP 4: Executing Export Process"
    
    # Get GraphQL files
    $gqlFiles = Get-GraphQLFiles -QueryFilePath $selectedQueryPath
    
    Write-InfoMessage "Loading GraphQL queries..."
    $query = Get-Content $gqlFiles.Query -Raw
    $exportJobQuery = Get-Content $gqlFiles.ExportJob -Raw
    $exportNextQuery = Get-Content $gqlFiles.ExportNext -Raw
    Write-SuccessMessage "GraphQL queries loaded"
    
    # Create output folder
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $baseFolder = "exports_demo_$timestamp"
    
    if (-not (Test-Path $baseFolder)) {
        New-Item -ItemType Directory -Path $baseFolder | Out-Null
        Write-SuccessMessage "Created output folder: $baseFolder"
    }
    
    Start-Sleep -Milliseconds 800
    
    # Initialize timing and metrics tracking
    $overallStartTime = Get-Date
    $totalDownloadSizeBytes = 0
    $totalDownloadTimeMs = 0
    $totalProcessingTimeMs = 0
    $totalExportedObjects = 0
    $batchMetrics = @()
    
    # Submit initial query
    $jobId = Submit-GraphQLQuery -Endpoint $endpoint -AccessTokenUrl $accessTokenUrl -ApiKey $apiKey -Query $query -Variables $queryVariables
    
    # Export loop
    $batchNumber = 1
    
    while ($true) {
        $batchHeader = "STEP 4.$batchNumber - Processing Data Batch #$batchNumber"
        Write-StepHeader $batchHeader
        
        # Start batch processing timer
        $batchStartTime = Get-Date
        
        # Wait for completion
        $jobStatus = Wait-ForJobCompletion -Endpoint $endpoint -AccessTokenUrl $accessTokenUrl -ApiKey $apiKey -ExportJobQuery $exportJobQuery -JobId $jobId
        Test-JobCompletionStatus -JobStatus $jobStatus
        
        # Calculate processing time
        $batchProcessingTime = (Get-Date) - $batchStartTime
        
        # Download results
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $baseFilename = "batch_$($batchNumber)_$timestamp"
        $baseFilePath = Join-Path $baseFolder "$baseFilename"
        $filenameAvro = "$baseFilePath.avro"
        
        # Start download timer
        $downloadStartTime = Get-Date
        Download-Results -DataUrl $jobStatus.dataUrl -AccessTokenUrl $accessTokenUrl -ApiKey $apiKey -AvroFilename $filenameAvro
        $downloadTime = (Get-Date) - $downloadStartTime
        
        # Get file size
        $batchFileSize = (Get-Item $filenameAvro).Length
        $batchFileSizeKB = [math]::Round($batchFileSize / 1KB, 2)
        $batchFileSizeMB = [math]::Round($batchFileSize / 1MB, 2)
        
        # Count records in the Avro file
        $batchRecordCount = Get-AvroRecordCount -AvroFilePath $filenameAvro
        $totalExportedObjects += $batchRecordCount
        
        # Update totals
        $totalDownloadSizeBytes += $batchFileSize
        $totalDownloadTimeMs += $downloadTime.TotalMilliseconds
        $totalProcessingTimeMs += $batchProcessingTime.TotalMilliseconds
        $elapsedSinceStart = (Get-Date) - $overallStartTime
        
        # Store batch metrics
        $batchMetrics += @{
            BatchNumber = $batchNumber
            ProcessingTimeSec = [math]::Round($batchProcessingTime.TotalSeconds, 2)
            DownloadTimeSec = [math]::Round($downloadTime.TotalSeconds, 2)
            FileSizeKB = $batchFileSizeKB
            FileSizeMB = $batchFileSizeMB
            RecordCount = $batchRecordCount
        }
        
        # Display batch timing summary
        Write-Host ""
        Write-Host "  ┌─────────────────────────────────────────────────────────────┐" -ForegroundColor DarkCyan
        Write-Host "  │  BATCH #$batchNumber METRICS                                         │" -ForegroundColor DarkCyan
        Write-Host "  ├─────────────────────────────────────────────────────────────┤" -ForegroundColor DarkCyan
        Write-Host "  │  Processing Time:   " -ForegroundColor DarkCyan -NoNewline
        Write-Host ("{0,8:N2}" -f $batchProcessingTime.TotalSeconds) -ForegroundColor Yellow -NoNewline
        Write-Host " seconds                       │" -ForegroundColor DarkCyan
        Write-Host "  │  Download Time:     " -ForegroundColor DarkCyan -NoNewline
        Write-Host ("{0,8:N2}" -f $downloadTime.TotalSeconds) -ForegroundColor Yellow -NoNewline
        Write-Host " seconds                       │" -ForegroundColor DarkCyan
        Write-Host "  │  Batch Size:        " -ForegroundColor DarkCyan -NoNewline
        if ($batchFileSizeMB -ge 1) {
            Write-Host ("{0,8:N2}" -f $batchFileSizeMB) -ForegroundColor Cyan -NoNewline
            Write-Host " MB                            │" -ForegroundColor DarkCyan
        } else {
            Write-Host ("{0,8:N2}" -f $batchFileSizeKB) -ForegroundColor Cyan -NoNewline
            Write-Host " KB                            │" -ForegroundColor DarkCyan
        }
        Write-Host "  │  Objects Exported:  " -ForegroundColor DarkCyan -NoNewline
        Write-Host ("{0,8:N0}" -f $batchRecordCount) -ForegroundColor Cyan -NoNewline
        Write-Host " records                       │" -ForegroundColor DarkCyan
        Write-Host "  ├─────────────────────────────────────────────────────────────┤" -ForegroundColor DarkCyan
        Write-Host "  │  CUMULATIVE TOTALS                                          │" -ForegroundColor DarkCyan
        Write-Host "  │  Total Elapsed:     " -ForegroundColor DarkCyan -NoNewline
        Write-Host ("{0,8:N2}" -f $elapsedSinceStart.TotalSeconds) -ForegroundColor Green -NoNewline
        Write-Host " seconds                       │" -ForegroundColor DarkCyan
        $totalSizeMB = [math]::Round($totalDownloadSizeBytes / 1MB, 2)
        $totalSizeKB = [math]::Round($totalDownloadSizeBytes / 1KB, 2)
        Write-Host "  │  Total Download:    " -ForegroundColor DarkCyan -NoNewline
        if ($totalSizeMB -ge 1) {
            Write-Host ("{0,8:N2}" -f $totalSizeMB) -ForegroundColor Green -NoNewline
            Write-Host " MB                            │" -ForegroundColor DarkCyan
        } else {
            Write-Host ("{0,8:N2}" -f $totalSizeKB) -ForegroundColor Green -NoNewline
            Write-Host " KB                            │" -ForegroundColor DarkCyan
        }
        Write-Host "  │  Total Objects:     " -ForegroundColor DarkCyan -NoNewline
        Write-Host ("{0,8:N0}" -f $totalExportedObjects) -ForegroundColor Green -NoNewline
        Write-Host " records                       │" -ForegroundColor DarkCyan
        Write-Host "  └─────────────────────────────────────────────────────────────┘" -ForegroundColor DarkCyan
        
        # Check if more data exists
        Write-Host ""
        Write-Host "  [?] Checking for additional data..." -ForegroundColor Cyan
        Start-Sleep -Milliseconds 1000
        
        if ($jobStatus.hasMoreData -eq $false) {
            $exportEndTime = Get-Date
            $totalExportTime = $exportEndTime - $overallStartTime
            
            Write-Host ""
            Write-StepHeader "EXPORT COMPLETED SUCCESSFULLY" -Delay 0
            Write-Host ""
            Write-SuccessMessage "All data has been exported!"
            Write-Host ""
            Write-Host "  ╔═════════════════════════════════════════════════════════════╗" -ForegroundColor Green
            Write-Host "  ║  EXPORT SUMMARY                                             ║" -ForegroundColor Green
            Write-Host "  ╠═════════════════════════════════════════════════════════════╣" -ForegroundColor Green
            Write-Host "  ║  Total Batches:         " -ForegroundColor Green -NoNewline
            Write-Host ("{0,6}" -f $batchNumber) -ForegroundColor Cyan -NoNewline
            Write-Host "                              ║" -ForegroundColor Green
            Write-Host "  ║  Total Export Time:     " -ForegroundColor Green -NoNewline
            Write-Host ("{0,6:N2}" -f $totalExportTime.TotalSeconds) -ForegroundColor Cyan -NoNewline
            Write-Host " seconds                       ║" -ForegroundColor Green
            Write-Host "  ║  Total Processing Time: " -ForegroundColor Green -NoNewline
            Write-Host ("{0,6:N2}" -f ($totalProcessingTimeMs / 1000)) -ForegroundColor Cyan -NoNewline
            Write-Host " seconds                       ║" -ForegroundColor Green
            Write-Host "  ║  Total Download Time:   " -ForegroundColor Green -NoNewline
            Write-Host ("{0,6:N2}" -f ($totalDownloadTimeMs / 1000)) -ForegroundColor Cyan -NoNewline
            Write-Host " seconds                       ║" -ForegroundColor Green
            $finalSizeMB = [math]::Round($totalDownloadSizeBytes / 1MB, 2)
            $finalSizeKB = [math]::Round($totalDownloadSizeBytes / 1KB, 2)
            Write-Host "  ║  Total Download Size:   " -ForegroundColor Green -NoNewline
            if ($finalSizeMB -ge 1) {
                Write-Host ("{0,6:N2}" -f $finalSizeMB) -ForegroundColor Cyan -NoNewline
                Write-Host " MB                            ║" -ForegroundColor Green
            } else {
                Write-Host ("{0,6:N2}" -f $finalSizeKB) -ForegroundColor Cyan -NoNewline
                Write-Host " KB                            ║" -ForegroundColor Green
            }
            Write-Host "  ║  Total Objects:         " -ForegroundColor Green -NoNewline
            Write-Host ("{0,6:N0}" -f $totalExportedObjects) -ForegroundColor Cyan -NoNewline
            Write-Host " records                       ║" -ForegroundColor Green
            Write-Host "  ║  Output Folder:         " -ForegroundColor Green -NoNewline
            $folderDisplay = $baseFolder
            if ($folderDisplay.Length -gt 30) { $folderDisplay = $folderDisplay.Substring(0, 27) + "..." }
            Write-Host ("{0,-30}" -f $folderDisplay) -ForegroundColor Cyan -NoNewline
            Write-Host " ║" -ForegroundColor Green
            Write-Host "  ╚═════════════════════════════════════════════════════════════╝" -ForegroundColor Green
            Write-Host ""
            Write-Host "  >> hasMoreData = " -ForegroundColor White -NoNewline
            Write-Host "FALSE" -ForegroundColor Green -NoNewline
            Write-Host " - Export loop terminated" -ForegroundColor White
            Write-Host ""
            break
        }
        
        Write-WarningMessage "More data available (hasMoreData = TRUE)"
        Write-InfoMessage "Continuing to next batch..."
        Start-Sleep -Milliseconds 1500
        
        # Submit exportNext
        $nextResult = Submit-ExportNext -Endpoint $endpoint -AccessTokenUrl $accessTokenUrl -ApiKey $apiKey -ExportNextQuery $exportNextQuery -Cursor $jobStatus.nextExportCursor
        $jobId = $nextResult.jobId
        
        $batchNumber++
    }
    
    # Step 5: Convert Avro to JSON
    Write-Host ""
    Write-StepHeader "STEP 5: Converting Avro Files to JSON"
    
    Write-InfoMessage "Preparing to convert Avro files to JSON format..."
    
    # Check if Python is available
    $pythonCmd = $null
    try {
        $pythonCmd = Get-PythonExecutable
        $pythonVersion = & $pythonCmd --version 2>&1
        Write-SuccessMessage "Python detected: $pythonVersion"
    }
    catch {
        Write-ErrorMessage "Python is not installed or not in PATH"
        Write-WarningMessage "Skipping Avro to JSON conversion"
        Write-Host ""
        Write-Host "To enable conversion, install Python and the fastavro library:" -ForegroundColor Yellow
        Write-Host "  pip install fastavro" -ForegroundColor Cyan
        Write-Host ""
    }
    
    # Check if fastavro is installed (only if Python was found)
    if ($pythonCmd) {
        $fastavroCheck = & $pythonCmd -c "import fastavro; print('OK')" 2>&1
        if ($fastavroCheck -like "*OK*") {
        Write-SuccessMessage "fastavro library is installed"
        
        # Run the conversion script
        $converterScript = Join-Path $PSScriptRoot "ConvertAvroToJson.py"
        
        if (-not (Test-Path $converterScript)) {
            Write-ErrorMessage "Converter script not found: $converterScript"
        }
        else {
            Write-Host ""
            Write-InfoMessage "Starting conversion process..."
            Start-Sleep -Milliseconds 800
            
            # Start JSON conversion timer
            $jsonConversionStartTime = Get-Date
            
            # Execute Python converter
            & $pythonCmd $converterScript $baseFolder
            
            # Calculate JSON conversion time
            $jsonConversionTime = (Get-Date) - $jsonConversionStartTime
            
            # Get total JSON file sizes
            $jsonFiles = Get-ChildItem -Path $baseFolder -Filter "*.json" -ErrorAction SilentlyContinue
            $totalJsonSizeBytes = 0
            $jsonFileCount = 0
            if ($jsonFiles) {
                $jsonFileCount = $jsonFiles.Count
                $totalJsonSizeBytes = ($jsonFiles | Measure-Object -Property Length -Sum).Sum
            }
            $totalJsonSizeMB = [math]::Round($totalJsonSizeBytes / 1MB, 2)
            $totalJsonSizeKB = [math]::Round($totalJsonSizeBytes / 1KB, 2)
            
            Write-Host ""
            Write-SuccessMessage "Avro to JSON conversion completed!"
            Write-Host ""
            Write-Host "  ┌─────────────────────────────────────────────────────────────┐" -ForegroundColor Magenta
            Write-Host "  │  JSON CONVERSION METRICS                                    │" -ForegroundColor Magenta
            Write-Host "  ├─────────────────────────────────────────────────────────────┤" -ForegroundColor Magenta
            Write-Host "  │  Files Converted:    " -ForegroundColor Magenta -NoNewline
            Write-Host ("{0,8}" -f $jsonFileCount) -ForegroundColor Yellow -NoNewline
            Write-Host " files                         │" -ForegroundColor Magenta
            Write-Host "  │  Conversion Time:    " -ForegroundColor Magenta -NoNewline
            Write-Host ("{0,8:N2}" -f $jsonConversionTime.TotalSeconds) -ForegroundColor Yellow -NoNewline
            Write-Host " seconds                       │" -ForegroundColor Magenta
            Write-Host "  │  Total JSON Size:    " -ForegroundColor Magenta -NoNewline
            if ($totalJsonSizeMB -ge 1) {
                Write-Host ("{0,8:N2}" -f $totalJsonSizeMB) -ForegroundColor Cyan -NoNewline
                Write-Host " MB                            │" -ForegroundColor Magenta
            } else {
                Write-Host ("{0,8:N2}" -f $totalJsonSizeKB) -ForegroundColor Cyan -NoNewline
                Write-Host " KB                            │" -ForegroundColor Magenta
            }
            Write-Host "  └─────────────────────────────────────────────────────────────┘" -ForegroundColor Magenta
        }
    }
    else {
        Write-WarningMessage "fastavro library is not installed"
        Write-Host ""
        Write-Host "To install fastavro, run:" -ForegroundColor Yellow
        Write-Host "  pip install fastavro" -ForegroundColor Cyan
        Write-Host ""
        Write-InfoMessage "Skipping conversion step..."
    }
    }
    else {
        Write-InfoMessage "Skipping conversion step due to missing Python..."
    }
    
    # Final summary
    $overallEndTime = Get-Date
    $totalDemoTime = $overallEndTime - $overallStartTime
    
    Write-Host ""
    Write-Host "====================================================================" -ForegroundColor Green
    Write-Host "                 DEMO COMPLETED SUCCESSFULLY                        " -ForegroundColor Green
    Write-Host "====================================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "  ╔═════════════════════════════════════════════════════════════════╗" -ForegroundColor White
    Write-Host "  ║                    FINAL SUMMARY                                ║" -ForegroundColor White
    Write-Host "  ╠═════════════════════════════════════════════════════════════════╣" -ForegroundColor White
    Write-Host "  ║  EXPORT METRICS                                                 ║" -ForegroundColor Yellow
    Write-Host "  ║    Total Batches:           " -ForegroundColor White -NoNewline
    Write-Host ("{0,6}" -f $batchNumber) -ForegroundColor Cyan -NoNewline
    Write-Host "                            ║" -ForegroundColor White
    Write-Host "  ║    Total Processing Time:   " -ForegroundColor White -NoNewline
    Write-Host ("{0,6:N2}" -f ($totalProcessingTimeMs / 1000)) -ForegroundColor Cyan -NoNewline
    Write-Host " seconds                     ║" -ForegroundColor White
    Write-Host "  ║    Total Download Time:     " -ForegroundColor White -NoNewline
    Write-Host ("{0,6:N2}" -f ($totalDownloadTimeMs / 1000)) -ForegroundColor Cyan -NoNewline
    Write-Host " seconds                     ║" -ForegroundColor White
    $summaryAvroSizeMB = [math]::Round($totalDownloadSizeBytes / 1MB, 2)
    $summaryAvroSizeKB = [math]::Round($totalDownloadSizeBytes / 1KB, 2)
    Write-Host "  ║    Total Avro Size:         " -ForegroundColor White -NoNewline
    if ($summaryAvroSizeMB -ge 1) {
        Write-Host ("{0,6:N2}" -f $summaryAvroSizeMB) -ForegroundColor Cyan -NoNewline
        Write-Host " MB                          ║" -ForegroundColor White
    } else {
        Write-Host ("{0,6:N2}" -f $summaryAvroSizeKB) -ForegroundColor Cyan -NoNewline
        Write-Host " KB                          ║" -ForegroundColor White
    }
    Write-Host "  ║    Total Objects Exported:  " -ForegroundColor White -NoNewline
    Write-Host ("{0,6:N0}" -f $totalExportedObjects) -ForegroundColor Cyan -NoNewline
    Write-Host " records                     ║" -ForegroundColor White
    Write-Host "  ╠═════════════════════════════════════════════════════════════════╣" -ForegroundColor White
    Write-Host "  ║  OVERALL                                                        ║" -ForegroundColor Yellow
    Write-Host "  ║    Total Demo Time:         " -ForegroundColor White -NoNewline
    Write-Host ("{0,6:N2}" -f $totalDemoTime.TotalSeconds) -ForegroundColor Green -NoNewline
    Write-Host " seconds                     ║" -ForegroundColor White
    Write-Host "  ║    Output Folder:           " -ForegroundColor White -NoNewline
    $folderDisplayFinal = $baseFolder
    if ($folderDisplayFinal.Length -gt 28) { $folderDisplayFinal = $folderDisplayFinal.Substring(0, 25) + "..." }
    Write-Host ("{0,-28}" -f $folderDisplayFinal) -ForegroundColor Cyan -NoNewline
    Write-Host " ║" -ForegroundColor White
    Write-Host "  ╚═════════════════════════════════════════════════════════════════╝" -ForegroundColor White
    Write-Host ""
    
}
catch {
    Write-Host ""
    Write-Host "====================================================================" -ForegroundColor Red
    Write-Host "                      ERROR OCCURRED                                " -ForegroundColor Red
    Write-Host "====================================================================" -ForegroundColor Red
    Write-Host ""
    Write-ErrorMessage $_.Exception.Message
    Write-Host ""
    exit 1
}

#endregion
