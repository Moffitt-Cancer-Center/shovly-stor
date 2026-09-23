# Varonis’ sample code(s) are provided on an “as is” and “as available” basis and without any warranty of any kind.  
# Any use of Varonis’ sample code(s) is optional at client’s sole discretion, responsibility and risk.
# Varonis does not make any commitment with respect to Varonis’ sample code(s), their specific functions or their availability, reliability, or ability to meet client’s needs.
# Client acknowledges that Varonis may, in its sole discretion, modify, discontinue or update the Varonis’ sample code(s) from time to time, without notice and for any reason.

function TenantURl {
        param(
            $origin = $null
        )
    
        if ($origin -eq $null) {
            $origin = read-host -prompt "Tenant URL (ie: https://tenant.varonis.io)"
        }

        if(!($origin.StartsWith("https://"))) {
            Write-Host -ForegroundColor Red "Let's give that another whirl. Tenant URL must start with https://"
            clear-variable origin
            $origin = read-host -prompt "Tenant URL (ie: https://tenant.varonis.io)"
            $origin = TenantURl -origin $origin
        }

    return $origin
}

function apikey {
    param (
        $apikey = $null
    )

    if ($apikey -eq $null) {
        $apiKey = read-host -prompt "Access Control API key"
    }

    if(!($apikey.StartsWith("vkey"))) {
        Write-Host -ForegroundColor Red "Let's give that another whirl. API key must start with vkey"
        clear-variable apikey
        $apiKey = read-host -prompt "Access Control API key"
        $apikey = apikey -apikey $apikey
    }
return $apiKey
}