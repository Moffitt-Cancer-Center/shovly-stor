<!--
Varonis' sample code(s) are provided on an "as is" and "as available" basis and without any warranty of any kind.  
Any use of Varonis' sample code(s) is optional at client's sole discretion, responsibility and risk.
Varonis does not make any commitment with respect to Varonis' sample code(s), their specific functions or their availability, reliability, or ability to meet client's needs.
Client acknowledges that Varonis may, in its sole discretion, modify, discontinue or update the Varonis' sample code(s) from time to time, without notice and for any reason.
-->

# Varonis DAG API Samples

This repository contains sample code for interacting with the Varonis Data Analytics Gateway (DAG) API. The samples are provided in both Python and PowerShell, demonstrating common operations such as querying data, managing requests, and working with permissions.

## Repository Structure

```
src/
├── Config/
│   ├── config.json              # Configuration file for API settings
│   └── graphql/                 # GraphQL query definitions
├── Python/
│   ├── Modules/                 # Reusable Python modules
│   └── Samples/                 # Python sample scripts
│       └── Replace Owner/       # Owner replacement utilities
└── PowerShell/
    ├── Config/Modules/          # PowerShell modules
    └── Samples/                 # PowerShell sample scripts
```

## Getting Started

### Python Samples

#### Prerequisites
- Python 3.6 or higher
- Required Python packages:
  ```bash
  pip install requests
  ```

#### Configuration
1. **Option 1:** Configure `Config/config.json` with your tenant URL and API key
2. **Option 2:** Provide credentials via command-line arguments
3. **Option 3:** Use interactive prompts (default behavior)

#### Available Python Scripts

##### Query Scripts

###### **getDAGquery.py** (Query Scripts/)
Executes DAG queries to retrieve governed resources and groups.
```bash
python getDAGquery.py
```

##### Request Management Scripts

###### **cancelRequest.py** (Request Scripts/)
Cancels a pending request in the Varonis system.
```bash
python cancelRequest.py
```

###### **getRequests.py** (Request Scripts/)
Retrieves and filters requests with various criteria.
```bash
python getRequests.py
```

###### **cloneRequests.py** (Request Scripts/)
Clones existing requests for bulk operations.
```bash
python cloneRequests.py
```

###### **membershipRequest.py** (Request Scripts/)
Submits group membership requests (grant or revoke).

**Interactive Mode:**
```bash
python membershipRequest.py
```

**Command-Line Mode:**
```bash
python membershipRequest.py <tenant_url> <api_key> --group "domain\groupname" --user "domain\username" --action "grant|revoke" --reason "justification" [optional_parameters]
```

**Command-Line Parameters:**
- `--group` - Group in format "domain\\accountname" (required)
- `--user` - User in format "domain\\accountname" (required)
- `--action` - Access action: "grant" or "revoke" (required)
- `--reason` - Reason for the request (required)
- `--auto-approve` - Auto-approve the request (optional flag)
- `--expiration-date` - Expiration date in YYYY-MM-DDTHH:MM:SS or DD/MM/YYYY format (optional)
- `--activation-date` - Activation date in YYYY-MM-DDTHH:MM:SS or DD/MM/YYYY format (optional)
- `--expiration-days` - Expiration days interval as positive integer (optional)

**Examples:**
```bash
# Basic membership grant request
python membershipRequest.py "https://yourtenant.varonis.io" "your_api_key" --group "domain\\groupname" --user "domain\\username" --action "grant" --reason "Business justification"

# Grant membership with 30-day expiration
python membershipRequest.py "https://yourtenant.varonis.io" "your_api_key" --group "domain\\groupname" --user "domain\\username" --action "grant" --reason "Temporary access needed" --expiration-days 30

# Revoke membership
python membershipRequest.py "https://yourtenant.varonis.io" "your_api_key" --group "domain\\groupname" --user "domain\\username" --action "revoke" --reason "Access no longer needed"
```

###### **permissionRequest.py** (Request Scripts/)
Submits permission requests for file system resources.

**Interactive Mode:**
```bash
python permissionRequest.py
```

**Command-Line Mode:**
```bash
python permissionRequest.py <tenant_url> <api_key> --resource-path "<folder_path>" --permission-type "<permission_type>" --user "domain\username" --action "grant|revoke" --reason "justification" [optional_parameters]
```

**Command-Line Parameters:**
- `--resource-path` - Display path of the resource/folder (required)
- `--permission-type` - Permission type like "Read", "Write", "Full Control" (required)
- `--user` - User in format "domain\\accountname" (required)
- `--action` - Access action: "grant" or "revoke" (required)
- `--reason` - Reason for the request (required)
- `--auto-approve` - Auto-approve the request (optional flag)
- `--expiration-date` - Expiration date in YYYY-MM-DDTHH:MM:SS or DD/MM/YYYY format (optional)
- `--activation-date` - Activation date in YYYY-MM-DDTHH:MM:SS or DD/MM/YYYY format (optional)
- `--expiration-days` - Expiration days interval as positive integer (optional)

