#!/usr/bin/env python3
# Varonis' sample code(s) are provided on an "as is" and "as available" basis and without any warranty of any kind.  
# Any use of Varonis' sample code(s) is optional at client's sole discretion, responsibility and risk.
# Varonis does not make any commitment with respect to Varonis' sample code(s), their specific functions or their availability, reliability, or ability to meet client's needs.
# Client acknowledges that Varonis may, in its sole discretion, modify, discontinue or update the Varonis' sample code(s) from time to time, without notice and for any reason.

"""
DAG Ownership Rollback Script

This script reads a CSV audit trail from the replaceOwner.py script and reverses 
the ownership changes by:
1. Adding the original owner back to resources
2. Removing the new owner from resources
3. Creating a new audit trail CSV for the rollback operation

Configuration:
- Tenant URL and API key can be provided via command line arguments OR
- Configured in src/Config/config.json file
- If both are available, command line arguments take precedence
- If neither are provided after the CSV file argument, config.json will be used

Usage:
    python rollbackOwner.py <csv_file>                                     # Use config.json for tenant/API
    python rollbackOwner.py <csv_file> <tenant_url>                        # Use config.json for API key
    python rollbackOwner.py <csv_file> <tenant_url> <api_key>              # Use command line for both

Examples:
    python rollbackOwner.py old_owner_user_20250909_143947.csv
    python rollbackOwner.py old_owner_user_20250909_143947.csv https://tenant.varonis.io
    python rollbackOwner.py old_owner_user_20250909_143947.csv https://tenant.varonis.io vkey1_abc123...

Author: GitHub Copilot
Date: September 2025
"""

import sys
import os
import csv
import argparse
from datetime import datetime
import time

# Add the modules directory to the path
sys.path.append(os.path.join(os.path.dirname(__file__), '..', '..', 'Modules'))

# Import required modules
import logger
import checkDAGjob
import graphQLclient
import graphQLhelpers
import config_manager

def validate_csv_file(csv_file_path, log):
    """Validate and read the CSV audit trail file"""
    if not os.path.exists(csv_file_path):
        log.error(f"CSV file not found: {csv_file_path}")
        return None
    
    try:
        rollback_data = []
        with open(csv_file_path, 'r', newline='', encoding='utf-8') as file:
            reader = csv.DictReader(file)
            
            # Validate required columns
            required_columns = [
                'Resource Type', 'Resource Path/Name', 'Current Owner', 'New Owner',
                'Add Owner Status', 'Remove Owner Status'
            ]
            
            if not all(col in reader.fieldnames for col in required_columns):
                log.error(f"CSV file missing required columns. Expected: {required_columns}")
                log.error(f"Found columns: {reader.fieldnames}")
                return None
            
            for row in reader:
                # Only process rows where both operations completed successfully
                if (row['Add Owner Status'] == 'COMPLETED' and 
                    row['Remove Owner Status'] == 'COMPLETED'):
                    rollback_data.append(row)
                else:
                    log.warning(f"Skipping incomplete operation for {row['Resource Path/Name']}: "
                              f"Add={row['Add Owner Status']}, Remove={row['Remove Owner Status']}")
        
        log.info(f"Successfully validated CSV file. Found {len(rollback_data)} completed operations to rollback")
        return rollback_data
        
    except Exception as e:
        log.error(f"Error reading CSV file: {str(e)}")
        return None

def create_rollback_csv(rollback_data, log):
    """Create a new CSV file to track the rollback operations"""
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    script_dir = os.path.dirname(os.path.abspath(__file__))
    
    # Extract original owner from the first row
    if rollback_data:
        original_owner = rollback_data[0]['Current Owner']
        csv_filename = f"rollback_{original_owner.replace('\\', '_')}_{timestamp}.csv"
    else:
        csv_filename = f"rollback_{timestamp}.csv"
    
    csv_path = os.path.join(script_dir, csv_filename)
    
    try:
        with open(csv_path, 'w', newline='', encoding='utf-8') as file:
            fieldnames = [
                'Resource Type', 'Resource Path/Name', 'Original Owner', 'Owner to Remove',
                'Restore Owner Status', 'Restore Owner Job ID', 
                'Remove Owner Status', 'Remove Owner Job ID'
            ]
            
            writer = csv.DictWriter(file, fieldnames=fieldnames)
            writer.writeheader()
            
            for row in rollback_data:
                # For rollback: restore original owner, remove new owner
                rollback_row = {
                    'Resource Type': row['Resource Type'],
                    'Resource Path/Name': row['Resource Path/Name'],
                    'Original Owner': row['Current Owner'],  # Owner to restore
                    'Owner to Remove': row['New Owner'],     # Owner to remove
                    'Restore Owner Status': 'Pending',
                    'Restore Owner Job ID': '',
                    'Remove Owner Status': 'Pending', 
                    'Remove Owner Job ID': ''
                }
                writer.writerow(rollback_row)
        
        log.info(f"Created rollback CSV file: {csv_filename}")
        return csv_path
        
    except Exception as e:
        log.error(f"Error creating rollback CSV file: {str(e)}")
        return None

