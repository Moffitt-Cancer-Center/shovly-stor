param (
    [string]$env,
    [string]$key,
    [string]$id,
	[int]$reason,
	[string]$note,
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
if (-not $id) { throw "Alert ID parameter is required." }
if (-not $reason) { throw "Close reason id parameter is required." }
if (-not $note) { throw "Note parameter is required." }

# Close the alert
try {
		$global:token = Get-AccessToken -env $env -key $key
		# Create the mutation request for CloseAlerts
		$closeResponse = Set-CloseAlerts -alertIds $id -closeReason $reason
		Write-Host "Mutation result for CloseAlerts: `n $($closeResponse | ConvertTo-Json -Depth 10)"
		$closeStatus = $closeResponse.data.closeAlerts[0].succeeded

		# Check if the job create successfuly and jobId exists
		if ($closeStatus) {
			$Response = Set-AddNoteToAlerts -alertId $id -note $note
			Write-Host "Mutation result for AddNote: `n $($Response | ConvertTo-Json -Depth 10)" 
		} 
		else
		{
			Write-Host "Failed to close the alert with ID $id. Please check the alert ID and try again."
		}
	}
	catch {
		Write-Host "An error occurred: $_"
	}
