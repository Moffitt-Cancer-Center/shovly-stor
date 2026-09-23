[CmdletBinding()]
param(
    [Alias('TenantUrl', 'URL')]
    [string]$Origin,

    [Alias('Key')]
    [string]$ApiKey
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$helperPath = Join-Path -Path $PSScriptRoot -ChildPath 'Invoke-GraphQlRequest.ps1'
$queryPath = Join-Path -Path $PSScriptRoot -ChildPath 'Config\graphql\get-ip-list.graphql'

$result = & $helperPath -Origin $Origin -ApiKey $ApiKey -QueryPath $queryPath -OperationName 'GetIpList'
$result.getIpList
