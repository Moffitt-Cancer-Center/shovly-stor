param (
    [string]$env,
    [string]$key,
	[int]$reason,
	[string]$note,
	[bool]$debug = $false
)

$global:token= ""

# Dot-source the file (ensure the path is correct)
. ".\GqlFunctions.ps1"

# Input validation
if (-not $env) { throw "Environment (env) parameter is required." }
if (-not $key) { throw "API key (key) parameter is required." }
if (-not $reason) { throw "Close reason id parameter is required." }
if (-not $note) { throw "Note parameter is required." }

# Main Script

try {
	$to = Get-Date
    $from = $to.AddMinutes(-30)

	$global:token = Get-AccessToken -env $env -key $key
    # Create get alert job request
	$jobResponse = Get-AlertsForDateRangeAsync -fromDate $from -toDate $to -severity "HIGH" -status "NEW"
    $jobId = $jobResponse.data.AlertsAsync.jobId
	$jobStatus = $jobResponse.data.AlertsAsync.jobStatus
	$counter = 1
	
    # Check if the job create successfuly and jobId exists
    if ($jobId) {
		do {
		$counter += 1
		# Wait for 1 seconds
		Start-Sleep -Seconds 1
		$jobQueryResponse = Get-alertsQueryJob -jobId $jobId
		$jobStatus = $jobQueryResponse.data.alertsQueryJob.jobStatus
		} while ($jobStatus -ne "COMPLETED" -and $counter -lt 10)
	   
    } else {
        throw "jobId not found in Get-AlertsForDateRangeAsync response."
    }
	
	if ($jobStatus -ne "COMPLETED")
	{
		Write-Host "Get Alert query result: `n $($jobQueryResponse | ConvertTo-Json -Depth 10)"
		throw "Failed to get alerts - job not COMPLETED"
	}
	
	# Output the total count
	$results = $jobQueryResponse.data.alertsQueryJob.results
	$count = $results.Count
	
	# Output the count
	Write-Host "Number of results with severity 'HIGH' and status NEW: $count"
	
	# Extract IDs from the filtered results
	$ids = $results | Select-Object -ExpandProperty id

	# Output the list of IDs
	Write-Host "Alert IDs:"
	$ids | ForEach-Object { Write-Host $_ }
	
	Write-Host "-----Setting status to "UNDER INVESTIGATION" for $count alerts-----"
	
	$setStatusResponse = Set-AlertsStatus -alertIds $ids
	Write-Host "Mutation set status result: `n $($setStatusResponse | ConvertTo-Json -Depth 10)"

	Write-Host "-----Getting alerted events for $count alerts-----"
	
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
        Write-Host "jobId not found in Get-alertedEventsQueryJob response."
    }
	
	if ($jobStatus -ne "COMPLETED")
	{
		Write-Host "get alerted events query result: `n $($jobQueryResponse | ConvertTo-Json -Depth 10)"
		throw "Failed to get alerted events - job not COMPLETED"
	}
	
	# Count all results
	$totalEventsCount = $jobQueryResponse.data.alertedEventsQueryJob.results.Count

	# Output the total count
	Write-Host "Total number of events: $totalEventsCount"
	
	
	Write-Host "-----Closing $count alerts-----"
	# Create the mutation job request
	$closeResponse = Set-CloseAlerts -alertIds $ids -closeReason $reason
	Write-Host "Mutation close alerts result: `n $($closeResponse | ConvertTo-Json -Depth 10)"

	# Find successfuly closed alerts
	$filteredAlerts = $closeResponse.data.closeAlerts | Where-Object { $_.succeeded }
	$ids = $filteredAlerts | ForEach-Object { $_.result.id }
	$count = ($ids | Measure-Object).Count

	
	Write-Host "-----Adding closing note to $count alerts-----"
	
	# Check if the job create successfuly and jobId exists
	if ($ids) {
		$noteResponse = Set-AddNoteToAlerts -alertId $ids -note $note
		Write-Host "Mutation addNote result: `n $($noteResponse | ConvertTo-Json -Depth 10)"
	   
	} 
	else {
		Write-Host "No alerts to to add notes to."
	}
} catch {
    Write-Host "An error occurred: $_"
}
