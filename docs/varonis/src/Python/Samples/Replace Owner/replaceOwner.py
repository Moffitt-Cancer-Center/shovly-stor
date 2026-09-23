# Varonis' sample code(s) are provided on an "as is" and "as available" basis and without any warranty of any kind.  
# Any use of Varonis' sample code(s) is optional at client's sole discretion, responsibility and risk.
# Varonis does not make any commitment with respect to Varonis' sample code(s), their specific functions or their availability, reliability, or ability to meet client's needs.
# Client acknowledges that Varonis may, in its sole discretion, modify, discontinue or update the Varonis' sample code(s) from time to time, without notice and for any reason.

"""
DAG Ownership Replace Script

This script will replace ownership of all folders and groups owned by a specified user.

The script performs the following operations:
1. Read current owner and new owner input from user
2. Query DAG for any group or folder owned by the current owner
3. Create a log/parseable CSV of all the items owned 
4. Add new owner to all folders/groups
5. Remove old owner from groups/folders

Configuration:
- Tenant URL and API key can be provided via command line arguments OR
- Configured in src/Config/config.json file
- If both are available, command line arguments take precedence
- If neither are provided, the script will prompt for input

Usage:
    python replaceOwner.py                                    # Use config.json for tenant/API
    python replaceOwner.py <tenant_url>                       # Use config.json for API key
    python replaceOwner.py <tenant_url> <api_key>             # Use command line for both

Examples:
    python replaceOwner.py
    python replaceOwner.py https://tenant.varonis.io
    python replaceOwner.py https://tenant.varonis.io vkey1_abc123...
"""

import sys
import os 
import json
import csv 
import time
import argparse
from datetime import datetime

modules_path = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', 'Modules'))
sys.path.append(modules_path)

import tenantinfo
import authentication
import graphQLclient
import checkDAGjob
import config_manager
from logger import get_logger


log = get_logger(__name__)

graphqlfolder = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..', 'Config', 'graphql'))

def findOwnership (client, current_owner, resource_type):
    log.info(f'Searching for {resource_type}s owned by {current_owner}')
    domain, user = splitAccountInput(current_owner)
    
    # Add error handling for splitAccountInput
    if not domain or not user:
        log.error("Failed to parse account information")
        return None
    
    log.debug(f'Got back from account splitter domain of: {domain} and user of: {user}')
    
    # Set variables based on resource type
    if resource_type.lower() == "folder":
        async_query_file = 'async_getFolderbyOwner.graphql'
        async_response_key = "governedResourcesAsync"
        check_status_type = "CheckStatus_GoverenedResources"
        async_result_type = "governedResourcesQueryJob"
        result_query_file = 'result_getFolderbyOwner.graphql'
    elif resource_type.lower() == "group":
        # Group query definitions
        async_query_file = 'async_getGroupbyOwner.graphql'
        async_response_key = 'governedGroupsAsync'
        check_status_type = 'CheckStatus_GoverenedGroups'
        async_result_type = 'governedGroupsQueryJob'
        result_query_file = 'result_getGroupbyOwner.graphql'
    else:
        log.error(f"Invalid resource_type: {resource_type}. Must be 'folder' or 'group'")
        return None
    
    query_path = os.path.join(graphqlfolder, async_query_file)
    with open (query_path, 'r') as queryfile: 
        query = queryfile.read()
    vars = {"samAccountName":user,"directoryServices":domain}

    log.debug (f"Executing GraphQL query: \n{query}")
    log.debug (f"Passing Vars: \n{vars}")

    response = client.execute_query(query, vars)
    
    # Debug: Log the full response
    log.debug(json.dumps(response, indent=2))
    
    # Fix: Access the nested structure correctly
    if not response or async_response_key not in response:
        log.error(f"Invalid GraphQL response structure. Expected key: {async_response_key}")
        return None
    
    governed_resources = response[async_response_key]
    
    if "jobId" not in governed_resources:
        log.error(f"Response missing 'jobId'. Available keys: {list(governed_resources.keys())}")
        return None
    
    job_id = governed_resources["jobId"]
    vars = {'id': job_id}
    log.debug (f"Checking jobid: {job_id}")

    checkStatus = checkDAGjob.checkStatus(vars, client, check_status_type, async_result_type)
    log.info (checkStatus)

    if checkStatus == "FAILED":
        log.error(checkStatus)
        sys.exit(-1)
    else: 
        query_path = os.path.join(graphqlfolder, result_query_file)
    
        with open(query_path, 'r') as queryfile:
            query = queryfile.read()
        log.debug(f"GraphQL Query:\n{query}")
        log.debug(f"GraphQL Variables:\n{json.dumps(vars, indent=2)}")
        result = client.execute_query (query,vars)
        return json.dumps(result,indent=4)

def splitAccountInput(account):
    r"""
    Split domain\user format into separate domain and user components
    
    Args:
        account (str): Account in format 'domain.local\user'
    
    Returns:
        tuple: (domain, user) or (None, None) if invalid format
    """
    try:
        if '\\' in account:
            domain, user = account.split('\\', 1)  # Split only on first backslash
            return domain.strip(), user.strip()
        else:
            log.warning(f"Invalid account format: {account}. Expected format: domain.local\\user")
            return None, None
    except ValueError:
        log.error(f"Failed to parse account: {account}")
        return None, None

