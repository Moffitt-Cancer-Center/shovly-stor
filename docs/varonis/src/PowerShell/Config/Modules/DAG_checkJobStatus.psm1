# Varonis’ sample code(s) are provided on an “as is” and “as available” basis and without any warranty of any kind.  
# Any use of Varonis’ sample code(s) is optional at client’s sole discretion, responsibility and risk.
# Varonis does not make any commitment with respect to Varonis’ sample code(s), their specific functions or their availability, reliability, or ability to meet client’s needs.
# Client acknowledges that Varonis may, in its sole discretion, modify, discontinue or update the Varonis’ sample code(s) from time to time, without notice and for any reason.

function TestJob {
    param(
        [string]$jobstatus 
    )
    if ($jobstatus -eq "PENDING")
    {
        return $true
    }
    elseif ($jobstatus -eq "COMPLETED")
    {
        return $false
    }
    elseif ($jobstatus -eq "FAILED") {
        return "Critical Failure"
    }
    elseif ($jobstatus -eq "Executing") {
        return $true
    }
}