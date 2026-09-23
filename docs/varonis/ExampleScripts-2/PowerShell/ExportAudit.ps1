# Varonis’ sample code(s) are provided on an “as is” and “as available” basis and without any warranty of any kind.  
# Any use of Varonis’ sample code(s) is optional at client’s sole discretion, responsibility and risk.
# Varonis does not make any commitment with respect to Varonis’ sample code(s), their specific functions or their availability, reliability, or ability to meet client’s needs.
# Client acknowledges that Varonis may, in its sole discretion, modify, discontinue or update the Varonis’ sample code(s) from time to time, without notice and for any reason.

param(
    [Parameter(Mandatory=$true)]
    [DateTime]$startDate,

    [Parameter(Mandatory=$false)]
    [Nullable[DateTime]]$endDate = $null
)

# Build queryVariables with the required start date parameter value
$queryVariables = @{
    gte = $startDate.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
}

# Add the optional end date paramater if provided
if ($null -ne $endDate) { 
    $queryVariables.lt = $endDate.ToString("yyyy-MM-ddTHH:mm:ss.fffZ") 
}

# Define the GraphQL query file path
$QueryFilePath = Join-Path $PSScriptRoot "..\Gql\Audit\exportAudit.gql"
if (-not (Test-Path $QueryFilePath)) {
    throw "GraphQL file not found: $QueryFilePath"
}

# Call Common\Export.ps1 with ExportType=Audit and QueryVariables
$exportScript = Join-Path $PSScriptRoot ".\Common\Export.ps1"
if (-not (Test-Path $exportScript)) {
    Write-Host ".\Common\Export.ps1 script file was not found: $QueryFilePath"
    exit 1
}

# Execute the export script
& $exportScript -EntityName "Audit" -QueryFilePath $QueryFilePath -QueryVariables $queryVariables