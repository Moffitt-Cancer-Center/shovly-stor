# Sample PowerShell Scripts for IP List GraphQL API

This package contains reusable PowerShell scripts for the GraphQL schema you provided.

## Files

- `Config\config.json` - configuration file for tenant URL and API key.
- `Config\graphql\*.graphql` - GraphQL operation documents.
- `Invoke-GraphQlRequest.ps1` - reusable helper for authentication and GraphQL requests.
- `Get-IpList.ps1` - reads the current configured IP list.
- `Add-IpListEntries.ps1` - adds one or more IP addresses or CIDR blocks.
- `Remove-IpListEntries.ps1` - removes one or more IP addresses or CIDR blocks.
- `Replace-IpList.ps1` - replaces the entire list.
- `Clear-IpList.ps1` - clears the entire list.
- `variables\*.json` - sample variables payloads.

## Prerequisites

- Windows PowerShell 5.1 or PowerShell 7+
- A Varonis tenant URL and an API key with the `Enterprise Manager` role

## Quick start

1. **Unblock the scripts.** Windows marks downloaded scripts as untrusted. Run this once from the folder before using any script:

```powershell
Get-ChildItem -Filter '*.ps1' | Unblock-File
```

2. Open `Config\config.json` and update it with your values:

```json
{
  "tenant": {
    "url": "https://tenant.varonis.io",
    "apiKey": "api_key"
  }
}
```

3. Run a script. The scripts will use `Config\config.json` by default, or you can override with `-Origin` and `-ApiKey`.

4. Read the current IP list:

```powershell
.\Get-IpList.ps1
```

5. Add entries:

```powershell
.\Add-IpListEntries.ps1 -IpAddresses '203.0.113.0/24','198.51.100.50'
```

6. Remove entries:

```powershell
.\Remove-IpListEntries.ps1 -IpAddresses '198.51.100.50'
```

7. Replace the list:

```powershell
.\Replace-IpList.ps1 -IpAddresses '203.0.113.0/24','198.51.100.50'
```

8. Clear the list:

```powershell
.\Clear-IpList.ps1
```

## Notes

- The scripts exchange the API key for a bearer token at `/api/authentication/api_keys/token`, then call GraphQL at `/api/roles/graphql/ip_ranges`.
- If `Config\config.json` is not configured, the scripts will prompt for the missing values.
- The schema defines `ipAddresses` as strings, so the scripts accept three formats: plain IPv4 addresses (e.g., 192.168.1.1), CIDR notation (e.g., 203.0.113.0/24), and ranges (e.g., 192.168.1.1-192.168.1.10).