def addOwnerBack(client, entities, entity_type, original_owner, log):
    """Add the original owner back to resources using existing GraphQL files"""
    log.info(f"Restoring original owner '{original_owner}' to {len(entities)} {entity_type}(s)")
    
    job_results = []
    successful_submissions = 0
    
    # Get GraphQL folder path
    graphql_folder = os.path.join(os.path.dirname(__file__), '..', '..', '..', 'Config', 'graphql')
    
    for entity in entities:
        try:
            log.debug(f"Restoring original owner to {entity_type}: {entity}")
            
            # Parse owner domain and name
            owner_parts = original_owner.split('\\')
            owner_domain = owner_parts[0]
            owner_name = owner_parts[1]
            
            if entity_type == "folder":
                # Use existing async_addFolderOwner.graphql
                query = graphQLhelpers.getQueryFile("async_addFolderOwner", graphql_folder)
                variables = {
                    "displayPath": entity,
                    "ownerName": owner_name,
                    "ownerDomain": owner_domain
                }
                
                response = client.execute_query(query, variables)
                
                if response and "addGovernedResourceOwnersAsync" in response:
                    job_id = response['addGovernedResourceOwnersAsync']['jobId']
                    successful_submissions += 1
                    log.debug(f"Successfully submitted restore job for folder {entity}: {job_id}")
                else:
                    log.error(f"Failed to restore original owner to folder {entity}: No job ID returned")
                    job_id = None
                    
            elif entity_type == "group":
                # Use existing async_addGroupOwner.graphql
                query = graphQLhelpers.getQueryFile("async_addGroupOwner", graphql_folder)
                
                # Parse group domain and name
                group_parts = entity.split('\\')
                group_domain = group_parts[0] 
                group_name = group_parts[1]
                
                variables = {
                    "groupName": group_name,
                    "groupDomain": group_domain,
                    "ownerName": owner_name,
                    "ownerDomain": owner_domain
                }
                
                response = client.execute_query(query, variables)
                
                if response and "addGovernedGroupOwnersAsync" in response:
                    job_id = response['addGovernedGroupOwnersAsync']['jobId']
                    successful_submissions += 1
                    log.debug(f"Successfully submitted restore job for group {entity}: {job_id}")
                else:
                    log.error(f"Failed to restore original owner to group {entity}: No job ID returned")
                    job_id = None
            
            if job_id:
                job_results.append({
                    "job_id": job_id,
                    "resource": entity,
                    "entity_type": entity_type,
                    "operation": "restore_owner"
                })
            else:
                job_results.append({
                    "job_id": None,
                    "resource": entity, 
                    "entity_type": entity_type,
                    "operation": "restore_owner",
                    "status": "FAILED"
                })
                
        except Exception as e:
            log.error(f"Exception while restoring original owner to {entity_type} {entity}: {str(e)}")
            job_results.append({
                "job_id": None,
                "resource": entity,
                "entity_type": entity_type, 
                "operation": "restore_owner",
                "status": "ERROR"
            })
    
    log.info(f"Submitted {successful_submissions}/{len(entities)} {entity_type} owner restoration jobs")
    return job_results