def combineAccountOutput(domain, user):
    r"""
    Combine domain and user into domain\user format
    
    Args:
        domain (str): Domain name (e.g., 'domain.local')
        user (str): Username (e.g., 'username')
    
    Returns:
        str: Combined account in format 'domain\user'
    """
    return f"{domain}\\{user}"

def get_user_inputs():
    """Get current owner and new owner from user input"""
    current_owner = input("Enter the current owner to replace: ")
    new_owner = input("Enter the new owner: ")
    
    # Optional: Add validation
    if not current_owner.strip() or not new_owner.strip():
        log.error("Error: Both owners must be provided")
        return None, None
    
    return current_owner.strip(), new_owner.strip()

def getSuccessfulResources(operation_results):
    """
    Extract list of resources that completed successfully from operation results
    
    Args:
        operation_results: Dict containing job results with details
    
    Returns:
        List of resource paths/names that completed successfully
    """
    successful_resources = []
    
    if not operation_results or "details" not in operation_results:
        return successful_resources
    
    for detail in operation_results["details"]:
        if detail.get("status") == "COMPLETED":
            resource = detail.get("resource")
            if resource:
                successful_resources.append(resource)
                log.debug(f"Resource marked for next operation: {resource}")
    
    log.info(f"Found {len(successful_resources)} resources with successful operations")
    return successful_resources

def updateLogFileStatus(log_filename, operation_results, operation_type="add_owner"):
    """
    Update the CSV log file with operation results
    
    Args:
        log_filename: Path to the CSV log file
        operation_results: Dict containing job results with resource names and statuses
        operation_type: "add_owner" or "remove_owner"
    """
    if not log_filename or not operation_results:
        log.warning("No log file or results to update")
        return
    
    try:
        log.debug(f"Updating CSV file '{log_filename}' with {operation_type} results")
        log.debug(f"Operation results summary: {operation_results.get('successful', 0)} successful, {operation_results.get('failed', 0)} failed")
        log.debug(f"Details count: {len(operation_results.get('details', []))}")
        
        # Read the current CSV data
        rows = []
        with open(log_filename, 'r', newline='', encoding='utf-8') as csvfile:
            reader = csv.reader(csvfile)
            rows = list(reader)
        
        log.debug(f"Read {len(rows)} rows from CSV file")
        
        # Determine which columns to update based on operation type
        if operation_type == "add_owner":
            status_col = 4  # Add Owner Status column
            job_id_col = 5  # Add Owner Job ID column
        elif operation_type == "remove_owner":
            status_col = 6  # Remove Owner Status column  
            job_id_col = 7  # Remove Owner Job ID column
        else:
            log.error(f"Invalid operation_type: {operation_type}")
            return
        
        # Update rows with results
        updates_made = 0
        for i, row in enumerate(rows):
            if i == 0:  # Skip header row
                continue
                
            if len(row) < 2:  # Skip malformed rows
                continue
                
            resource_path = row[1].strip()  # Resource Path/Name column
            log.debug(f"Processing CSV row {i}: resource='{resource_path}'")
            
            # Find matching result for this resource
            for result in operation_results.get("details", []):
                result_resource = result.get("resource", "").strip()
                log.debug(f"Comparing CSV resource '{resource_path}' with result resource '{result_resource}'")
                
                if result_resource == resource_path:
                    # Update status and job ID
                    if len(row) > status_col:
                        old_status = row[status_col]
                        row[status_col] = result.get("status", "Unknown")
                        log.debug(f"Updated status from '{old_status}' to '{row[status_col]}' for {resource_path}")
                    if len(row) > job_id_col:
                        old_job_id = row[job_id_col] 
                        row[job_id_col] = result.get("job_id", "")
                        log.debug(f"Updated job ID from '{old_job_id}' to '{row[job_id_col]}' for {resource_path}")
                    
                    updates_made += 1
                    break
            else:
                # No matching result found, mark as not processed for this operation only
                if len(row) > status_col:
                    if row[status_col] == "Pending" or row[status_col] == "":
                        row[status_col] = "Not Processed"
                        log.debug(f"Marked as 'Not Processed' for {resource_path} (no matching result)")
        
        log.info(f"Made {updates_made} updates to CSV file for {operation_type}")
        
        # Write back to CSV
        with open(log_filename, 'w', newline='', encoding='utf-8') as csvfile:
            writer = csv.writer(csvfile)
            writer.writerows(rows)
        
        log.info(f"Updated log file with {operation_type} results: {log_filename}")
        
    except Exception as e:
        log.error(f"Failed to update log file: {e}")
        import traceback
        log.error(f"Full traceback: {traceback.format_exc()}")

