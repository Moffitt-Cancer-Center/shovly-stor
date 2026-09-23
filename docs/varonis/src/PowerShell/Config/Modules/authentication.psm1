# Tested with PowerShell 5.1

# Varonis' sample code(s) are provided on an "as is" and "as available" basis and without any warranty of any kind.  
# Any use of Varonis' sample code(s) is optional at client's sole discretion, responsibility and risk. 
# Varonis does not make any commitment with respect to Varonis' sample code(s), their specific functions or their availability, reliability, or ability to meet client's needs. 
# Client acknowledges that Varonis may, in its sole discretion, modify, discontinue or update the Varonis' sample code(s) from time to time, without notice and for any reason.

<#
.SYNOPSIS
    A class that manages the authentication process.
.DESCRIPTION
    The Authentication class manages the authentication process by obtaining an access token from the Varonis API.
.PARAMETER Origin
    The Varonis origin (server protocol and domain), e.g. https://mytenant.varonis.io.
.PARAMETER ApiKey
    The API key to use for authenticating all API calls.
.EXAMPLE
    $Origin = 'https://mytenant.varonis.io'
    $ApiKey = 'YOUR_API_KEY'
    [object]$Auth = New-Authentication -Origin $Origin -ApiKey $ApiKey
    # Get the auth token
    $Token = $Auth.Token
    Write-Host "Auth Token: $Token"
#>
class Authentication {
    [string]$Url
    [string]$ApiKey
    [string]$Token

    Authentication([string]$Origin, [string]$ApiKey) {
        Write-Host "Initializing authentication: $Origin"
        $this.Url = "$($Origin.TrimEnd('/'))/api/authentication/api_keys/token"
        $this.ApiKey = $ApiKey
        $this.RefreshToken()
    }
    
    [string] RefreshToken() {
        <#
        .SYNOPSIS
            Obtains a new access token from the Varonis API.
        .DESCRIPTION
            Obtains a new access token from the Varonis API using the API key provided during initialization.
        .EXAMPLE
            $Token = $Auth.RefreshToken()
            Write-Host "New Auth Token: $Token"
        #>
        Write-Host "Calling authentication endpoint: $this.Url"
        
        $headers = @{
            'x-api-key' = $this.ApiKey
            'Content-Type' = 'application/x-www-form-urlencoded'
            'Accept' = 'application/json'
        }
        
        try {
            $response = Invoke-RestMethod -Uri $this.Url -Method Post -Headers $headers -Body "grant_type=varonis_custom"
            Write-Host "Authentication succeeded"
            #Write-Host $response
            $this.Token = $response.access_token
            return $this.Token
        }
        catch {
            throw "Authentication failed: $($_.Exception.Message)"
        }
    }
}

function New-Authentication {
    <#
    .SYNOPSIS
        Creates a new instance of the Authentication class.
    .DESCRIPTION
        Creates a new instance of the Authentication class with the specified origin and API key.
    .PARAMETER Origin
        The Varonis origin (server protocol and domain), e.g. https://mytenant.varonis.io.
    .PARAMETER ApiKey
        The API key to use for authenticating all API calls.
    .EXAMPLE
        $Origin = 'https://mytenant.varonis.io'
        $ApiKey = 'YOUR_API_KEY'
        [object]$Auth = New-Authentication -Origin $Origin -ApiKey $ApiKey
        # Get the auth token
        $Token = $Auth.Token
        Write-Host "Auth Token: $Token"
    #>
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Origin,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ApiKey
    )
    return [Authentication]::new($Origin, $ApiKey)
}
