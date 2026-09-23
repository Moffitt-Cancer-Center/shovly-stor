# Varonis' sample code(s) are provided on an "as is" and "as available" basis and without any warranty of any kind.
# Any use of Varonis' sample code(s) is optional at client's sole discretion, responsibility and risk.
# Varonis does not make any commitment with respect to Varonis' sample code(s), their specific functions or their availability, reliability, or ability to meet client's needs.
# Client acknowledges that Varonis may, in its sole discretion, modify, discontinue or update the Varonis' sample code(s) from time to time, without notice and for any reason.

[CmdletBinding()]
param (
    [int]$scheduledSearchId # ID of the scheduled search
)

# Set the security protocol to TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

if (-not $scheduledSearchId) {
    Write-Error "'scheduledSearchId' parameter is required."
    exit 1
}

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
        Write-Verbose "Successfully obtained access token."
        return $response.access_token
    } catch {
        Write-Error "Failed to obtain access token. $_"
        exit 1
    }
}

function Get-LastMonthWindow {
    # Previous calendar month in UTC (inclusive start, exclusive end)
    $now = Get-Date
    $prevMonth = $now.AddMonths(-1)
    $startDate = Get-Date -Year $prevMonth.Year -Month $prevMonth.Month -Day 1 -Hour 0 -Minute 0 -Second 0 -Millisecond 0
    $endDate   = Get-Date -Year $now.Year       -Month $now.Month       -Day 1 -Hour 0 -Minute 0 -Second 0 -Millisecond 0

    return @{
        startIso = $startDate.ToString("yyyy-MM-ddTHH:mm:ssZ")
        endIso   = $endDate.ToString("yyyy-MM-ddTHH:mm:ssZ")
    }
}

function Get-ScheduledSearchExecutions {
    param (
        [object]$ScheduledSearchId,
        [object]$Start,
        [object]$End,
        [object]$Config
    )

    $token = Get-AccessToken($Config)
    $url = "https://$($Config.domain)/api/graphql"
    $headers = @{
        "Authorization" = "Bearer $token" # Authorization header with the access token
        "Content-Type" = "application/json" # Content-Type header
    }

    # GraphQL query to get scheduled search executions from the last month for the specified Scheduled Search id
    $query = @"
    query urls {
        scheduledSearchExecutions(where: { time: { gte: `"$Start`", lt: `"$End`" }}, scheduledSearchIds: [$ScheduledSearchId] ) {
            id
            scheduledSearch {
              id
              name
            }
            results {
                id
                status
                containsData
                dataUrl
            }
        }
    }
"@
    $body = @{
        query = $query
    } | ConvertTo-Json # Convert the query to JSON format

    try {
        Write-Verbose "Executing GraphQL query:`n$query"
        # Invoke the POST request to obtain the search executions
        $response = Invoke-RestMethod -Uri $url -Method Post -Headers $headers -Body $body
        $resultsCount = $response.data.scheduledSearchExecutions.results.Count
        Write-Verbose "Successfully obtained scheduled searches executions ($($response.data.scheduledSearchExecutions.Count)): $($response.data.scheduledSearchExecutions | ConvertTo-Json -Depth 10)"
        # Return the results
        return $response.data.scheduledSearchExecutions.results
    } catch {
        Write-Error "Failed to query scheduled search executions. $_"
        exit 1
    }
}

function Download-Files {
    param (
        [array]$dataUrls, # Array of data URLs to download
        [string]$destinationFolder, # Destination folder to save the files
        [object]$Config
    )

    # Ensure the download directory exists
    if (-not (Test-Path -Path $destinationFolder)) {
        New-Item -ItemType Directory -Path $destinationFolder
    }

    foreach ($dataUrl in $dataUrls) {
        if ($dataUrl -match 'filename=([^&]+)') {
            $fileName = [System.Web.HttpUtility]::UrlDecode($matches[1]) # Decode the URL to get the file name
            $fileName = $fileName -replace '[<>:"/\\|?*]', '_' # Replace invalid characters in the file name
            $outputPath = Join-Path -Path $destinationFolder -ChildPath $fileName # Create the output path

            try {
                $token = Get-AccessToken($Config)
                $headers = @{
                    "Authorization" = "Bearer $token" # Authorization header with the access token
                }
                Invoke-WebRequest -Uri $dataUrl -Headers $headers -OutFile $outputPath # Download the file
                Write-Verbose "Successfully downloaded file: $destinationFolder\$fileName"
            } catch {
                Write-Error "Failed to download file from $dataUrl : $_" # Handle download failure
            }
        } else {
            Write-Error "Invalid data URL format: $dataUrl"
        }
    }
}

# Main Script
try {
    # Read configuration
    $ConfigFile = "config.json"
    if (-not (Test-Path $ConfigFile)) {
        throw "Config file not found: $ConfigFile"
    }
    $config = Get-Content $ConfigFile | ConvertFrom-Json

    # Set the destination folder next to the script, named with today's date
    $timestamp = Get-Date -Format "yyyyMMdd"
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $destinationFolder = Join-Path $scriptDir "Results\$timestamp"
    if (-not (Test-Path $destinationFolder)) {
        New-Item -ItemType Directory -Path $destinationFolder | Out-Null
    }

    # Get the scheduled search executions for the last month
    $window = Get-LastMonthWindow
    $scheduledSearchExecutions = Get-ScheduledSearchExecutions -Start $window.startIso -End $window.endIso -ScheduledSearchId $scheduledSearchId -Config $config

    # Extract the data URLs for executions that successfully ran and contain data
    $dataUrls = $scheduledSearchExecutions |
        Where-Object { $_.containsData -eq $true -and $_.status -eq 'SUCCESS' } |
        ForEach-Object { $_.dataUrl }
    Write-Verbose "Data URLs ($($dataUrls.Count)):"
    $dataUrls | ForEach-Object { Write-Verbose "    $_"}  # print each url in a newline

    if ($dataUrls.Count -eq 0) {
        Write-Warning "No files found to download."
        Write-Host "FAILED"
        exit 1
    }
    Write-Verbose "Downloading files..."
    Download-Files -dataUrls $dataUrls -destinationFolder $destinationFolder -Config $config
    Write-Host "SUCCESS"
} catch {
    Write-Error "An error occurred in the main script. $_"
    Write-Host "FAILED"
}