def makeLogFile(folders, groups, current_owner, new_owner):
    """Create a CSV log file of owned resources with status tracking columns"""
    
    # Create filename: old_owner_<input>_<currentdateandtime>
    # Replace backslash in owner name with underscore for valid filename
    safe_owner = current_owner.replace('\\', '_').replace('/', '_')
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    fileName = f"old_owner_{safe_owner}_{timestamp}.csv"
    
    log.info(f"Creating log file: {fileName}")
    
    try:
        with open(fileName, 'w', newline='', encoding='utf-8') as csvfile:
            writer = csv.writer(csvfile)
            
            # Write headers with status tracking columns
            writer.writerow([
                'Resource Type', 
                'Resource Path/Name', 
                'Current Owner', 
                'New Owner',
                'Add Owner Status',
                'Add Owner Job ID',
                'Remove Owner Status', 
                'Remove Owner Job ID'
            ])
            
            # Write folder data with initial status as "Pending"
            for folder in folders:
                writer.writerow([
                    'Folder', 
                    folder, 
                    current_owner, 
                    new_owner,
                    'Pending',
                    '',
                    'Pending',
                    ''
                ])
            
            # Write group data with initial status as "Pending"
            for group in groups:
                writer.writerow([
                    'Group', 
                    group, 
                    current_owner, 
                    new_owner,
                    'Pending',
                    '',
                    'Pending',
                    ''
                ])
        
        log.info(f"Log file created successfully: {fileName}")
        return fileName
        
    except Exception as e:
        log.error(f"Failed to create log file: {e}")
        return None
    
def addNewOwner(client, entities, entity_type, new_owner):
    r"""
    Add new owner to folders or groups
    
    Args:
        client: GraphQL client
        entities: List of folder paths or group names
        entity_type: 'folder' or 'group'
        new_owner: New owner in format 'domain\user'
    
    Returns:
        List of job results with job IDs and resource info for tracking async operations
    """
    log.info(f"Starting to add new owner '{new_owner}' to {len(entities)} {entity_type}s")
    
    # Parse the new owner
    new_owner_domain, new_owner_user = splitAccountInput(new_owner)
    if not new_owner_domain or not new_owner_user:
        log.error("Failed to parse new owner information")
        return []
    
    job_results = []
    
    for entity in entities:
        try:
            if entity_type.lower() == "folder":
                job_id = addFolderOwner(client, entity, new_owner_user, new_owner_domain)
            elif entity_type.lower() == "group":
                job_id = addGroupOwner(client, entity, new_owner_user, new_owner_domain)
            else:
                log.error(f"Invalid entity_type: {entity_type}")
                continue
                
            if job_id:
                job_results.append({
                    "job_id": job_id,
                    "resource": entity,
                    "entity_type": entity_type
                })
                log.info(f"Successfully submitted {entity_type} owner addition for: {entity} (Job ID: {job_id})")
            else:
                log.error(f"Failed to submit {entity_type} owner addition for: {entity}")
                # Still add to results to track the failure
                job_results.append({
                    "job_id": None,
                    "resource": entity,
                    "entity_type": entity_type,
                    "status": "FAILED_TO_SUBMIT"
                })
                
        except Exception as e:
            log.error(f"Error adding owner to {entity_type} '{entity}': {e}")
            job_results.append({
                "job_id": None,
                "resource": entity,
                "entity_type": entity_type,
                "status": "ERROR",
                "error": str(e)
            })
    
    successful_submissions = len([r for r in job_results if r["job_id"] is not None])
    log.info(f"Submitted {successful_submissions} {entity_type} owner addition jobs")
    return job_results

def addFolderOwner(client, folder_path, owner_name, owner_domain):
    """
    Add owner to a specific folder using GraphQL
    
    Args:
        client: GraphQL client
        folder_path: Full path to the folder
        owner_name: Username (samAccountName)
        owner_domain: Domain name
    
    Returns:
        Job ID if successful, None if failed
    """
    try:
        # Load the GraphQL query
        query_path = os.path.join(graphqlfolder, 'async_addFolderOwner.graphql')
        with open(query_path, 'r') as queryfile:
            query = queryfile.read()
        
        # Set up variables matching PowerShell pattern
        vars = {
            "displayPath": folder_path,
            "ownerName": owner_name,
            "ownerDomain": owner_domain
        }
        
        log.debug(f"Adding folder owner - Path: {folder_path}, Owner: {owner_domain}\\{owner_name}")
        log.debug(f"GraphQL Query:\n{query}")
        log.debug(f"GraphQL variables:\n {json.dumps(vars, indent=2)}")
        
        # Execute the query
        response = client.execute_query(query, vars)
        
        # Extract job ID from response - now use raw job ID (no prefix)
        if response and "addGovernedResourceOwnersAsync" in response:
            job_id = response["addGovernedResourceOwnersAsync"].get("jobId")
            if job_id:
                log.debug(f"Folder owner addition job submitted: {job_id}")
                return job_id

        log.error(f"No job ID returned for folder: {folder_path}")
        log.debug(f"Full response: {json.dumps(response, indent=2)}")
        return None
        
    except Exception as e:
        log.error(f"Error in addFolderOwner for {folder_path}: {e}")
        return None

