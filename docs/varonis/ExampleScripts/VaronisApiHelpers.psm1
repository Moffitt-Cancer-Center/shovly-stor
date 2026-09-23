# VaronisApiHelpers.psm1
# Shared functions for Varonis Search API PowerShell scripts

function Get-ConfigFile {
    <#
    .SYNOPSIS
    Locates the config.json file for the SearchAPI scripts.
    
    .DESCRIPTION
    Searches for config.json in multiple locations:
    1. ExampleScripts root directory (one level up from script location)
    2. Current script directory
    3. Current working directory
    
    .OUTPUTS
    String path to the config.json file
    #>
    
    # Get the script directory to look for config file
    $scriptDir = Split-Path -Parent $MyInvocation.ScriptName
    if (-not $scriptDir) {
        $scriptDir = Get-Location
    }
    
    # Look for config.json in the ExampleScripts root directory (one level up from subfolder)
    $configFile = Join-Path (Split-Path -Parent $scriptDir) "config.json"
    
    # If not found in ExampleScripts root, look in current script directory
    if (-not (Test-Path $configFile)) {
        $configFile = Join-Path $scriptDir "config.json"
    }
    
    # If still not found, look in current working directory
    if (-not (Test-Path $configFile)) {
        $configFile = "config.json"
    }
    
    return $configFile
}

function Get-GraphQLQueryFile {
    <#
    .SYNOPSIS
    Locates the GraphQL query file for a script.
    
    .DESCRIPTION
    Constructs the path to the GraphQL query file based on the script location and query filename.
    
    .PARAMETER QueryFileName
    The name of the GraphQL query file (e.g., "Inconsistent (Broken) Permissions.gql")
    
    .OUTPUTS
    String path to the GraphQL query file
    #>
    param (
        [Parameter(Mandatory=$true)]
        [string]$QueryFileName
    )
    
    # Get the script directory to look for GraphQL file
    $scriptDir = Split-Path -Parent $MyInvocation.ScriptName
    if (-not $scriptDir) {
        $scriptDir = Get-Location
    }
    
    # Path to the GraphQL file relative to script location
    $gqlFile = Join-Path $scriptDir "Gql\$QueryFileName"
    
    if (-not (Test-Path $gqlFile)) {
        throw "GraphQL file not found: $gqlFile"
    }
    
    return $gqlFile
}

function Get-AccessToken {
    <#
    .SYNOPSIS
    Obtains an access token from the Varonis API.
    
    .DESCRIPTION
    Uses the API key from the config to request an access token for GraphQL API calls.
    
    .PARAMETER Config
    Configuration object containing domain and apiKey
    
    .OUTPUTS
    String access token for API authentication
    #>
    param (
        [Parameter(Mandatory=$true)]
        [object]$Config
    )

    # URL to request the access token
    $url = "https://$($Config.domain)/api/authentication/api_keys/token"

    # Logging the URL for debugging purposes
    Write-Host "Requesting access token from: $url"

    try {
        # Invoke the REST method to get the access token
        $response = Invoke-RestMethod -Method Post -Uri $url -Headers @{
            "x-api-key" = $Config.api_key
            "Content-Type" = "application/x-www-form-urlencoded"
        } -Body @{
            "grant_type" = "varonis_custom"
        }

        # Logging the response for debugging purposes
        Write-Host "Access token received successfully"

        return $response.access_token
    } catch {
        Write-Host "Failed to obtain access token: $_"
        throw "Failed to obtain access token. Please check your domain and API key in the config file."
    }
}

function Extract-ResultsStructureFromQuery {
    <#
    .SYNOPSIS
    Extracts the results structure from a GraphQL query for polling purposes.
    
    .DESCRIPTION
    Parses a GraphQL query to extract the results block structure needed for async query polling.
    
    .PARAMETER Query
    The complete GraphQL query string
    
    .OUTPUTS
    String containing the results block structure for polling queries
    #>
    param (
        [Parameter(Mandatory=$true)]
        [string]$Query
    )
    
    # Find the start of the results block
    $resultsStart = $Query.IndexOf('results {')
    if ($resultsStart -eq -1) {
        throw "Could not find 'results {' in GraphQL query"
    }
    
    # Start after 'results {'
    $startPos = $resultsStart + 9  # Length of 'results {'
    $braceCount = 1
    $currentPos = $startPos
    
    # Count braces to find the matching closing brace
    while ($currentPos -lt $Query.Length -and $braceCount -gt 0) {
        $char = $Query[$currentPos]
        if ($char -eq '{') {
            $braceCount++
        } elseif ($char -eq '}') {
            $braceCount--
        }
        $currentPos++
    }
    
    if ($braceCount -ne 0) {
        throw "Could not find matching closing brace for results block"
    }
    
    # Extract the content between the braces (excluding the final closing brace)
    $resultsContent = $Query.Substring($startPos, $currentPos - $startPos - 1).Trim()
    
    # Return the complete results block
    return "results {`n$resultsContent`n}"
}

