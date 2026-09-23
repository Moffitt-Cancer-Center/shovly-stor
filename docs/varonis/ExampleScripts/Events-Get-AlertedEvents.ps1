# Varonis' sample code(s) are provided on an "as is" and "as available" basis and without any warranty of any kind.  
# Any use of Varonis' sample code(s) is optional at client's sole discretion, responsibility and risk.
# Varonis does not make any commitment with respect to Varonis' sample code(s), their specific functions or their availability, reliability, or ability to meet client's needs.
# Client acknowledges that Varonis may, in its sole discretion, modify, discontinue or update the Varonis' sample code(s) from time to time, without notice and for any reason.

<#
.SYNOPSIS
Queries Varonis API for alerted events.

.DESCRIPTION
This script searches for events that have triggered alerts within a specified date range.
Optionally filters by specific data source IDs.

.PARAMETER daysAgo
Number of days ago to start the search from (required)

.PARAMETER dataSourceIds
Comma-separated list of data source IDs to filter by (optional)

.EXAMPLE
.\Events-Get-AlertedEvents.ps1 -daysAgo 7
.\Events-Get-AlertedEvents.ps1 -daysAgo 14 -dataSourceIds "1,5,10"
#>

param (
    [Parameter(Mandatory=$true)]
    [int]$daysAgo,
    
    [Parameter(Mandatory=$false)]
    [string]$dataSourceIds = ""
)

# Import the helper module
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$helperModule = Join-Path $scriptDir "VaronisApiHelpers.psm1"
Import-Module $helperModule -Force

# Constants
$GRAPHQL_QUERY_FILENAME = "Events - Alerted Events.gql"
$OUTPUT_FILENAME = "Events-AlertedEvents.json"
$QUERY_DESCRIPTION = "Alerted Events"

# Read configuration
$ConfigFile = Get-ConfigFile
if (-not (Test-Path $ConfigFile)) {
    throw "Config file not found: $ConfigFile"
}
$config = Get-Content $ConfigFile | ConvertFrom-Json

# Read GraphQL query from file
$queryFile = Get-GraphQLQueryFile -QueryFileName $GRAPHQL_QUERY_FILENAME
$baseQuery = Get-Content $queryFile -Raw

# Calculate dates based on daysAgo parameter
$toDate = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
$fromDate = (Get-Date).AddDays(-$daysAgo).ToString("yyyy-MM-ddTHH:mm:ssZ")

# Input validation
if ($daysAgo -lt 1) { throw "Days ago must be a positive number." }

# Convert dataSourceIds string to integer array
$dataSourceIdsArray = if ([string]::IsNullOrWhiteSpace($dataSourceIds)) { @() } else { $dataSourceIds -split ',' | ForEach-Object { [int]$_ } }

# Set destination folder to be next to the script, with timestamp
$timestamp = Get-Date -Format "yyyyMMdd"
$destinationFolder = Join-Path $scriptDir "Results\$timestamp"
if (-not (Test-Path $destinationFolder)) {
    New-Item -ItemType Directory -Path $destinationFolder | Out-Null
}

# Main execution
Write-Host "Starting query '$QUERY_DESCRIPTION'"
Write-Host "Searching for events from $daysAgo days ago to now"
Write-Host "Date range: $fromDate to $toDate"
if ($dataSourceIdsArray.Count -gt 0) {
    Write-Host "Filtering by data source IDs: $($dataSourceIdsArray -join ', ')"
} else {
    Write-Host "No data source filter applied (will search all data sources)"
}
Write-Host "Output file: $destinationFolder\$OUTPUT_FILENAME"
Write-Host "Using GraphQL file: $queryFile"

try {
    # Execute the query using the shared helper function
    $results = Invoke-EventsQuery -Query $baseQuery -Config $config -FromDate $fromDate -ToDate $toDate -DataSourceIds $dataSourceIdsArray -QueryDescription $QUERY_DESCRIPTION

    # Save the results using the shared helper function
    Save-Results -Results $results -DestinationFolder $destinationFolder -FileName $OUTPUT_FILENAME -ResultType "events"

    Write-Host "Script completed successfully!"
} catch {
    Write-Host "An error occurred: $_"
    exit 1
}