def addGroupOwner(client, group_account, owner_name, owner_domain):
    r"""
    Add owner to a specific group using GraphQL
    
    Args:
        client: GraphQL client
        group_account: Group in format 'domain\groupname'
        owner_name: Username (samAccountName)
        owner_domain: Domain name
    
    Returns:
        Job ID if successful, None if failed
    """
    try:
        # Parse the group account to get domain and group name
        group_domain, group_name = splitAccountInput(group_account)
        if not group_domain or not group_name:
            log.error(f"Failed to parse group account: {group_account}")
            return None
        
        # Load the GraphQL query
        query_path = os.path.join(graphqlfolder, 'async_addGroupOwner.graphql')
        with open(query_path, 'r') as queryfile:
            query = queryfile.read()
        
        # Set up variables matching PowerShell pattern
        vars = {
            "groupName": group_name,
            "groupDomain": group_domain,
            "ownerName": owner_name,
            "ownerDomain": owner_domain
        }
        
        log.debug(f"Adding group owner - Group: {group_domain}\\{group_name}, Owner: {owner_domain}\\{owner_name}")
        log.debug(f"GraphQL Query:\n{query}")
        log.debug(f"GraphQL variables: {json.dumps(vars, indent=2)}")
        
        # Execute the query
        response = client.execute_query(query, vars)
        
        # Extract job ID from response - now use raw job ID (no prefix)
        if response and "addGovernedGroupOwnersAsync" in response:
            job_id = response["addGovernedGroupOwnersAsync"].get("jobId")
            if job_id:
                log.debug(f"Group owner addition job submitted: {job_id}")
                return job_id

        log.error(f"No job ID returned for group: {group_account}")
        log.debug(f"Full response: {json.dumps(response, indent=2)}")
        return None
        
    except Exception as e:
        log.error(f"Error in addGroupOwner for {group_account}: {e}")
        return None

def removeFolderOwner(client, folder_path, owner_name, owner_domain):
    """
    Remove owner from a specific folder using GraphQL
    
    Args:
        client: GraphQL client
        folder_path: Full path to the folder
        owner_name: Username (samAccountName)
        owner_domain: Domain name
    
    Returns:
        Job ID if successful, None if failed
    """
    try:
        # Load the GraphQL query
        query_path = os.path.join(graphqlfolder, 'async_removeFolderOwner.graphql')
        with open(query_path, 'r') as queryfile:
            query = queryfile.read()
        
        # Set up variables matching the add owner pattern
        vars = {
            "displayPath": folder_path,
            "ownerName": owner_name,
            "ownerDomain": owner_domain
        }
        
        log.debug(f"Removing folder owner - Path: {folder_path}, Owner: {owner_domain}\\{owner_name}")
        log.debug(f"GraphQL Query:\n{query}")
        log.debug(f"GraphQL variables: {json.dumps(vars, indent=2)}")
        
        # Execute the query
        response = client.execute_query(query, vars)
        
        # Extract job ID from response - now use raw job ID (no prefix)
        if response and "removeGovernedResourceOwnersAsync" in response:
            job_id = response["removeGovernedResourceOwnersAsync"].get("jobId")
            if job_id:
                log.debug(f"Folder owner removal job submitted: {job_id}")
                return job_id
        
        log.error(f"No job ID returned for folder: {folder_path}")
        log.debug(f"Full response: {json.dumps(response, indent=2)}")
        return None
        
    except Exception as e:
        log.error(f"Error in removeFolderOwner for {folder_path}: {e}")
        return None

def removeGroupOwner(client, group_account, owner_name, owner_domain):
    r"""
    Remove owner from a specific group using GraphQL
    
    Args:
        client: GraphQL client
        group_account: Group in format 'domain\groupname'
        owner_name: Username (samAccountName)
        owner_domain: Domain name
    
    Returns:
        Job ID if successful, None if failed
    """
    try:
        # Parse the group account to get domain and group name
        group_domain, group_name = splitAccountInput(group_account)
        if not group_domain or not group_name:
            log.error(f"Failed to parse group account: {group_account}")
            return None
        
        # Load the GraphQL query
        query_path = os.path.join(graphqlfolder, 'async_removeGroupOwner.graphql')
        with open(query_path, 'r') as queryfile:
            query = queryfile.read()
        
        # Set up variables matching the add owner pattern
        vars = {
            "groupName": group_name,
            "groupDomain": group_domain,
            "ownerName": owner_name,
            "ownerDomain": owner_domain
        }
        
        log.debug(f"Removing group owner - Group: {group_domain}\\{group_name}, Owner: {owner_domain}\\{owner_name}")
        log.debug(f"GraphQL Query:\n{query}")
        log.debug(f"GraphQL variables: {json.dumps(vars, indent=2)}")
        
        # Execute the query
        response = client.execute_query(query, vars)
        
        # Extract job ID from response - now use raw job ID (no prefix)
        if response and "removeGovernedGroupOwnersAsync" in response:
            job_id = response["removeGovernedGroupOwnersAsync"].get("jobId")
            if job_id:
                log.debug(f"Group owner removal job submitted: {job_id}")
                return job_id
        
        log.error(f"No job ID returned for group: {group_account}")
        log.debug(f"Full response: {json.dumps(response, indent=2)}")
        return None
        
    except Exception as e:
        log.error(f"Error in removeGroupOwner for {group_account}: {e}")
        return None

