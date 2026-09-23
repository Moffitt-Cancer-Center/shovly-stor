# Varonis' sample code(s) are provided on an "as is" and "as available" basis and without any warranty of any kind.  
# Any use of Varonis' sample code(s) is optional at client's sole discretion, responsibility and risk. 
# Varonis does not make any commitment with respect to Varonis' sample code(s), their specific functions or their availability, reliability, or ability to meet client's needs. 
# Client acknowledges that Varonis may, in its sole discretion, modify, discontinue or update the Varonis' sample code(s) from time to time, without notice and for any reason.

<#
.SYNOPSIS
    Parses domain\username format into separate domain and username components.

.DESCRIPTION
    This module provides functions to split SamAccountName format (DOMAIN\username) 
    into separate domain and username parts for use with Varonis API calls.

.EXAMPLE
    $result = Split-SamAccountName -SamAccountName "CONTOSO\jsmith"
    Write-Host "Domain: $($result.Domain), Username: $($result.Username)"
#>

function Split-SamAccountName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$SamAccountName
    )
    
    process {
        # Check if the input contains a backslash
        if ($SamAccountName -notmatch '\\') {
            Write-Warning "SamAccountName '$SamAccountName' does not contain a backslash. Assuming no domain."
            return @{
                Domain = $null
                Username = $SamAccountName
                FullName = $SamAccountName
            }
        }
        
        # Split on backslash
        $parts = $SamAccountName -split '\\', 2
        
        if ($parts.Count -ne 2) {
            Write-Error "Invalid SamAccountName format: $SamAccountName. Expected format: DOMAIN\username"
            return $null
        }
        
        return [PSCustomObject]@{
            Domain = $parts[0].Trim()
            Username = $parts[1].Trim()
            FullName = $SamAccountName
        }
    }
}

function Get-DomainFromSamAccountName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$SamAccountName
    )
    
    process {
        $parsed = Split-SamAccountName -SamAccountName $SamAccountName
        return $parsed.Domain
    }
}

function Get-UsernameFromSamAccountName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$SamAccountName
    )
    
    process {
        $parsed = Split-SamAccountName -SamAccountName $SamAccountName
        return $parsed.Username
    }
}

# Export functions
Export-ModuleMember -Function Split-SamAccountName, Get-DomainFromSamAccountName, Get-UsernameFromSamAccountName