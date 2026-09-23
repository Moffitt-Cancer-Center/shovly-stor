param (
    [string]$env,
    [string]$key,
    [string[]]$ids,
	[bool]$debug = $false
)

$global:token= ""

# Dot-source the file (ensure the path is correct)
. ".\GqlFunctions.ps1"

# Set the security protocol to TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Input validation
if (-not $env) { throw "Environment (env) parameter is required." }
if (-not $key) { throw "API key (key) parameter is required." }
if (-not $ids) { throw "List of alert ids parameter is required." }
# Main Script

try {
	$global:token = Get-AccessToken -env $env -key $key
    # Create get alerted events job request
	$jobResponse = Get-AlertedEventsAsync -alertId $ids
    $jobId = $jobResponse.data.alertedEventsAsync.jobId
	$jobStatus = $jobResponse.data.alertedEventsAsync.jobStatus
	$counter = 1
	
    # Check if the job create successfuly and jobId exists
    if ($jobId) {
		do {
		$counter += 1
		# Wait for 1 seconds
		Start-Sleep -Seconds 1
		$jobQueryResponse = Get-AlertedEventsQueryJob -jobId $jobId
		$jobStatus = $jobQueryResponse.data.alertedEventsQueryJob.jobStatus
		} while ($jobStatus -ne "COMPLETED" -and $counter -lt 10)
	   
    } else {
        Write-Host "jobId not found in Get-AlertedEventsAsync response."
    }
	
	if ($jobStatus -eq "COMPLETED")
	{
		Write-Host "get alerted events query result: `n $($jobQueryResponse | ConvertTo-Json -Depth 10)"
	}
} catch {
    Write-Host "An error occurred: $_"
}