def removeOldOwner(client, entities, entity_type, old_owner):
    r"""
    Remove old owner from folders or groups
    
    Args:
        client: GraphQL client
        entities: List of folder paths or group names
        entity_type: 'folder' or 'group'
        old_owner: Old owner in format 'domain\user'
    
    Returns:
        List of job results with job IDs and resource info for tracking async operations
    """
    log.info(f"Starting to remove old owner '{old_owner}' from {len(entities)} {entity_type}s")
    
    # Parse the old owner
    old_owner_domain, old_owner_user = splitAccountInput(old_owner)
    if not old_owner_domain or not old_owner_user:
        log.error("Failed to parse old owner information")
        return []
    
    job_results = []
    
    for entity in entities:
        try:
            if entity_type.lower() == "folder":
                job_id = removeFolderOwner(client, entity, old_owner_user, old_owner_domain)
            elif entity_type.lower() == "group":
                job_id = removeGroupOwner(client, entity, old_owner_user, old_owner_domain)
            else:
                log.error(f"Invalid entity_type: {entity_type}")
                continue
                
            if job_id:
                job_results.append({
                    "job_id": job_id,
                    "resource": entity,
                    "entity_type": entity_type
                })
                log.info(f"Successfully submitted {entity_type} owner removal for: {entity} (Job ID: {job_id})")
            else:
                log.error(f"Failed to submit {entity_type} owner removal for: {entity}")
                # Still add to results to track the failure
                job_results.append({
                    "job_id": None,
                    "resource": entity,
                    "entity_type": entity_type,
                    "status": "FAILED_TO_SUBMIT"
                })
                
        except Exception as e:
            log.error(f"Error removing owner from {entity_type} '{entity}': {e}")
            job_results.append({
                "job_id": None,
                "resource": entity,
                "entity_type": entity_type,
                "status": "ERROR",
                "error": str(e)
            })
    
    successful_submissions = len([r for r in job_results if r["job_id"] is not None])
    log.info(f"Submitted {successful_submissions} {entity_type} owner removal jobs")
    return job_results

def checkJobStatusAndResults(vars, client, CheckStatusType, AsyncResultType):
    """
    Enhanced job status checking that also examines job results for actual success/failure
    
    Args:
        vars: Variables for the GraphQL query (typically contains job ID)
        client: GraphQL client
        CheckStatusType: Type of status check query to use
        AsyncResultType: Type of async result to check
    
    Returns:
        Tuple of (status, success, error_message)
        - status: Job status (PENDING, EXECUTING, COMPLETED, FAILED)
        - success: Boolean indicating if the operation actually succeeded
        - error_message: Error message if there was a failure
    """
    query_path = os.path.join(graphqlfolder, CheckStatusType + '.graphql')
    
    with open(query_path, 'r') as queryfile:
        query = queryfile.read()
    
    log.debug(f"Job Status Check GraphQL Query:\n{query}")
    log.debug(f"Job Status Check Variables: {json.dumps(vars, indent=2)}")
    
    result = client.execute_query(query, vars)
    job_result = result[f'{AsyncResultType}']
    
    # Debug: Log the full response
    log.debug(f"Full job result response: {json.dumps(job_result, indent=2)}")
    
    status = job_result["jobStatus"]
    success = True
    error_message = None
    
    # If job is completed, check if it actually succeeded
    if status == "COMPLETED" and "results" in job_result:
        results = job_result["results"]
        log.debug(f"Job results section: {json.dumps(results, indent=2)}")
        
        if results and len(results) > 0:
            # Results is an array, check the first result
            first_result = results[0]
            if "succeeded" in first_result and not first_result["succeeded"]:
                success = False
                if "extensions" in first_result and first_result["extensions"]:
                    extensions = first_result["extensions"]
                    error_message = extensions.get("errorMessage", "Unknown error")
                    error_code = extensions.get("errorCode", "")
                    error_details = extensions.get("errorDetails", "")
                    
                    full_error = f"Error: {error_message}"
                    if error_code:
                        full_error += f" (Code: {error_code})"
                    if error_details:
                        full_error += f" Details: {error_details}"
                    error_message = full_error
                else:
                    error_message = "Operation failed but no error details provided"
            elif "succeeded" in first_result:
                log.debug(f"First result succeeded = {first_result['succeeded']}")
            else:
                log.debug("No 'succeeded' field found in first result")
        else:
            log.debug("Results array is empty or null")
    else:
        log.debug(f"Job status: {status}, results present: {'results' in job_result}")
    
    log.debug(f"Final assessment - Status: {status}, Success: {success}, Error: {error_message}")
    return status, success, error_message

