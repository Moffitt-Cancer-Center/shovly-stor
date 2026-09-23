# Tested with PowerShell 5.1

# Varonis' sample code(s) are provided on an "as is" and "as available" basis and without any warranty of any kind.  
# Any use of Varonis' sample code(s) is optional at client's sole discretion, responsibility and risk. 
# Varonis does not make any commitment with respect to Varonis' sample code(s), their specific functions or their availability, reliability, or ability to meet client's needs. 
# Client acknowledges that Varonis may, in its sole discretion, modify, discontinue or update the Varonis' sample code(s) from time to time, without notice and for any reason.

# Import required modules
Import-Module (Join-Path $modulesPath "authentication.psm1") -Force


# A REST client class that supports token refresh
class RestClient {
    [string]$Origin
    [object]$Auth
    [hashtable]$Headers

    RestClient([string]$Origin, [object]$Auth) {
        $this.Origin = $Origin
        $this.Auth = $Auth
        $this.SetBearerHeader($this.Auth.Token)
    }

    [void] SetBearerHeader([string]$AuthToken) {
        $this.Headers = @{
            Authorization = "Bearer $AuthToken"
        }
    }

    [void] RefreshToken() {
        Write-Host "Refreshing token..."
        $this.SetBearerHeader($this.Auth.RefreshToken())
    }

    [Microsoft.PowerShell.Commands.WebResponseObject] Get([string]$endpoint,[string]$topath,[string]$filename) {
        Write-Host "Requesting GET endpoint: $endpoint"
        $url = if ($endpoint.StartsWith('http')) { $endpoint } else { "$($this.Origin.TrimEnd('/'))/$endpoint" }
        try {
            return Invoke-WebRequest -Uri $url -Headers $this.Headers -UseBasicParsing -OutFile $topath\$filename
            #return Invoke-WebRequest -Uri $url -Headers $this.Headers -UseBasicParsing
        } catch [System.Net.WebException] {
            $response = $_.Exception.Response
            if ($response.StatusCode -eq 401 -or $response.StatusCode -eq 403) {
                Write-Host "Unauthorized or Forbidden request. Refreshing token..."
                $this.RefreshToken()
                return Invoke-WebRequest -Uri $url -Headers $this.Headers -UseBasicParsing 
            } else {
                throw "Error executing GET request: $($_.Exception.Message)"
            }
        }
    }

}

function New-RestClient {
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Origin,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [object]$Auth
    )
    return [RestClient]::new($Origin, $Auth)
}
