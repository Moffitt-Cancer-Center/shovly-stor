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
$queryPath = Join-Path -Path $PSScriptRoot -ChildPath 'Config\graphql\manage-ip-list.graphql'
$variables = @{
    input = @{
        action = 'CLEAR'
    }
}

$result = & $helperPath -Origin $Origin -ApiKey $ApiKey -QueryPath $queryPath -OperationName 'ManageIpList' -Variables $variables
$result.manageIpList