function Save-Results {
    <#
    .SYNOPSIS
    Saves query results to a JSON file.
    
    .DESCRIPTION
    Creates the destination directory if needed and saves the results as formatted JSON.
    
    .PARAMETER Results
    Array of results to save
    
    .PARAMETER DestinationFolder
    Folder path where the file should be saved
    
    .PARAMETER FileName
    Name of the output file
    
    .PARAMETER ResultType
    Type of results for logging (e.g., "permission entries", "events", "objects")
    #>
    param (
        [Parameter(Mandatory=$false)]
        [AllowNull()]
        [array]$Results,
        
        [Parameter(Mandatory=$true)]
        [string]$DestinationFolder,
        
        [Parameter(Mandatory=$true)]
        [string]$FileName,
        
        [Parameter(Mandatory=$false)]
        [string]$ResultType = "items"
    )

    # Handle null or empty results
    if ($null -eq $Results) {
        Write-Warning "No results returned from query - Results parameter is null"
        $Results = @()
    }
    elseif ($Results.Count -eq 0) {
        Write-Warning "No results returned from query - Results array is empty"
    }

    # Ensure the destination directory exists
    if (-not (Test-Path -Path $DestinationFolder)) {
        Write-Host "Creating destination folder: $DestinationFolder"
        New-Item -ItemType Directory -Path $DestinationFolder -Force
    }

    $outputPath = Join-Path -Path $DestinationFolder -ChildPath $FileName

    try {
        # Convert results to JSON and save
        $jsonResults = $Results | ConvertTo-Json -Depth 10
        $jsonResults | Out-File -FilePath $outputPath -Encoding UTF8

        Write-Host "Results saved to: $outputPath"
        Write-Host "Total $ResultType found: $($Results.Count)"

    } catch {
        Write-Host "Failed to save results to $outputPath : $_"
        throw "Failed to save results."
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
        if ($response.data.resourcesExportAsync) {
            $jobId = $response.data.resourcesExportAsync.jobId
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

function Invoke-GraphQLQuery {
    <#
    .SYNOPSIS
    Executes a Varonis GraphQL query with async polling support.
    
    .DESCRIPTION
    A generic function to execute any GraphQL query against the Varonis API.
    Handles both synchronous and asynchronous queries with automatic polling.
    
    .PARAMETER Query
    The GraphQL query string to execute
    
    .PARAMETER Config
    Configuration object containing domain and apiKey
    
    .PARAMETER Variables
    Hashtable of variables to pass to the GraphQL query
    
    .PARAMETER QueryDescription
    Description of the query for logging purposes
    
    .PARAMETER QueryType
    Type of query (events, identities, resources, physicalPermissions) for API response handling
    
    .OUTPUTS
    Array of results from the query
    #>
    param (
        [Parameter(Mandatory=$true)]
        [string]$Query,
        
        [Parameter(Mandatory=$true)]
        [object]$Config,
        
        [Parameter(Mandatory=$false)]
        [hashtable]$Variables = @{},
        
        [Parameter(Mandatory=$true)]
        [string]$QueryDescription,
        
        [Parameter(Mandatory=$true)]
        [ValidateSet("events", "identities", "resources", "physicalPermissions")]
        [string]$QueryType
    )

    # Get the access token
    $token = Get-AccessToken -Config $Config

    # URL for the GraphQL API
    $url = "https://$($Config.domain)/api/graphql"
    $headers = @{
        "Authorization" = "Bearer $token"
        "Content-Type" = "application/json"
    }

    $body = @{
        query = $Query
        variables = $Variables
    } | ConvertTo-Json -Depth 3

    # Logging the query for debugging purposes
    Write-Host "Querying $QueryDescription"
    if ($Variables.Count -gt 0) {
        $variableInfo = ($Variables.GetEnumerator() | ForEach-Object { "$($_.Key): $($_.Value)" }) -join ", "
        Write-Host "Variables: $variableInfo"
    }
    Write-Host "`n--- GraphQL Request ---"
    Write-Host "Endpoint: $url"
    Write-Host "Request Query:`n$Query"
    Write-Host "Request body:`n$body"
    Write-Host "--- End GraphQL Request ---`n"

    try {
        # Invoke the REST method
        $response = Invoke-RestMethod -Uri $url -Method Post -Headers $headers -Body $body

        if ($response.errors) {
            throw "GraphQL errors: $($response.errors | ConvertTo-Json)"
        }

        # Dynamic response handling based on query type
        $asyncProperty = "${QueryType}Async"
        $asyncData = $response.data.$asyncProperty

        # Check if this is an async query that needs polling
        if ($asyncData.jobStatus -eq "EXECUTING") {
            Write-Host "Query is running asynchronously. JobId: $($asyncData.jobId)"
            Write-Host "Polling for results..."
            
            # Poll for results
            $jobId = $asyncData.jobId
            $pollResponse = Poll-GraphQLQueryJob -JobId $jobId -Token $token -Url $url -BaseQuery $Query -Config $Config -QueryType $QueryType
            return $pollResponse
        } else {
            # Query completed immediately
            $resultCount = if ($asyncData.results) { $asyncData.results.Count } else { 0 }
            Write-Host "Query completed. Found $resultCount $QueryType."
            return $asyncData.results
        }
    } catch {
        Write-Host "Failed to query $QueryDescription`: $_"
        throw "Failed to query $QueryType. Please check your GraphQL query and API endpoint."
    }
}

function Poll-GraphQLQueryJob {
    <#
    .SYNOPSIS
    Polls an asynchronous GraphQL query job until completion.
    
    .DESCRIPTION
    Handles the polling logic for async GraphQL queries, checking job status
    and retrieving results when the job completes.
    
    .PARAMETER JobId
    The job ID returned from the async query
    
    .PARAMETER Token
    Access token for API authentication
    
    .PARAMETER Url
    GraphQL API endpoint URL
    
    .PARAMETER BaseQuery
    Original query string to extract results structure
    
    .PARAMETER Config
    Configuration object for refreshing tokens
    
    .PARAMETER QueryType
    Type of query (events, identities, resources, physicalPermissions) for API response handling
    
    .OUTPUTS
    Array of results when job completes
    #>
    param (
        [Parameter(Mandatory=$true)]
        [string]$JobId,
        
        [Parameter(Mandatory=$true)]
        [string]$Token,
        
        [Parameter(Mandatory=$true)]
        [string]$Url,
        
        [Parameter(Mandatory=$true)]
        [string]$BaseQuery,
        
        [Parameter(Mandatory=$false)]
        [object]$Config,
        
        [Parameter(Mandatory=$true)]
        [ValidateSet("events", "identities", "resources", "physicalPermissions")]
        [string]$QueryType
    )

    $headers = @{
        "Authorization" = "Bearer $Token"
        "Content-Type" = "application/json"
    }

    $maxAttempts = 10
    $attempt = 0
    $waitTime = 5
    
    # Extract results structure from the original query
    $resultsStructure = Extract-ResultsStructureFromQuery -Query $BaseQuery

    while ($attempt -lt $maxAttempts) {
        $attempt++
        Write-Host "Polling attempt $attempt of $maxAttempts..."

        $jobQueryName = "${QueryType}QueryJob"
        $pollQuery = @"
        query {
            $jobQueryName(jobId: "$JobId") {
                jobId    
                jobStatus
                $resultsStructure
            }
        }
"@

        $pollBody = @{
            query = $pollQuery
        } | ConvertTo-Json

        try {
            # Get fresh access token for polling if config is provided
            if ($Config) {
                $freshToken = Get-AccessToken -Config $Config
                $headers["Authorization"] = "Bearer $freshToken"
            }
            
            Write-Host "`n--- Polling GraphQL Request ---"
            Write-Host "Polling Query:`n$pollQuery"
            Write-Host "--- End Polling GraphQL Request ---`n"
            $pollResponse = Invoke-RestMethod -Uri $Url -Method Post -Headers $headers -Body $pollBody
            
            if ($pollResponse.errors) {
                Write-Host "GraphQL errors during polling: $($pollResponse.errors | ConvertTo-Json)"
                Start-Sleep -Seconds $waitTime
                continue
            }
            
            $jobData = $pollResponse.data.$jobQueryName
            if ($jobData.jobStatus -eq "COMPLETED") {
                $resultCount = if ($jobData.results) { $jobData.results.Count } else { 0 }
                Write-Host "Query completed successfully. Found $resultCount $QueryType."
                return $jobData.results
            } elseif ($jobData.jobStatus -eq "FAILED") {
                throw "Async query failed."
            } else {
                Write-Host "Query still running... waiting $waitTime seconds before next poll."
                Start-Sleep -Seconds $waitTime
            }
        } catch {
            Write-Host "Error polling for results: $_"
            Start-Sleep -Seconds $waitTime
        }
    }

    throw "Query timed out after $maxAttempts attempts."
}

function Invoke-EventsQuery {
    <#
    .SYNOPSIS
    Executes a Varonis events GraphQL query with async polling support.
    
    .DESCRIPTION
    A convenience wrapper for events queries that handles date range and data source filtering.
    
    .PARAMETER Query
    The GraphQL query string to execute
    
    .PARAMETER Config
    Configuration object containing domain and apiKey
    
    .PARAMETER FromDate
    Start date for the query in ISO format
    
    .PARAMETER ToDate
    End date for the query in ISO format
    
    .PARAMETER DataSourceIds
    Array of data source IDs to filter by (optional)
    
    .PARAMETER QueryDescription
    Description of the query for logging purposes
    
    .OUTPUTS
    Array of event results from the query
    #>
    param (
        [Parameter(Mandatory=$true)]
        [string]$Query,
        
        [Parameter(Mandatory=$true)]
        [object]$Config,
        
        [Parameter(Mandatory=$true)]
        [string]$FromDate,
        
        [Parameter(Mandatory=$true)]
        [string]$ToDate,
        
        [Parameter(Mandatory=$false)]
        [int[]]$DataSourceIds = @(),
        
        [Parameter(Mandatory=$true)]
        [string]$QueryDescription
    )

    $variables = @{
        fromDate = $FromDate
        toDate = $ToDate
        dataSourceIds = $DataSourceIds
    }

    return Invoke-GraphQLQuery -Query $Query -Config $Config -Variables $variables -QueryDescription $QueryDescription -QueryType "events"
}

function Invoke-IdentitiesQuery {
    <#
    .SYNOPSIS
    Executes a Varonis identities GraphQL query with async polling support.
    
    .DESCRIPTION
    A convenience wrapper for identities queries with simplified parameter handling.
    
    .PARAMETER Query
    The GraphQL query string to execute
    
    .PARAMETER Config
    Configuration object containing domain and apiKey
    
    .PARAMETER QueryDescription
    Description of the query for logging purposes
    
    .OUTPUTS
    Array of user results from the query
    #>
    param (
        [Parameter(Mandatory=$true)]
        [string]$Query,
        
        [Parameter(Mandatory=$true)]
        [object]$Config,
        
        [Parameter(Mandatory=$true)]
        [string]$QueryDescription
    )

    # identities queries typically don't need variables, but we'll pass an empty hashtable
    $variables = @{}

    return Invoke-GraphQLQuery -Query $Query -Config $Config -Variables $variables -QueryDescription $QueryDescription -QueryType "identities"
}

function Invoke-PhysicalPermissionsQuery {
    <#
    .SYNOPSIS
    Executes a Varonis physical permissions GraphQL query with async polling support.
    
    .DESCRIPTION
    A convenience wrapper for physical permissions queries that handles data source filtering.
    
    .PARAMETER Query
    The GraphQL query string to execute
    
    .PARAMETER Config
    Configuration object containing domain and apiKey
    
    .PARAMETER DataSourceIds
    Array of data source IDs to filter by (optional)
    
    .PARAMETER QueryDescription
    Description of the query for logging purposes
    
    .OUTPUTS
    Array of physical permissions results from the query
    #>
    param (
        [Parameter(Mandatory=$true)]
        [string]$Query,
        
        [Parameter(Mandatory=$true)]
        [object]$Config,
        
        [Parameter(Mandatory=$false)]
        [int[]]$DataSourceIds = @(),
        
        [Parameter(Mandatory=$true)]
        [string]$QueryDescription
    )

    $variables = @{
        dataSourceIds = $DataSourceIds
    }

    return Invoke-GraphQLQuery -Query $Query -Config $Config -Variables $variables -QueryDescription $QueryDescription -QueryType "physicalPermissions"
}

function Invoke-ResourcesQuery {
    <#
    .SYNOPSIS
    Executes a Varonis resources GraphQL query with async polling support.
    
    .DESCRIPTION
    A convenience wrapper for resources queries that handles data source filtering.
    
    .PARAMETER Query
    The GraphQL query string to execute
    
    .PARAMETER Config
    Configuration object containing domain and apiKey
    
    .PARAMETER DataSourceIds
    Array of data source IDs to filter by (optional)
    
    .PARAMETER QueryDescription
    Description of the query for logging purposes
    
    .OUTPUTS
    Array of resources results from the query
    #>
    param (
        [Parameter(Mandatory=$true)]
        [string]$Query,
        
        [Parameter(Mandatory=$true)]
        [object]$Config,
        
        [Parameter(Mandatory=$false)]
        [int[]]$DataSourceIds = @(),
        
        [Parameter(Mandatory=$true)]
        [string]$QueryDescription
    )

    $variables = @{
        dataSourceIds = $DataSourceIds
    }

    return Invoke-GraphQLQuery -Query $Query -Config $Config -Variables $variables -QueryDescription $QueryDescription -QueryType "resources"
}