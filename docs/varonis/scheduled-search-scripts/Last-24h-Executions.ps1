# Varonis' sample code(s) are provided on an "as is" and "as available" basis and without any warranty of any kind.  
# Any use of Varonis' sample code(s) is optional at client's sole discretion, responsibility and risk.
# Varonis does not make any commitment with respect to Varonis' sample code(s), their specific functions or their availability, reliability, or ability to meet client's needs.
# Client acknowledges that Varonis may, in its sole discretion, modify, discontinue or update the Varonis' sample code(s) from time to time, without notice and for any reason.

[CmdletBinding()]
param()

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
        Write-Verbose "Successfully obtained access token."
        return $response.access_token
    } catch {
        Write-Error "Failed to obtain access token. $_"
        exit 1
    }
}

function Get-ScheduledSearches {
    param (
        [object]$Config
    )

    $token = Get-AccessToken($Config)
    $url = "https://$($Config.domain)/api/graphql"
    $headers = @{
        "Authorization" = "Bearer $token" # Authorization header with the access token
        "Content-Type" = "application/json" # Content-Type header
    }

    # GraphQL query to get scheduled searches and their last execution times
    $query = @"
    query subscriptions {
        scheduledSearches {
            id
            name
            description
            enabled
            schedule {
                summary
            }
            lastExecution {
                time
                status
            }
            nextExecutionTime
            linkedSavedSearches {
                id
                name
            }
        }
    }
"@
    $body = @{ query = $query } | ConvertTo-Json

    try {
        Write-Verbose "Executing GraphQL query:`n$query"
        # Invoke the POST request to obtain the scheduled searches
        $response = Invoke-RestMethod -Uri $url -Method Post -Headers $headers -Body $body
        Write-Verbose "Successfully obtained scheduled searches ($($response.data.scheduledSearches.Count)): $($response.data.scheduledSearches | ConvertTo-Json -Depth 10)"
        # Return the scheduled searches
        return $response.data.scheduledSearches
    } catch {
        Write-Error "Failed to query scheduled searches. $_"
        exit 1
    }
}

function Get-ScheduledSearchExecutions {
    param (
        [array]$ids, # Array of scheduled search IDs
        [object]$Config
    )

    $token = Get-AccessToken($Config)
    $url = "https://$($Config.domain)/api/graphql"
    $headers = @{
        "Authorization" = "Bearer $token" # Authorization header with the access token
        "Content-Type" = "application/json" # Content-Type header
    }
    $queryTime = (Get-Date).AddHours(-24).ToString("yyyy-MM-ddTHH:mm:ssZ") # Query time set to 24 hours ago
    $idsString = $ids -join ', ' # Join the array of IDs into a string

    # GraphQL query to get scheduled search executions
    $query = @"
    query urls {
        scheduledSearchExecutions(where: { time: { gte: `"$queryTime`" }}, scheduledSearchIds: [$idsString] ) {
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
    $body = @{ query = $query } | ConvertTo-Json

    try {
        Write-Verbose "Executing GraphQL query:`n$query"
        # Invoke the POST request to obtain the search executions
        $response = Invoke-RestMethod -Uri $url -Method Post -Headers $headers -Body $body
        Write-Verbose "Successfully obtained scheduled search executions ($($response.data.scheduledSearchExecutions.Count)): $($response.data.scheduledSearchExecutions | ConvertTo-Json -Depth 10)"

        # Return the results
        return $response.data.scheduledSearchExecutions.results
    } catch {
        Write-Error "Failed to query scheduled search executions: $_"
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

    # Get all scheduled searches
    $scheduledSearches = Get-ScheduledSearches($config)

    # Initialize an empty array to store the IDs of searches executed in the last 24 hours
    $ids = @()

    # Find scheduled searches that were executed in the last 24 hours
    foreach ($search in $scheduledSearches) {
        if ($search.lastExecution -and $search.lastExecution.time) {
            $lastExecutionTime = [datetime]::ParseExact($search.lastExecution.time, "yyyy-MM-ddTHH:mm:ss.fffZ", $null)
            if ($lastExecutionTime -ge (Get-Date).AddHours(-24)) {
                $ids += $search.id
            }
        }
    }
    Write-Verbose "Scheduled searches IDs executed in the last 24 hours ($($ids.Count)): $ids"

    # If there are any IDs, get their scheduled search executions and download the files
    if ($ids.Count -gt 0) {
        $scheduledSearchExecutions = Get-ScheduledSearchExecutions -ids $ids -Config $config
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
    } else {
        Write-Warning "No scheduled searches executed in the last 24 hours."
        Write-Host "FAILED"
    }
} catch {
    Write-Error "An error occurred in the main script. $_"
    Write-Host "FAILED"
    exit 1
}
