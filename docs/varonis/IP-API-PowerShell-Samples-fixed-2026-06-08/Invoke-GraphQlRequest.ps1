[CmdletBinding()]
param(
    [Alias('TenantUrl', 'URL')]
    [string]$Origin,

    [Alias('Key')]
    [string]$ApiKey,

    [Parameter(Mandatory = $true)]
    [string]$QueryPath,

    [string]$OperationName,

    [hashtable]$Variables,

    [hashtable]$Headers,

    [ValidateSet('Post', 'Get')]
    [string]$Method = 'Post',

    [switch]$RawResponse
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-ConfiguredValue {
    param(
        [string]$Value,
        [string[]]$Placeholders
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $false
    }

    return $Placeholders -notcontains $Value
}

function Get-ConfigPath {
    Join-Path -Path $PSScriptRoot -ChildPath 'Config\config.json'
}

function Import-Configuration {
    $configPath = Get-ConfigPath

    if (-not (Test-Path -LiteralPath $configPath)) {
        return $null
    }

    Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
}

function Resolve-Origin {
    param(
        [string]$OriginValue,
        [object]$Config
    )

    $resolvedOrigin = $OriginValue
    if (-not (Test-ConfiguredValue -Value $resolvedOrigin -Placeholders @('https://tenant.varonis.io', 'https://your-tenant.varonis.io'))) {
        $resolvedOrigin = $Config.tenant.url
    }

    if (-not (Test-ConfiguredValue -Value $resolvedOrigin -Placeholders @('https://tenant.varonis.io', 'https://your-tenant.varonis.io'))) {
        $resolvedOrigin = Read-Host 'Enter your Varonis domain or tenant URL'
    }

    $resolvedOrigin = $resolvedOrigin.Trim()
    if ($resolvedOrigin -notmatch '^https?://') {
        $resolvedOrigin = "https://$resolvedOrigin"
    }

    $resolvedOrigin.TrimEnd('/')
}

function Resolve-ApiKey {
    param(
        [string]$ApiKeyValue,
        [object]$Config
    )

    $resolvedApiKey = $ApiKeyValue
    if (-not (Test-ConfiguredValue -Value $resolvedApiKey -Placeholders @('api_key', 'your-api-key-here'))) {
        $resolvedApiKey = $Config.tenant.apiKey
    }

    if (-not (Test-ConfiguredValue -Value $resolvedApiKey -Placeholders @('api_key', 'your-api-key-here'))) {
        $resolvedApiKey = Read-Host 'Enter your API key'
    }

    $resolvedApiKey.Trim()
}

function Get-AccessToken {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ResolvedOrigin,

        [Parameter(Mandatory = $true)]
        [string]$ResolvedApiKey
    )

    $headers = @{
        'x-api-key' = $ResolvedApiKey
        'Content-Type' = 'application/x-www-form-urlencoded'
        Accept = 'application/json'
    }

    $tokenEndpoint = "$ResolvedOrigin/api/authentication/api_keys/token"
    $tokenResponse = Invoke-RestMethod -Uri $tokenEndpoint -Method Post -Headers $headers -Body 'grant_type=varonis_custom'

    if ([string]::IsNullOrWhiteSpace($tokenResponse.access_token)) {
        throw 'Authentication response did not include an access token.'
    }

    $tokenResponse.access_token
}

function ConvertTo-QueryString {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Parameters
    )

    $pairs = foreach ($key in $Parameters.Keys) {
        if ($null -eq $Parameters[$key]) {
            continue
        }

        '{0}={1}' -f [System.Uri]::EscapeDataString([string]$key), [System.Uri]::EscapeDataString([string]$Parameters[$key])
    }

    [string]::Join('&', $pairs)
}

if (-not (Test-Path -LiteralPath $QueryPath)) {
    throw "Query file not found: $QueryPath"
}

$config = Import-Configuration
$resolvedOrigin = Resolve-Origin -OriginValue $Origin -Config $config
$resolvedApiKey = Resolve-ApiKey -ApiKeyValue $ApiKey -Config $config
$endpoint = "$resolvedOrigin/api/roles/graphql/ip_ranges"
$bearerToken = Get-AccessToken -ResolvedOrigin $resolvedOrigin -ResolvedApiKey $resolvedApiKey

$query = Get-Content -LiteralPath $QueryPath -Raw
$payload = @{
    query = $query
}

if ($OperationName) {
    $payload.operationName = $OperationName
}

if ($Variables) {
    $payload.variables = $Variables
}

$requestHeaders = @{}
if ($Headers) {
    foreach ($key in $Headers.Keys) {
        $requestHeaders[$key] = $Headers[$key]
    }
}

$requestHeaders['Authorization'] = "Bearer $bearerToken"

if ($Method -eq 'Get') {
    $queryParameters = @{
        query = $query
    }

    if ($OperationName) {
        $queryParameters.operationName = $OperationName
    }

    if ($Variables) {
        $queryParameters.variables = ($Variables | ConvertTo-Json -Depth 10 -Compress)
    }

    $uriBuilder = [System.UriBuilder]::new($Endpoint)
    $uriBuilder.Query = ConvertTo-QueryString -Parameters $queryParameters

    $response = Invoke-RestMethod -Method Get -Uri $uriBuilder.Uri.AbsoluteUri -Headers $requestHeaders
}
else {
    $body = $payload | ConvertTo-Json -Depth 10
    $response = Invoke-RestMethod -Method Post -Uri $Endpoint -Headers $requestHeaders -ContentType 'application/json' -Body $body
}

if ($RawResponse) {
    return $response
}

if ($response.PSObject.Properties.Match('errors').Count -and $null -ne $response.errors) {
    $response.errors | ConvertTo-Json -Depth 10 | Write-Error
}

$response.data
