# Tested with PowerShell 5.1

# Varonis' sample code(s) are provided on an "as is" and "as available" basis and without any warranty of any kind.  
# Any use of Varonis' sample code(s) is optional at client's sole discretion, responsibility and risk. 
# Varonis does not make any commitment with respect to Varonis' sample code(s), their specific functions or their availability, reliability, or ability to meet client's needs. 
# Client acknowledges that Varonis may, in its sole discretion, modify, discontinue or update the Varonis' sample code(s) from time to time, without notice and for any reason.

# Define the module path relative to this module's location
$script:modulesPath = Split-Path -Parent $PSCommandPath

# Import dependencies
Import-Module (Join-Path $modulesPath "authentication.psm1") -Force


# A GraphQL client class that supports token refresh
class GraphqlClient {
    [string]$Url
    [object]$Auth
    
    GraphqlClient([string]$Origin, [object]$Auth) {
        Write-Host "Initializing GraphQL client: $Origin"
        $this.Url = "$($Origin.TrimEnd('/'))/api/graphql"
        $this.Auth = $Auth
        Write-Host "Initialized"
    }
    
    [object] ExecuteQuery([string]$query, [hashtable]$variables) {
        $headers = @{
            'Authorization' = "Bearer $($this.Auth.Token)"
            'Content-Type' = 'application/json'
        }
        
        $body = @{
            query = $query      # Both Queries and Mutations are both sent using the query field
            variables = $variables
        } | ConvertTo-Json -Depth 25
        
        try {
            $response = Invoke-RestMethod -Uri $this.Url -Method Post -Headers $headers -Body $body
            return $response.data
        }
        catch {
            $response = $_.Exception.Response
            if ($response.StatusCode -in [System.Net.HttpStatusCode]::Unauthorized, [System.Net.HttpStatusCode]::Forbidden) {  # Handle token expiration
                Write-Host "Failed with status $($response.StatusCode). Obtain new token."
                $headers.Authorization = "Bearer $($this.Auth.RefreshToken())"
                $response = Invoke-RestMethod -Uri $this.Url -Method Post -Headers $headers -Body $body
                return $response.data
            }
            throw "Error executing GraphQL query: $($_.Exception.Message)"
        }
    }

    [object] ExecuteQuery([string]$query) {
        return $this.ExecuteQuery($query, @{})
    }

    [object] ExecuteMutation([string]$mutation, [hashtable]$variables) {
        return $this.ExecuteQuery($mutation, $variables)
    }

    [object] ExecuteMutation([string]$mutation) {
        return $this.ExecuteQuery($mutation, @{})
    }
}

function New-GraphqlClient {
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Origin,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [object]$Auth
    )
    return [GraphqlClient]::new($Origin, $Auth)
}