def removeNewOwner(client, entities, entity_type, new_owner, log):
    """Remove the new owner from resources using existing GraphQL files"""
    log.info(f"Removing new owner '{new_owner}' from {len(entities)} {entity_type}(s)")
    
    job_results = []
    successful_submissions = 0
    
    # Get GraphQL folder path
    graphql_folder = os.path.join(os.path.dirname(__file__), '..', '..', '..', 'Config', 'graphql')
    
    for entity in entities:
        try:
            log.debug(f"Removing new owner from {entity_type}: {entity}")
            
            # Parse owner domain and name
            owner_parts = new_owner.split('\\')
            owner_domain = owner_parts[0]
            owner_name = owner_parts[1]
            
            if entity_type == "folder":
                # Use existing async_removeFolderOwner.graphql
                query = graphQLhelpers.getQueryFile("async_removeFolderOwner", graphql_folder)
                variables = {
                    "displayPath": entity,
                    "ownerName": owner_name,
                    "ownerDomain": owner_domain
                }
                
                response = client.execute_query(query, variables)
                
                if response and "removeGovernedResourceOwnersAsync" in response:
                    job_id = response['removeGovernedResourceOwnersAsync']['jobId']
                    successful_submissions += 1
                    log.debug(f"Successfully submitted removal job for folder {entity}: {job_id}")
                else:
                    log.error(f"Failed to remove new owner from folder {entity}: No job ID returned")
                    job_id = None
                    
            elif entity_type == "group":
                # Use existing async_removeGroupOwner.graphql
                query = graphQLhelpers.getQueryFile("async_removeGroupOwner", graphql_folder)
                
                # Parse group domain and name
                group_parts = entity.split('\\')
                group_domain = group_parts[0]
                group_name = group_parts[1]
                
                variables = {
                    "groupName": group_name,
                    "groupDomain": group_domain,
                    "ownerName": owner_name,
                    "ownerDomain": owner_domain
                }
                
                response = client.execute_query(query, variables)
                
                if response and "removeGovernedGroupOwnersAsync" in response:
                    job_id = response['removeGovernedGroupOwnersAsync']['jobId']
                    successful_submissions += 1
                    log.debug(f"Successfully submitted removal job for group {entity}: {job_id}")
                else:
                    log.error(f"Failed to remove new owner from group {entity}: No job ID returned")
                    job_id = None
            
            if job_id:
                job_results.append({
                    "job_id": job_id,
                    "resource": entity,
                    "entity_type": entity_type,
                    "operation": "remove_owner"
                })
            else:
                job_results.append({
                    "job_id": None,
                    "resource": entity,
                    "entity_type": entity_type,
                    "operation": "remove_owner", 
                    "status": "FAILED"
                })
                
        except Exception as e:
            log.error(f"Exception while removing new owner from {entity_type} {entity}: {str(e)}")
            job_results.append({
                "job_id": None,
                "resource": entity,
                "entity_type": entity_type,
                "operation": "remove_owner",
                "status": "ERROR"
            })
    
    log.info(f"Submitted {successful_submissions}/{len(entities)} {entity_type} owner removal jobs")
    return job_results

def waitForJobCompletion(client, job_results, job_type, log):
    """Wait for job completion using existing checkDAGjob module"""
    if not job_results:
        log.warning("No jobs to monitor")
        return []
    
    # Filter out jobs without job IDs
    valid_jobs = [job for job in job_results if job.get("job_id")]
    
    if not valid_jobs:
        log.warning("No valid jobs to monitor")
        return job_results
    
    log.info(f"Monitoring {len(valid_jobs)} {job_type} jobs for completion...")
    
    max_attempts = 30
    attempt = 0
    
    while attempt < max_attempts:
        attempt += 1
        all_completed = True
        
        for job in valid_jobs:
            if job.get("status"):  # Skip if already has status
                continue
                
            job_id = job["job_id"]
            resource = job["resource"]
            
            try:
                # Determine status check type based on job type and entity
                if job.get("entity_type") == "folder":
                    if "addGovernedResourceOwners" in job_id:
                        CheckStatusType = "CheckStatus_AddFolder"
                        AsyncResultType = "governedResourceMutationJob"
                    else:
                        CheckStatusType = "CheckStatus_RemoveFolder"
                        AsyncResultType = "governedResourceMutationJob"
                elif job.get("entity_type") == "group":
                    if "addGovernedGroupOwners" in job_id:
                        CheckStatusType = "CheckStatus_addGroup"
                        AsyncResultType = "governedGroupMutationJob"
                    else:
                        CheckStatusType = "CheckStatus_removeGroup"
                        AsyncResultType = "governedGroupMutationJob"
                
                vars = {"id": job_id}
                status = checkDAGjob.checkStatus(vars, client, CheckStatusType, AsyncResultType)
                
                log.debug(f"Job {job_id} status check {attempt}/{max_attempts}: {status}")
                
                if status == "COMPLETED":
                    job["status"] = "COMPLETED"
                    log.info(f"SUCCESS: {job_type} job {job_id} completed successfully for {resource}")
                elif status in ["FAILED", "ERROR"]:
                    job["status"] = "FAILED"
                    log.error(f"FAILED: {job_type} job {job_id} failed for {resource}")
                else:
                    all_completed = False
                    log.debug(f"Job {job_id} still {status}, waiting...")
                    
            except Exception as e:
                log.error(f"Error checking status for job {job_id}: {str(e)}")
                job["status"] = "ERROR"
        
        if all_completed:
            break
            
        if attempt < max_attempts:
            time.sleep(10)  # Wait 10 seconds between checks
    
    # Mark any remaining jobs without status as timeout
    for job in valid_jobs:
        if not job.get("status"):
            job["status"] = "TIMEOUT"
            log.warning(f"TIMEOUT: Job {job['job_id']} did not complete within timeout")
    
    return job_results