**Examples:**
```bash
# Basic permission grant request
python permissionRequest.py "https://yourtenant.varonis.io" "your_api_key" --resource-path "\\server\\share\\folder" --permission-type "Read" --user "domain\\username" --action "grant" --reason "Need read access for project"

# Grant write permission with 15-day expiration
python permissionRequest.py "https://yourtenant.varonis.io" "your_api_key" --resource-path "\\server\\share\\folder" --permission-type "Write" --user "domain\\username" --action "grant" --reason "Temporary write access needed" --expiration-days 15

# Revoke existing permission
python permissionRequest.py "https://yourtenant.varonis.io" "your_api_key" --resource-path "\\server\\share\\folder" --permission-type "Write" --user "domain\\username" --action "revoke" --reason "Project completed, access no longer needed"
```

#### Owner Replace Scripts

Special utilities for bulk ownership changes:

##### **replaceOwner.py**
Replaces ownership of all folders and groups owned by a specified user.
```bash
python replaceOwner.py                           # Use config.json
python replaceOwner.py <tenant_url>              # Use config.json for API key
python replaceOwner.py <tenant_url> <api_key>    # Full command line
```

##### **rollbackOwner.py**
Reverses ownership changes using CSV audit trail from replaceOwner.py.
```bash
python rollbackOwner.py <csv_file>                                     # Use config.json
python rollbackOwner.py <csv_file> <tenant_url>                        # Use config.json for API key
python rollbackOwner.py <csv_file> <tenant_url> <api_key>              # Full command line
```

### PowerShell Samples

#### Prerequisites
- PowerShell 5.1 or higher
- Varonis tenant URL and API key

#### Available PowerShell Scripts

##### Query and Data Management Scripts

###### **getDAGDataQuery.ps1**
Executes DAG queries to retrieve various data types.
```powershell
.\getDAGDataQuery.ps1 -QueryType "RootResource|GovernedFolders|GovernedGroups"
```

###### **getDAGAutoRules.ps1**
Retrieves automatic authorization rules from the DAG system.
```powershell
.\getDAGAutoRules.ps1
```

###### **MergeGroups.ps1**
Merges multiple groups based on configuration.
```powershell
.\MergeGroups.ps1
```

##### Authorization Rule Management

###### **ReplaceAuthRuleAuthorizer.ps1**
Replaces authorizers in authorization rules.
```powershell
.\ReplaceAuthRuleAuthorizer.ps1
```

##### Request Management Scripts

###### **membershipRequest.ps1** (Request Scripts/)
Submits group membership requests.
```powershell
.\membershipRequest.ps1
```

###### **permissionRequest.ps1** (Request Scripts/)
Submits permission requests for file system resources.
```powershell
.\permissionRequest.ps1
```

## Language-Specific Scripts

The following scripts are **Python-only** (no PowerShell equivalent):
- **cloneRequests.py** - Clones existing requests for bulk operations
- **replaceOwner.py** - Replaces ownership of all folders and groups owned by a specified user
- **rollbackOwner.py** - Reverses ownership changes using CSV audit trail

The following scripts are **PowerShell-only** (no Python equivalent):
- **getDAGAutoRules.ps1** - Retrieves automatic authorization rules from the DAG system
- **MergeGroups.ps1** - Merges multiple groups based on configuration
- **ReplaceAuthRuleAuthorizer.ps1** - Replaces authorizers in authorization rules

The following scripts are available in **both Python and PowerShell**:
- **membershipRequest** - Group membership request automation
- **permissionRequest** - File system permission request automation
- **getDAGquery/getDAGDataQuery** - Query DAG for governed resources and groups

## Python Modules Documentation

### Core Modules (Python/Modules/)

#### **authentication.py**
Handles API authentication with the Varonis SaaS platform.
- `Authenticate(tenanturl, apikey)` - Authenticates using API key and returns access token

#### **graphQLclient.py**
Provides a GraphQL client for executing queries and mutations.
- Supports both standard API and DAG API endpoints
- Automatic token refresh on authentication failure
- Error handling and logging

#### **tenantinfo.py**
Handles tenant URL and API key validation and input.
- `getTenantInfo()` - Prompts for tenant URL
- `validateTenantURl(tenanturl)` - Validates tenant URL format
- `getAPIKey()` - Prompts for API key
- `validateAPIKey(apikey)` - Validates API key format

