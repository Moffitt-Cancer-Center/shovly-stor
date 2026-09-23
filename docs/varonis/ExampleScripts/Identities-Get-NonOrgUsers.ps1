# Varonis' sample code(s) are provided on an "as is" and "as available" basis and without any warranty of any kind.  
# Any use of Varonis' sample code(s) is optional at client's sole discretion, responsibility and risk.
# Varonis does not make any commitment with respect to Varonis' sample code(s), their specific functions or their availability, reliability, or ability to meet client's needs.
# Client acknowledges that Varonis may, in its sole discretion, modify, discontinue or update the Varonis' sample code(s) from time to time, without notice and for any reason.

<#
.SYNOPSIS
Queries Varonis API for non-organization users.

.DESCRIPTION
This script searches for user accounts that are not part of the organization,
such as external users, service accounts, or orphaned accounts.

.EXAMPLE
.\Identities-Get-NonOrgUsers.ps1
#>

param (
    # No parameters needed for this users query
)

# Import the helper module
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$helperModule = Join-Path $scriptDir "VaronisApiHelpers.psm1"
Import-Module $helperModule -Force

# Constants
$GRAPHQL_QUERY_FILENAME = "Identities - Non-Org Users.gql"
$OUTPUT_FILENAME = "Identities-NonOrgUsers.json"
$QUERY_DESCRIPTION = "Non-Organization Users"

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
Write-Host "Searching for non-organization user accounts"
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
