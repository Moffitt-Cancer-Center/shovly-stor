# Varonis Search API PowerShell Scripts

This directory contains standardized PowerShell scripts that run GraphQL queries against the Varonis Search API. Each script uses a shared template structure and common helper functions for maximum code reuse and maintainability.

## Architecture Overview

- **Shared Helper Module**: `VaronisApiHelpers.psm1` provides common functions for all scripts
- **Template-Based Scripts**: All scripts follow a consistent structure for easier maintenance
- **GraphQL Queries**: Each script corresponds to a `.gql` file in the `Gql` subdirectory
- **Automatic Results Management**: Results are saved with timestamps to the `Results` directory
- **Generic Query Support**: Helper functions support all query types (events, users, resources, physicalPermissions)

## Prerequisites

1. **Configuration**: Ensure `config.json` exists with your Varonis API settings
2. **Helper Module**: `VaronisApiHelpers.psm1` must be in the same directory
3. **GraphQL Files**: Corresponding `.gql` files must exist in the `Gql` subdirectory
4. **PowerShell**: PowerShell 5.1 or later
5. **Network Access**: Connectivity to your Varonis API endpoint

## Events Scripts

Query event data with date filtering. All events scripts require `-daysAgo` parameter.

```powershell
# Get alerted events from the last 7 days
.\Events-Get-AlertedEvents.ps1 -daysAgo 7

# Get alerted events from specific data sources
.\Events-Get-AlertedEvents.ps1 -daysAgo 7 -dataSourceIds "1,2,3"

# Get activity on sensitive data from the last 30 days
.\Events-Get-ActivityOnSensitiveData.ps1 -daysAgo 30

# Get activity on sensitive data from specific data source
.\Events-Get-ActivityOnSensitiveData.ps1 -daysAgo 14 -dataSourceIds "5"

# Get activity on data exposed to organization
.\Events-Get-ActivityOnDataExposedToOrganization.ps1 -daysAgo 14

# Get activity on data exposed to organization from specific data source
.\Events-Get-ActivityOnDataExposedToOrganization.ps1 -daysAgo 14 -dataSourceIds "1,5"
```

## Physical Permissions Scripts

Query permission data. Optional `-dataSourceIds` parameter for filtering specific data sources.

```powershell
# Get inconsistent (broken) permissions
.\PhysicalPermissions-Get-InconsistentPermissions.ps1
.\PhysicalPermissions-Get-InconsistentPermissions.ps1 -dataSourceIds "1"

# Get permissions on data exposed to the whole organization
.\PhysicalPermissions-Get-PermissionsOnDataExposedToOrganization.ps1
.\PhysicalPermissions-Get-PermissionsOnDataExposedToOrganization.ps1 -dataSourceIds "1,2"

# Get permissions on sensitive data
.\PhysicalPermissions-Get-PermissionsOnSensitiveData.ps1
.\PhysicalPermissions-Get-PermissionsOnSensitiveData.ps1 -dataSourceIds "1,2"

# Get permissions to unique sensitive folders
.\PhysicalPermissions-Get-PermissionsToUniqueSensitiveFolders.ps1
.\PhysicalPermissions-Get-PermissionsToUniqueSensitiveFolders.ps1 -dataSourceIds "1,2"
```

## Resources Scripts

Query resource metadata. Optional `-dataSourceIds` parameter for filtering specific data sources.

```powershell
# Get classified objects
.\Resources-Get-ClassifiedObjects.ps1
.\Resources-Get-ClassifiedObjects.ps1 -dataSourceIds "1"

# Get objects with broken permissions
.\Resources-Get-ObjectsWithBrokenPermissions.ps1
.\Resources-Get-ObjectsWithBrokenPermissions.ps1 -dataSourceIds "1"

# Get stale sensitive data
.\Resources-Get-StaleSensitiveData.ps1
.\Resources-Get-StaleSensitiveData.ps1 -dataSourceIds "1,2"
```

## Identities Scripts

Query user and identity information. No additional parameters required.

```powershell
# Get users with passwords that never expire
.\Identities-Get-UsersWithPasswordsNeverExpire.ps1

# Get non-organizational users (guest/external)
.\Identities-Get-NonOrgUsers.ps1

# Get enabled but stale users
.\Identities-Get-EnabledButStaleUsers.ps1
```


## Configuration

Ensure your `config.json` contains the required Varonis API settings:
```json
{
  "domain": "https://your-varonis-instance.com",
  "api_key": "your-api_key",
}
```

## Examples

### Basic Usage
```powershell
# Run a simple query
.\Events-Get-AlertedEvents.ps1 -daysAgo 7

# Query specific data sources
.\Resources-Get-ClassifiedObjects.ps1 -dataSourceIds "1,5,10"
```

### Batch Execution
```powershell
# Run multiple scripts in sequence
.\Events-Get-AlertedEvents.ps1 -daysAgo 30
.\Resources-Get-ClassifiedObjects.ps1
.\Identities-Get-EnabledButStaleUsers.ps1
```