def waitForJobCompletion(client, job_results, job_type="owner addition"):
    """
    Wait for async jobs to complete and report status
    
    Args:
        client: GraphQL client
        job_results: List of dicts with job_id and resource info
        job_type: Description of the job type for logging
    
    Returns:
        Dict with success/failed job counts and detailed job results
    """
    if not job_results:
        log.info(f"No {job_type} jobs to monitor")
        return {"successful": 0, "failed": 0, "details": []}
    
    log.info(f"Monitoring {len(job_results)} {job_type} jobs for completion...")
    
    successful_jobs = 0
    failed_jobs = 0
    job_details = []
    
    for job_result in job_results:
        job_id = job_result["job_id"]
        resource = job_result.get("resource", "")
        final_status = "UNKNOWN"  # Initialize with default
        
        try:
            log.debug(f"Checking status of job: {job_id} for resource: {resource}")
            vars = {'id': job_id}
            
            # Use the correct status check types based on operation and resource type
            if "folder" in job_type.lower():
                if "removal" in job_type.lower() or "remove" in job_type.lower():
                    CheckStatusType = "CheckStatus_RemoveFolder"
                    AsyncResultType = "governedResourceMutationJob"
                else:  # add operations
                    CheckStatusType = "CheckStatus_AddFolder"
                    AsyncResultType = "governedResourceMutationJob"
            else:  # group operations
                if "removal" in job_type.lower() or "remove" in job_type.lower():
                    CheckStatusType = "CheckStatus_removeGroup"
                    AsyncResultType = "governedGroupMutationJob"
                else:  # add operations
                    CheckStatusType = "CheckStatus_addGroup"
                    AsyncResultType = "governedGroupMutationJob"
            
            # Poll for completion (like PowerShell WaitForJobCompletion)
            max_attempts = 30  # Maximum polling attempts
            poll_interval = 5  # Seconds between polls
            
            for attempt in range(max_attempts):
                status, success, error_message = checkJobStatusAndResults(vars, client, CheckStatusType, AsyncResultType)
                final_status = status  # Track the final status
                log.debug(f"Job {job_id} status check {attempt + 1}/{max_attempts}: {status}, Success: {success}")
                
                if status == "COMPLETED":
                    if success:
                        successful_jobs += 1
                        log.info(f"SUCCESS: {job_type} job {job_id} completed successfully for {resource}")
                    else:
                        failed_jobs += 1
                        final_status = "FAILED_WITH_ERRORS"
                        log.error(f"FAILED: {job_type} job {job_id} completed but failed for {resource}")
                        log.error(f"GraphQL Error Details: {error_message}")
                        # Additional detailed error logging
                        log.error(f"Job ID: {job_id}")
                        log.error(f"Resource: {resource}")
                        log.error(f"Operation: {job_type}")
                    break
                elif status == "FAILED":
                    failed_jobs += 1
                    log.error(f"FAILED: {job_type} job {job_id} failed for {resource}")
                    break
                elif status in ["EXECUTING", "PENDING"]:
                    log.debug(f"Job {job_id} still {status}, waiting...")
                    if attempt < max_attempts - 1:  # Don't sleep on last attempt
                        time.sleep(poll_interval)
                    continue
                else:
                    # Unexpected status
                    failed_jobs += 1
                    final_status = f"UNEXPECTED:{status}"
                    log.warning(f"WARNING: {job_type} job {job_id} returned unexpected status: {status} for {resource}")
                    break
            else:
                # Loop completed without breaking (timeout)
                failed_jobs += 1
                final_status = "TIMEOUT"
                log.error(f"TIMEOUT: {job_type} job {job_id} timed out after {max_attempts * poll_interval} seconds for {resource}")
            
            job_detail = {
                "job_id": job_id, 
                "status": final_status, 
                "resource": resource
            }
            
            # Add error information if operation failed
            if not success and error_message:
                job_detail["error_message"] = error_message
                job_detail["graphql_extensions"] = error_message
            
            job_details.append(job_detail)
                
        except Exception as e:
            failed_jobs += 1
            final_status = "ERROR"
            log.error(f"ERROR: Error checking {job_type} job {job_id}: {e}")
            job_details.append({
                "job_id": job_id, 
                "status": final_status, 
                "error": str(e),
                "resource": resource
            })
    
    log.info(f"{job_type} completion summary: {successful_jobs} successful, {failed_jobs} failed")
    
    # Debug logging for CSV update troubleshooting
    log.debug(f"Job details being returned for CSV update: {len(job_details)} items")
    for detail in job_details[:3]:  # Log first 3 for debugging
        log.debug(f"Sample job detail: resource='{detail.get('resource')}', status='{detail.get('status')}', job_id='{detail.get('job_id')}'")
    
    return {
        "successful": successful_jobs, 
        "failed": failed_jobs, 
        "details": job_details
    }
  