def updateRollbackCSV(csv_path, job_results, operation_type, log):
    """Update the rollback CSV file with job results"""
    try:
        # Read current CSV content
        rows = []
        with open(csv_path, 'r', newline='', encoding='utf-8') as file:
            reader = csv.DictReader(file)
            fieldnames = reader.fieldnames
            for row in reader:
                rows.append(row)
        
        # Determine which columns to update based on operation type
        if operation_type == "restore_owner":
            status_col = "Restore Owner Status"
            job_id_col = "Restore Owner Job ID"
        elif operation_type == "remove_owner":
            status_col = "Remove Owner Status" 
            job_id_col = "Remove Owner Job ID"
        else:
            log.error(f"Unknown operation type: {operation_type}")
            return
        
        # Update rows with job results
        updates_made = 0
        for job_result in job_results:
            result_resource = job_result["resource"]
            
            for row in rows:
                resource_path = row["Resource Path/Name"].strip()
                
                if result_resource == resource_path:
                    # Update status
                    old_status = row.get(status_col, "")
                    new_status = job_result.get("status", "Unknown")
                    row[status_col] = new_status
                    
                    # Update job ID if available
                    if job_result.get("job_id"):
                        row[job_id_col] = job_result["job_id"]
                    
                    updates_made += 1
                    log.debug(f"Updated {operation_type} status from '{old_status}' to '{new_status}' for: {resource_path}")
                    break
        
        # Write updated content back to CSV
        with open(csv_path, 'w', newline='', encoding='utf-8') as file:
            writer = csv.DictWriter(file, fieldnames=fieldnames)
            writer.writeheader()
            writer.writerows(rows)
        
        log.info(f"Made {updates_made} updates to rollback CSV file for {operation_type}")
        
    except Exception as e:
        log.error(f"Error updating rollback CSV file: {str(e)}")

