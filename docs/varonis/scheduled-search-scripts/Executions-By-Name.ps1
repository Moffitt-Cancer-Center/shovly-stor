# Varonis' sample code(s) are provided on an "as is" and "as available" basis and without any warranty of any kind.
# Any use of Varonis' sample code(s) is optional at client's sole discretion, responsibility and risk.
# Varonis does not make any commitment with respect to Varonis' sample code(s), their specific functions or their availability, reliability, or ability to meet client's needs.
# Client acknowledges that Varonis may, in its sole discretion, modify, discontinue or update the Varonis' sample code(s) from time to time, without notice and for any reason.

[CmdletBinding()]
param (
    [string]$name,
    [string]$fromDate,
    [string]$toDate
)

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
        Write-Error "Failed to query scheduled searches: $_"
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
    $idsString = $ids -join ', ' # Join the array of IDs into a string

    # GraphQL query to get scheduled search executions
    $query = @"
    query urls {
        scheduledSearchExecutions(where: { time: { gte: `"$fromDate`",lt: `"$toDate`" }}, scheduledSearchIds: [$idsString] ) {
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

    # Logging the query for debugging purposes
    $prettyJson = $body | ConvertFrom-Json | ConvertTo-Json -Depth 10 -Compress:$false

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

# Input validation
if (-not $name) { throw "Name (name) parameter is required." }
if (-not $fromDate) { throw "From date (fromDate) parameter is required in ISO format." }
if (-not $toDate) { throw "To date (toDate) parameter is required in ISO format." }

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

    # Get the scheduled search
    $scheduledSearches = Get-ScheduledSearches($Config)

    # Find scheduled search with $name
    $requested_scheduledSearch = $scheduledSearches | Where-Object { $_.name -eq $name }    # Return the scheduled searches with the requested $name
    if ([string]::IsNullOrEmpty($requested_scheduledSearch)) {
        Write-Warning "Scheduled search with name '$name' not found."
        Write-Host "FAILED"
        exit 1
    }

    # Get the scheduled search executions
    $scheduledSearchExecutions = Get-ScheduledSearchExecutions -ids $requested_scheduledSearch.id -Config $config

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
