# Varonis' sample code(s) are provided on an "as is" and "as available" basis and without any warranty of any kind.  
# Any use of Varonis' sample code(s) is optional at client's sole discretion, responsibility and risk.
# Varonis does not make any commitment with respect to Varonis' sample code(s), their specific functions or their availability, reliability, or ability to meet client's needs.
# Client acknowledges that Varonis may, in its sole discretion, modify, discontinue or update the Varonis' sample code(s) from time to time, without notice and for any reason.

<#
.SYNOPSIS
Queries Varonis API for users with passwords that never expire.

.DESCRIPTION
This script searches for user accounts that have passwords configured to never expire,
which may represent security risks requiring review.

.EXAMPLE
.\Identities-Get-UsersWithPasswordsNeverExpire.ps1
#>

param (
    # No parameters needed for this identities query
)

# Import the helper module
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$helperModule = Join-Path $scriptDir "VaronisApiHelpers.psm1"
Import-Module $helperModule -Force

# Constants
$GRAPHQL_QUERY_FILENAME = "Identities - Users with Passwords that Never Expire.gql"
$OUTPUT_FILENAME = "Identities-UsersWithPasswordsNeverExpire.json"
$QUERY_DESCRIPTION = "Users with Passwords that Never Expire"

# Read configuration
$ConfigFile = Get-ConfigFile
if (-not (Test-Path $ConfigFile)) {
    throw "Config file not found: $ConfigFile"
}
$config = Get-Content $ConfigFile | ConvertFrom-Json

# Read GraphQL query from file
$queryFile = Get-GraphQLQueryFile -QueryFileName $GRAPHQL_QUERY_FILENAME
$baseQuery = Get-Content $queryFile -Raw

# Set destination folder to be next to the script, with timestamp
$timestamp = Get-Date -Format "yyyyMMdd"
$destinationFolder = Join-Path $scriptDir "Results\$timestamp"
if (-not (Test-Path $destinationFolder)) {
    New-Item -ItemType Directory -Path $destinationFolder | Out-Null
}

# Main execution
Write-Host "Starting query '$QUERY_DESCRIPTION'"
Write-Host "Searching for users with passwords that never expire"
Write-Host "Output file: $destinationFolder\$OUTPUT_FILENAME"
Write-Host "Using GraphQL file: $queryFile"

try {
    # Execute the query using the shared helper function
    $results = Invoke-IdentitiesQuery -Query $baseQuery -Config $config -QueryDescription $QUERY_DESCRIPTION

    # Save the results using the shared helper function
    Save-Results -Results $results -DestinationFolder $destinationFolder -FileName $OUTPUT_FILENAME -ResultType "identities"

    Write-Host "Script completed successfully!"
} catch {
    Write-Host "An error occurred: $_"
    exit 1
}