def main(csv_file, dag_url=None, api_key=None):
    """
    Main rollback function
    
    Args:
        csv_file (str): Path to the CSV audit trail file from replaceOwner.py
        dag_url (str, optional): Tenant URL. If not provided, will try config file
        api_key (str, optional): API key. If not provided, will try config file
    """
    # Setup logging
    log = logger.get_logger(__name__)
    log.info("Starting DAG Ownership Rollback Script")
    
    try:
        # Try to get URL from config file if not provided
        if not dag_url:
            try:
                dag_url = config_manager.get_tenant_url()
                log.info("Tenant URL loaded from config file")
            except Exception as e:
                log.error(f"Could not load tenant URL from config: {e}")
                log.error("Please provide tenant URL as command line argument or configure it in config.json")
                return 1
        
        # Try to get API key from config file if not provided
        if not api_key:
            try:
                api_key = config_manager.get_api_key()
                log.info("API key loaded from config file")
            except Exception as e:
                log.error(f"Could not load API key from config: {e}")
                log.error("Please provide API key as command line argument or configure it in config.json")
                return 1
        log.info(f"Rollback parameters - CSV: {csv_file}, URL: {dag_url}")
        
        # Validate and read CSV file
        rollback_data = validate_csv_file(csv_file, log)
        if not rollback_data:
            log.error("Failed to validate CSV file. Exiting.")
            return 1
        
        # Create rollback CSV for tracking
        rollback_csv_path = create_rollback_csv(rollback_data, log)
        if not rollback_csv_path:
            log.error("Failed to create rollback CSV file. Exiting.")
            return 1
        
        # Setup DAG client
        log.info("Connecting to DAG API...")
        client = graphQLclient.GraphqlClient(dag_url, api_key, None, api_option='dag')
        log.info("Successfully connected to DAG API")
        
        # Separate resources by type
        folders = []
        groups = []
        
        for row in rollback_data:
            if row['Resource Type'].lower() == 'folder':
                folders.append(row['Resource Path/Name'])
            elif row['Resource Type'].lower() == 'group':
                groups.append(row['Resource Path/Name'])
        
        log.info(f"Rollback scope: {len(folders)} folders, {len(groups)} groups")
        
        # Get original and new owner from first row (should be consistent across all rows)
        if rollback_data:
            original_owner = rollback_data[0]['Current Owner']
            new_owner = rollback_data[0]['New Owner']
            log.info(f"Rollback operation: Restoring '{original_owner}', Removing '{new_owner}'")
        
        # Phase 1: Restore original owner to folders
        if folders:
            log.info(f"Phase 1: Restoring original owner to {len(folders)} folders")
            folder_restore_results = addOwnerBack(client, folders, "folder", original_owner, log)
            
            if folder_restore_results:
                # Monitor folder restoration jobs
                folder_restore_completion = waitForJobCompletion(client, folder_restore_results, "folder owner restoration", log)
                # Update rollback CSV with results
                updateRollbackCSV(rollback_csv_path, folder_restore_completion, "restore_owner", log)
        
        # Phase 2: Restore original owner to groups  
        if groups:
            log.info(f"Phase 2: Restoring original owner to {len(groups)} groups")
            group_restore_results = addOwnerBack(client, groups, "group", original_owner, log)
            
            if group_restore_results:
                # Monitor group restoration jobs
                group_restore_completion = waitForJobCompletion(client, group_restore_results, "group owner restoration", log)
                # Update rollback CSV with results
                updateRollbackCSV(rollback_csv_path, group_restore_completion, "restore_owner", log)
        
        # Phase 3: Remove new owner from folders
        if folders:
            log.info(f"Phase 3: Removing new owner from {len(folders)} folders")
            folder_remove_results = removeNewOwner(client, folders, "folder", new_owner, log)
            
            if folder_remove_results:
                # Monitor folder removal jobs
                folder_remove_completion = waitForJobCompletion(client, folder_remove_results, "folder owner removal", log)
                # Update rollback CSV with results
                updateRollbackCSV(rollback_csv_path, folder_remove_completion, "remove_owner", log)
        
        # Phase 4: Remove new owner from groups
        if groups:
            log.info(f"Phase 4: Removing new owner from {len(groups)} groups")
            group_remove_results = removeNewOwner(client, groups, "group", new_owner, log)
            
            if group_remove_results:
                # Monitor group removal jobs
                group_remove_completion = waitForJobCompletion(client, group_remove_results, "group owner removal", log)
                # Update rollback CSV with results
                updateRollbackCSV(rollback_csv_path, group_remove_completion, "remove_owner", log)
        
        log.info("Rollback operation completed!")
        log.info(f"Rollback audit trail saved to: {rollback_csv_path}")
        
        return 0
        
    except Exception as e:
        log.error(f"Fatal error during rollback operation: {str(e)}")
        return 1

if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description='Rollback ownership changes using a CSV file generated by replaceOwner.py',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
    python rollbackOwner.py old_owner_user_20250909_143947.csv
    python rollbackOwner.py old_owner_user_20250909_143947.csv https://tenant.varonis.io
    python rollbackOwner.py old_owner_user_20250909_143947.csv https://tenant.varonis.io vkey1_abc123...

Configuration:
    - CSV file is required (generated by replaceOwner.py)
    - Tenant URL and API key are optional if configured in config.json
    - Command line arguments take precedence over config.json
        """
    )
    
    parser.add_argument('csv_file', help='CSV file containing ownership changes to rollback')
    parser.add_argument('dag_url', nargs='?', help='Tenant URL (optional if configured in config.json)')
    parser.add_argument('api_key', nargs='?', help='API Key (optional if configured in config.json)')
    
    args = parser.parse_args()
    
    exit_code = main(args.csv_file, args.dag_url, args.api_key)
    sys.exit(exit_code)