def main (url=None, apikey=None):
    """
    Main function to replace ownership of resources.
    
    Args:
        url (str, optional): Tenant URL. If not provided, will try config file, then prompt user
        apikey (str, optional): API key. If not provided, will try config file, then prompt user
    """
    
    # Try to get URL from config file first, then fall back to parameters or user input
    if not url:
        try:
            tenantUrl = config_manager.get_tenant_url()
            log.info("Tenant URL loaded from config file")
        except Exception as e:
            log.warning(f"Could not load tenant URL from config: {e}")
            tenantUrl = tenantinfo.getAndReturnTenant()
    else: 
        check = tenantinfo.validateTenantURl(url)
        if check:
            tenantUrl = url
        else:
            log.error('Invalid URL provided, falling back to config or user input')
            tenantUrl = tenantinfo.getAndReturnTenant()
        
    # Try to get API key from config file first, then fall back to parameters or user input
    if not apikey:
        try:
            apikey = config_manager.get_api_key()
            log.info("API key loaded from config file")
        except Exception as e:
            log.warning(f"Could not load API key from config: {e}")
            apikey = tenantinfo.getAndReturnAPIKey()
    else:
        while True:
            check = tenantinfo.validateAPIKey(apikey)
            if check: 
                apikey = apikey
                break 
            else: 
                log.error('Invalid API Key')
                apikey = tenantinfo.getAndReturnAPIKey()
    
    # Get user inputs first
    current_owner, new_owner = get_user_inputs()
    
    if not current_owner or not new_owner:
        log.error("Invalid input provided")
        return
    
    log.info(f"Replacing owner '{current_owner}' with '{new_owner}'")
    

    token = authentication.Authenticate (tenantUrl, apikey)
    client = graphQLclient.GraphqlClient(tenantUrl, apikey, token,api_option='dag')
    
    # Pass the owners to your findOwnership function
    ownedFolders = findOwnership(client, current_owner,'folder')
    log.debug (ownedFolders)
    ownedGroups = findOwnership(client, current_owner,'group')
    log.debug (ownedGroups)
    
    # Initialize list to store all owned folder paths
    full_ownedFolders = []
    
    # Parse the JSON response from ownedFolders
    if ownedFolders:
        folders_data = json.loads(ownedFolders)
        
        # Check if the expected structure exists
        if "governedResourcesQueryJob" in folders_data and "results" in folders_data["governedResourcesQueryJob"]:
            log.debug("Extracting owned folder paths:")
            
            # Iterate through each folder
            for folder_item in folders_data["governedResourcesQueryJob"]["results"]:
                display_path = folder_item["displayPath"]
                full_ownedFolders.append(display_path)
                log.debug(f"Added folder: {display_path}")
        else:
            log.warning("No folders found in the response structure")

    # Initialize list to store all owned groups
    full_ownedGroups = []
    
    # Parse the JSON response from ownedGroups
    if ownedGroups:
        groups_data = json.loads(ownedGroups)
        
        # Check if the expected structure exists
        if "governedGroupsQueryJob" in groups_data and "results" in groups_data["governedGroupsQueryJob"]:
            log.debug("Combining owned groups:")
            
            # Iterate through each group
            for group_item in groups_data["governedGroupsQueryJob"]["results"]:
                group_info = group_item["group"]
                sam_account_name = group_info["samAccountName"]
                domain_name = group_info["directoryServices"]["name"]
                
                # Combine using your combineAccountOutput function and append to list
                full_account = combineAccountOutput(domain_name, sam_account_name)
                full_ownedGroups.append(full_account)
                log.debug(f"Added group: {full_account}")
        else:
            log.warning("No groups found in the response structure")

    log.info(f"All owned folders: {full_ownedFolders}")
    log.info(f"All owned groups: {full_ownedGroups}")
    
    # Create log file with the owned resources
    log_filename = makeLogFile(full_ownedFolders, full_ownedGroups, current_owner, new_owner)
    if log_filename:
        # Log the full path so you know exactly where it was created
        full_path = os.path.abspath(log_filename)
        log.info(f"Log file location: {full_path}")
    else:
        log.error("Failed to create log file")
    
    # Add new owner to all owned resources
    log.info("=" * 60)
    log.info("STARTING OWNERSHIP TRANSFER")
    log.info("=" * 60)
    
    folder_results = {"successful": 0, "failed": 0}
    group_results = {"successful": 0, "failed": 0}
    
    # Add new owner to folders
    if full_ownedFolders:
        log.info(f"Adding new owner to {len(full_ownedFolders)} folders...")
        folder_job_results = addNewOwner(client, full_ownedFolders, "folder", new_owner)
        
        # Wait for folder jobs to complete
        if folder_job_results:
            log.info("Waiting for folder ownership jobs to complete...")
            folder_results = waitForJobCompletion(client, folder_job_results, "folder owner addition")
            
            # Update CSV with add owner results
            if log_filename:
                try:
                    updateLogFileStatus(log_filename, folder_results, "add_owner")
                except Exception as e:
                    log.error(f"Failed to update CSV with folder add results: {e}")
        else:
            log.warning("No folder jobs were submitted successfully")
    else:
        log.info("No owned folders found to transfer")
    
    # Add new owner to groups
    if full_ownedGroups:
        log.info(f"Adding new owner to {len(full_ownedGroups)} groups...")
        group_job_results = addNewOwner(client, full_ownedGroups, "group", new_owner)
        
        # Wait for group jobs to complete
        if group_job_results:
            log.info("Waiting for group ownership jobs to complete...")
            group_results = waitForJobCompletion(client, group_job_results, "group owner addition")
            
            # Update CSV with add owner results
            if log_filename:
                try:
                    updateLogFileStatus(log_filename, group_results, "add_owner")
                except Exception as e:
                    log.error(f"Failed to update CSV with group add results: {e}")
        else:
            log.warning("No group jobs were submitted successfully")
    else:
        log.info("No owned groups found to transfer")
    
    # Summary of ownership addition results
    total_successful = folder_results["successful"] + group_results["successful"]
    total_failed = folder_results["failed"] + group_results["failed"]
    
    log.info("=" * 60)
    log.info("OWNERSHIP ADDITION COMPLETED")
    log.info(f"SUCCESS: Successfully added new owner to {total_successful} resources")
    log.info(f"FAILED: Failed to add new owner to {total_failed} resources")
    log.info("=" * 60)
    
    # Proceed with removal even if some additions failed (only remove from successful ones)
    if total_successful > 0:
        if total_failed == 0:
            log.info("SUCCESS: All ownership additions completed successfully!")
        else:
            log.warning(f"PARTIAL SUCCESS: {total_successful} additions succeeded, {total_failed} failed")
        
        log.info("Ready to proceed with removing old owner from successfully added resources...")
        
        # Step 5: Remove old owner from successfully added resources only
        log.info("=" * 60)
        log.info("STARTING OLD OWNER REMOVAL")
        log.info("=" * 60)
        
        remove_folder_results = {"successful": 0, "failed": 0}
        remove_group_results = {"successful": 0, "failed": 0}
        
        # Remove old owner from folders - ONLY from successfully added folders
        successful_folders = getSuccessfulResources(folder_results) if 'folder_results' in locals() else []
        if successful_folders:
            log.info(f"Removing old owner from {len(successful_folders)} successfully added folders...")
            folder_remove_job_results = removeOldOwner(client, successful_folders, "folder", current_owner)
            
            # Wait for folder removal jobs to complete
            if folder_remove_job_results:
                log.info("Waiting for folder ownership removal jobs to complete...")
                remove_folder_results = waitForJobCompletion(client, folder_remove_job_results, "folder owner removal")
                
                # Update CSV with remove owner results
                if log_filename:
                    try:
                        updateLogFileStatus(log_filename, remove_folder_results, "remove_owner")
                    except Exception as e:
                        log.error(f"Failed to update CSV with folder remove results: {e}")
            else:
                log.warning("No folder removal jobs were submitted successfully")
        else:
            log.info("No folders were successfully added - skipping folder owner removal")
        
        # Remove old owner from groups - ONLY from successfully added groups
        successful_groups = getSuccessfulResources(group_results) if 'group_results' in locals() else []
        if successful_groups:
            log.info(f"Removing old owner from {len(successful_groups)} successfully added groups...")
            group_remove_job_results = removeOldOwner(client, successful_groups, "group", current_owner)
            
            # Wait for group removal jobs to complete
            if group_remove_job_results:
                log.info("Waiting for group ownership removal jobs to complete...")
                remove_group_results = waitForJobCompletion(client, group_remove_job_results, "group owner removal")
                
                # Update CSV with remove owner results
                if log_filename:
                    try:
                        updateLogFileStatus(log_filename, remove_group_results, "remove_owner")
                    except Exception as e:
                        log.error(f"Failed to update CSV with group remove results: {e}")
            else:
                log.warning("No group removal jobs were submitted successfully")
        else:
            log.info("No groups were successfully added - skipping group owner removal")
        
        # Summary of ownership removal results
        total_remove_successful = remove_folder_results["successful"] + remove_group_results["successful"]
        total_remove_failed = remove_folder_results["failed"] + remove_group_results["failed"]
        
        log.info("=" * 60)
        log.info("OLD OWNER REMOVAL COMPLETED")
        log.info(f"SUCCESS: Successfully removed old owner from {total_remove_successful} resources")
        log.info(f"FAILED: Failed to remove old owner from {total_remove_failed} resources")
        log.info("=" * 60)
        
        # Final summary
        if total_remove_failed == 0 and total_remove_successful > 0:
            log.info("SUCCESS: Complete ownership replacement successful!")
            log.info(f"Ownership transferred from '{current_owner}' to '{new_owner}' for {total_successful} resources")
        elif total_remove_failed > 0:
            log.error(f"WARNING: {total_remove_failed} old owner removals failed. Manual cleanup may be required.")
            log.info(f"However, {total_remove_successful} resources completed full ownership transfer successfully")
        else:
            log.info("No old owner removals were performed.")
        
        # Report on any failed additions that were skipped
        if total_failed > 0:
            log.warning(f"IMPORTANT: {total_failed} resources failed during addition phase and were skipped for removal")
            log.warning("Please review the CSV log for detailed status of each resource")
            
    else:
        log.error("No ownership additions were successful - cannot proceed with removal operations")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description='Replace ownership of all folders and groups owned by a specified user.',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
    python replaceOwner.py                                    # Use config.json for tenant/API
    python replaceOwner.py https://tenant.varonis.io          # Use config.json for API key  
    python replaceOwner.py https://tenant.varonis.io vkey1_abc123...  # Use command line for both

Configuration:
    - Tenant URL and API key can be provided via command line arguments OR
    - Configured in src/Config/config.json file
    - If both are available, command line arguments take precedence
    - If neither are provided, the script will prompt for input
        """
    )
    
    parser.add_argument('url', nargs='?', help='Tenant URL (optional if configured in config.json)')
    parser.add_argument('apikey', nargs='?', help='API Key (optional if configured in config.json)')
    
    args = parser.parse_args()
    main(args.url, args.apikey)