# Varonis' sample code(s) are provided on an "as is" and "as available" basis and without any warranty of any kind.  
# Any use of Varonis' sample code(s) is optional at client's sole discretion, responsibility and risk.
# Varonis does not make any commitment with respect to Varonis' sample code(s), their specific functions or their availability, reliability, or ability to meet client's needs.
# Client acknowledges that Varonis may, in its sole discretion, modify, discontinue or update the Varonis' sample code(s) from time to time, without notice and for any reason.

<#
.SYNOPSIS
Configuration module for reading tenant and API settings from config.json

.DESCRIPTION
This module provides functions to read configuration from a centralized config.json file
located in the Config directory. It handles loading, validation, and provides access
to tenant URL, API key, and other settings.

.NOTES
Author: Generated for Varonis DAG API Samples
Date: September 2025
#>

# Global variable to store configuration data
$script:ConfigData = $null
$script:ConfigPath = $null

function Initialize-ConfigPath {
    <#
    .SYNOPSIS
    Initialize the path to the config.json file
    #>
    
    # Get the path relative to this module's location
    # Module is in: src\PowerShell\Config\Modules\config_manager.psm1
    # Config is in: src\Config\config.json
    $ModuleDir = Split-Path -Parent $PSCommandPath
    # Go up from Modules to Config, then to PowerShell, then to src, then to Config
    $SrcDir = Split-Path (Split-Path (Split-Path $ModuleDir -Parent) -Parent) -Parent
    $script:ConfigPath = Join-Path $SrcDir "Config\config.json"
    
    Write-Debug "Configuration path set to: $script:ConfigPath"
}

function Import-Configuration {
    <#
    .SYNOPSIS
    Import configuration from config.json file
    
    .DESCRIPTION
    Imports and parses the JSON configuration file. Validates that the file exists
    and contains valid JSON data.
    
    .EXAMPLE
    Import-Configuration
    #>
    
    try {
        if (-not $script:ConfigPath) {
            Initialize-ConfigPath
        }
        
        if (-not (Test-Path $script:ConfigPath)) {
            $ErrorMessage = "Configuration file not found: $script:ConfigPath"
            Write-Error $ErrorMessage
            Write-Error "Please create config.json from config.template.json and update with your values"
            throw $ErrorMessage
        }
        
        $ConfigContent = Get-Content -Path $script:ConfigPath -Raw -Encoding UTF8
        $script:ConfigData = $ConfigContent | ConvertFrom-Json
        
        Write-Debug "Configuration loaded successfully from: $script:ConfigPath"
        
    } catch {
        Write-Error "Error loading configuration: $($_.Exception.Message)"
        throw
    }
}

function Get-TenantUrl {
    <#
    .SYNOPSIS
    Get tenant URL from configuration
    
    .DESCRIPTION
    Retrieves the tenant URL from the loaded configuration. Validates that
    the URL has been properly configured (not the default template value).
    
    .OUTPUTS
    String - The configured tenant URL
    
    .EXAMPLE
    $tenantUrl = Get-TenantUrl
    #>
    
    if (-not $script:ConfigData) {
        Import-Configuration
    }
    
    $url = $script:ConfigData.tenant.url
    
    if (-not $url -or $url -eq "https://your-tenant.varonis.io") {
        $ErrorMessage = "Tenant URL not configured. Please update config.json with your actual tenant URL"
        Write-Error $ErrorMessage
        throw $ErrorMessage
    }
    
    Write-Debug "Tenant URL retrieved from configuration"
    return $url
}

function Get-ApiKey {
    <#
    .SYNOPSIS
    Get API key from configuration
    
    .DESCRIPTION
    Retrieves the API key from the loaded configuration. Validates that
    the API key has been properly configured (not the default template value).
    
    .OUTPUTS
    String - The configured API key
    
    .EXAMPLE
    $apiKey = Get-ApiKey
    #>
    
    if (-not $script:ConfigData) {
        Import-Configuration
    }
    
    $apiKey = $script:ConfigData.tenant.apiKey
    
    if (-not $apiKey -or $apiKey -eq "your-api-key-here") {
        $ErrorMessage = "API key not configured. Please update config.json with your actual API key"
        Write-Error $ErrorMessage
        throw $ErrorMessage
    }
    
    Write-Debug "API key retrieved from configuration"
    return $apiKey
}

function Get-ConfigSetting {
    <#
    .SYNOPSIS
    Get a setting value from configuration
    
    .DESCRIPTION
    This function is deprecated. The config file now only contains tenant URL and API key.
    
    .PARAMETER SettingName
    The name of the setting to retrieve
    
    .PARAMETER DefaultValue
    The default value to return
    
    .OUTPUTS
    Object - The default value (settings section removed)
    
    .EXAMPLE
    $timeout = Get-ConfigSetting -SettingName "timeout" -DefaultValue 30
    #>
    
    param(
        [Parameter(Mandatory = $true)]
        [string]$SettingName,
        
        [Parameter(Mandatory = $false)]
        [object]$DefaultValue = $null
    )
    
    Write-Warning "Settings functionality removed. Config file now only contains tenant URL and API key. Returning default value."
    return $DefaultValue
}

function Test-Configuration {
    <#
    .SYNOPSIS
    Test if configuration is properly set up
    
    .DESCRIPTION
    Validates that the configuration file exists, is valid JSON,
    and contains properly configured tenant URL and API key.
    
    .OUTPUTS
    Boolean - True if configuration is valid, False otherwise
    
    .EXAMPLE
    if (Test-Configuration) {
        Write-Host "Configuration is valid"
    }
    #>
    
    try {
        if (-not $script:ConfigPath) {
            Initialize-ConfigPath
        }
        
        if (-not (Test-Path $script:ConfigPath)) {
            Write-Warning "Configuration file not found: $script:ConfigPath"
            return $false
        }
        
        Import-Configuration
        
        $url = $script:ConfigData.tenant.url
        $apiKey = $script:ConfigData.tenant.apiKey
        
        if (-not $url -or $url -eq "https://your-tenant.varonis.io") {
            Write-Warning "Tenant URL not properly configured"
            return $false
        }
        
        if (-not $apiKey -or $apiKey -eq "your-api-key-here") {
            Write-Warning "API key not properly configured"
            return $false
        }
        
        return $true
        
    } catch {
        Write-Warning "Configuration validation failed: $($_.Exception.Message)"
        return $false
    }
}

function Update-Configuration {
    <#
    .SYNOPSIS
    Update configuration from file
    
    .DESCRIPTION
    Forces an update of the configuration from the config.json file.
    Useful when the configuration file has been updated.
    
    .EXAMPLE
    Update-Configuration
    #>
    
    Write-Host "Updating configuration..."
    $script:ConfigData = $null
    Import-Configuration
}

# Initialize the configuration path when the module is loaded
Initialize-ConfigPath

# Export functions
Export-ModuleMember -Function Get-TenantUrl, Get-ApiKey, Test-Configuration, Update-Configuration
