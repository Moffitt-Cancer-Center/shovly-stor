param (
    [string]$env,
    [string]$key,
	[bool]$debug = $false
)

$global:token= ""

# Dot-source the file (ensure the path is correct)
. ".\GqlFunctions.ps1"

# Input validation
if (-not $env) { throw "Environment (env) parameter is required." }
if (-not $key) { throw "API key (key) parameter is required." }

# Main Script

try {
	$to = Get-Date
    $from = $to.AddMinutes(-30)

	$global:token = Get-AccessToken -env $env -key $key
    # Create get alert job request
	$jobResponse = Get-AlertsForDateRangeAsync -fromDate $from -toDate $to -status "NEW"
    $jobId = $jobResponse.data.AlertsAsync.jobId
	$jobStatus = $jobResponse.data.AlertsAsync.jobStatus
	$counter = 1
	
    # Check if the job create successfuly and jobId exists
    if ($jobId) {
		do {
		$counter += 1
		# Wait for 1 seconds
		Start-Sleep -Seconds 1
		$jobQueryResponse = Get-AlertsQueryJob -jobId $jobId
		$jobStatus = $jobQueryResponse.data.alertsQueryJob.jobStatus
		} while ($jobStatus -ne "COMPLETED" -and $counter -lt 10)
	   
    } else {
        Write-Host "jobId not found in Get-AlertsAsync response."
    }
	
	if ($jobStatus -eq "COMPLETED")
	{
		Write-Host "Get Alert query result: `n $($jobQueryResponse | ConvertTo-Json -Depth 10)"
	}
} catch {
    Write-Host "An error occurred: $_"
}