#### **logger.py**
Provides centralized logging functionality.
- Rotating file handlers
- Automatic log directory creation
- Timestamped log files named after the main script

#### **checkDAGjob.py**
Monitors the status of asynchronous DAG jobs.
- `checkStatus(vars, client, CheckQueryType, AsyncResultType)` - Polls job status until completion

#### **graphQLhelpers.py**
Utility functions for GraphQL operations.
- `getQueryFile(queryType, graphqlfolder)` - Loads GraphQL query files
- `checkMutation(jobId, client, graphqlfolder)` - Monitors mutation job completion

## Authentication Requirements

All scripts require:
1. **Tenant URL** - Your Varonis SaaS tenant URL (format: `https://yourtenant.varonis.io`)
2. **API Key** - A valid Varonis API key with appropriate permissions

### Configuration Options

#### Option 1: Configuration File
Edit `Config/config.json`:
```json
{
    "tenant_url": "https://yourtenant.varonis.io",
    "api_key": "your_api_key_here"
}
```

#### Option 2: Command-Line Arguments
Many scripts support passing credentials as arguments:
```bash
python script.py "https://yourtenant.varonis.io" "your_api_key"
```

#### Option 3: Interactive Prompts
Run scripts without arguments to be prompted for credentials:
```bash
python script.py
```

## Request Types and Statuses

### Supported Request Types
- `DIRECT_PERMISSION` - Direct permission requests
- `ENTITLEMENT_REVIEW` - Entitlement review requests
- `FOLDER_CREATION` - Folder creation requests
- `MEMBERSHIP` - Group membership requests
- `PERMISSION` - Permission requests

### Supported Request Statuses
- `APPROVED`, `CANCELED`, `DECLINED`, `ERROR`, `EXECUTING`, `EXPIRED`, `PARTIAL`, `PENDING`, `PENDING_ACTIVATION`, `SIGNED`, `SUB_REQ`

## Logging and Output

### Logging
- All scripts generate detailed logs in the `Python/Logs/` directory
- Log files are named after the executing script with timestamp
- Logs include debug information, API calls, and error details
- Log files use rotating handlers to prevent excessive disk usage

### Output Format
Most scripts output results in formatted JSON for easy parsing and integration with other tools.

## Security Notes

- **Never hardcode API keys or tenant URLs in scripts**
- API keys are validated but not stored permanently
- SSL verification is disabled for development (consider enabling in production)
- All authentication tokens are managed automatically and not exposed in logs
- Follow your organization's security policies for API key management

## Troubleshooting

### Common Issues

#### Authentication Failures
- Verify tenant URL format: `https://yourtenant.varonis.io`
- Ensure API key is valid and has necessary permissions
- Check network connectivity to the tenant

#### Module Import Errors
- Ensure you're running scripts from the correct directory
- Verify the `Modules/` directory exists and contains required files
- Check that all required dependencies are installed

#### GraphQL Query Errors
- Verify `.graphql` files exist in the `Config/graphql/` directory
- Check that the API key has permissions for the requested operations
- Review log files for detailed error information

### Debug Mode
Enable debug logging by reviewing the detailed log files generated in the `Python/Logs/` directory.

## Recent Updates

### Enhanced Command-Line Interface (September 2025)

**Updated Scripts:**
- **membershipRequest.py** - Group membership request automation
- **permissionRequest.py** - File system permission request automation

**New Features:**
- **Command-Line Interface:** Added comprehensive command-line argument support for automated workflows
- **Dual Operation Modes:** Interactive mode for manual use, command-line mode for scripting and automation
- **Enhanced Date Parsing:** Flexible date format support (ISO 8601 and DD/MM/YYYY)
- **Smart Parameter Handling:** Automatic detection of command-line vs interactive mode
- **Improved Validation:** Better error handling and input validation

**Benefits:**
- **Automation-Ready:** Can be integrated into scripts and CI/CD pipelines
- **Reduced Manual Input:** No interactive prompts when all required parameters are provided
- **Backward Compatibility:** Existing interactive workflows remain unchanged
- **Flexible Usage:** Choose between interactive prompts or command-line efficiency based on use case

## Usage Patterns

### For Automation/Scripting
```bash
# Membership request
python membershipRequest.py "https://tenant.varonis.io" "api_key" --group "domain\\group" --user "domain\\user" --action "grant" --reason "justification"

# Permission request  
python permissionRequest.py "https://tenant.varonis.io" "api_key" --resource-path "\\server\\share" --permission-type "Read" --user "domain\\user" --action "grant" --reason "justification"
```

### For Interactive Use
```bash
# Both scripts still support interactive mode
python membershipRequest.py
python permissionRequest.py
```

## Support

For questions or issues with these samples, please refer to the Varonis documentation or contact your Varonis administrator.