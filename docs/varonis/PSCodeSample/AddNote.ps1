param (
    [string]$env,
    [string]$key,
    [string]$id,
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
if (-not $note) { throw "Note parameter is required." }

# Main Script

try {
	$global:token = Get-AccessToken -env $env -key $key
    # Create the mutation job request
	$Response = Set-AddNoteToAlerts -alertId $id -note $note
	Write-Host "Mutation result: `n $($Response | ConvertTo-Json -Depth 10)"
	
} catch {
    Write-Host "An error occurred: $_"
}
