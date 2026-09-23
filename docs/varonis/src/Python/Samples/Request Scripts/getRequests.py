# Varonis' sample code(s) are provided on an "as is" and "as available" basis and without any warranty of any kind.  
# Any use of Varonis' sample code(s) is optional at client's sole discretion, responsibility and risk.
# Varonis does not make any commitment with respect to Varonis' sample code(s), their specific functions or their availability, reliability, or ability to meet client's needs.
# Client acknowledges that Varonis may, in its sole discretion, modify, discontinue or update the Varonis' sample code(s) from time to time, without notice and for any reason.

import sys
import os 
import datetime
import json
import argparse

modules_path = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', 'Modules'))
sys.path.append(modules_path)

import tenantinfo
import authentication
import graphQLclient
import graphQLhelpers as helpers
from logger import get_logger

log = get_logger(__name__)

graphqlfolder = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..', 'Config', 'graphql'))

def get_dynamic_inputs():
    reqVars = {}

    allowed_types = {"DIRECT_PERMISSION", "ENTITLEMENT_REVIEW", "FOLDER_CREATION", "MEMBERSHIP", "PERMISSION"}
    allowed_statuses = {
        "APPROVED", "CANCELED", "DECLINED", "ERROR", "EXECUTING", "EXPIRED",
        "PARTIAL", "PENDING", "PENDING_ACTIVATION", "SIGNED", "SUB_REQ"
    }

    # ID (Long)
    while True:
        id_input = input("Enter ID (leave blank to skip): ").strip()
        if not id_input:
            break
        try:
            reqVars["id"] = int(id_input)
            break
        except ValueError:
            log.error("ID must be a number. Please try again or leave blank to skip.")

    # RequestedBy
    requested_by = input("Requested By (domain\\user, leave blank to skip): ").strip()
    if requested_by and "\\" in requested_by:
        domain, user = requested_by.split("\\", 1)
        reqVars["requestedBySamAccountName"] = user.strip()
        reqVars["requestedByDirectoryServicesName"] = domain.strip()

    # RequestedFor
    requested_for = input("Requested For (domain\\user, leave blank to skip): ").strip()
    if requested_for and "\\" in requested_for:
        domain, user = requested_for.split("\\", 1)
        reqVars["requestedForSamAccountName"] = user.strip()
        reqVars["requestedForDirectoryServicesName"] = domain.strip()

    # Status
    while True:
        status_input = input("Status (comma separated, e.g. PENDING,COMPLETED; leave blank to skip): ").strip()
        if not status_input:
            break
        statuses = [s.strip().upper() for s in status_input.split(",")]
        invalid = [s for s in statuses if s not in allowed_statuses]
        if invalid:
            log.error(f"Invalid status(es): {', '.join(invalid)}. Allowed statuses are: {', '.join(allowed_statuses)}")
        else:
            reqVars["status"] = statuses
            break

    # Type
    while True:
        type_input = input("Type (comma separated, e.g. DIRECT_PERMISSION,ENTITLEMENT_REVIEW; leave blank to skip): ").strip()
        if not type_input:
            break
        types = [t.strip().upper() for t in type_input.split(",")]
        invalid = [t for t in types if t not in allowed_types]
        if invalid:
            log.error(f"Invalid type(s): {', '.join(invalid)}. Allowed types are: {', '.join(allowed_types)}")
        else:
            reqVars["type"] = types
            break

    # Creation Date Range
    while True:
        date_range = input("How many days back to look for creation date (leave blank to skip): ").strip()
        if not date_range:
            break
        try:
            days_back = int(date_range)
            if days_back <= 0:
                log.error("Please enter a positive number.")
                continue
            now = datetime.datetime.now(datetime.UTC)
            creationDateFrom = now - datetime.timedelta(days=days_back)
            reqVars["creationDateFrom"] = creationDateFrom.strftime('%Y-%m-%dT%H:%M:%SZ')
            reqVars["creationDateTo"] = now.strftime('%Y-%m-%dT%H:%M:%SZ')
            break
        except ValueError:
            log.error("Please enter a valid positive integer for days back.")

    return reqVars

def get_args_inputs(args):
    """
    Convert command line arguments to the same format as get_dynamic_inputs()
    
    Args:
        args: Parsed command line arguments
        
    Returns:
        dict: Request variables dictionary
    """
    reqVars = {}
    
    allowed_types = {"DIRECT_PERMISSION", "ENTITLEMENT_REVIEW", "FOLDER_CREATION", "MEMBERSHIP", "PERMISSION"}
    allowed_statuses = {
        "APPROVED", "CANCELED", "DECLINED", "ERROR", "EXECUTING", "EXPIRED",
        "PARTIAL", "PENDING", "PENDING_ACTIVATION", "SIGNED", "SUB_REQ"
    }
    
    # ID
    if args.id is not None:
        reqVars["id"] = args.id
    
    # RequestedBy
    if args.requestedby:
        if "\\" in args.requestedby:
            domain, user = args.requestedby.split("\\", 1)
            reqVars["requestedBySamAccountName"] = user.strip()
            reqVars["requestedByDirectoryServicesName"] = domain.strip()
        else:
            log.error("RequestedBy must be in format 'domain\\user'")
            sys.exit(1)
    
    # RequestedFor
    if args.requestedfor:
        if "\\" in args.requestedfor:
            domain, user = args.requestedfor.split("\\", 1)
            reqVars["requestedForSamAccountName"] = user.strip()
            reqVars["requestedForDirectoryServicesName"] = domain.strip()
        else:
            log.error("RequestedFor must be in format 'domain\\user'")
            sys.exit(1)
    
    # Status
    if args.status:
        statuses = [s.strip().upper() for s in args.status.split(",")]
        invalid = [s for s in statuses if s not in allowed_statuses]
        if invalid:
            log.error(f"Invalid status(es): {', '.join(invalid)}. Allowed statuses are: {', '.join(allowed_statuses)}")
            sys.exit(1)
        reqVars["status"] = statuses
    
    # Type
    if args.requesttype:
        types = [t.strip().upper() for t in args.requesttype.split(",")]
        invalid = [t for t in types if t not in allowed_types]
        if invalid:
            log.error(f"Invalid type(s): {', '.join(invalid)}. Allowed types are: {', '.join(allowed_types)}")
            sys.exit(1)
        reqVars["type"] = types
    
    # Creation Date Range
    if args.daysback:
        if args.daysback <= 0:
            log.error("Days back must be a positive number.")
            sys.exit(1)
        now = datetime.datetime.now(datetime.UTC)
        creationDateFrom = now - datetime.timedelta(days=args.daysback)
        reqVars["creationDateFrom"] = creationDateFrom.strftime('%Y-%m-%dT%H:%M:%SZ')
        reqVars["creationDateTo"] = now.strftime('%Y-%m-%dT%H:%M:%SZ')
    
    return reqVars

def main(args=None, return_results=False, reqVars=None):
    """
    Main function to query governed requests
    
    Args:
        args: Command line arguments (optional)
        return_results: If True, returns the results instead of just logging them
        reqVars: Pre-built request variables dict (optional, overrides args/interactive input)
        
    Returns:
        list: Request results if return_results=True, otherwise None
    """
    # Always get credentials from config file
    tenantUrl = tenantinfo.getAndReturnTenant()
    apikey = tenantinfo.getAndReturnAPIKey()
    #end tenant and api validation 

    #generate auth token and graphql client 
    token = authentication.Authenticate (tenantUrl, apikey)
    client = graphQLclient.GraphqlClient(tenantUrl, apikey, token,api_option='dag')
    #end generate token and graphql client 
    
    # Use provided reqVars, or get them from args/interactive input
    if reqVars is None:
        reqVars = {}
        
        # Check if any command line arguments were provided (excluding just --help or --version)
        if args and any([args.id is not None, args.requestedby, args.requestedfor, args.status, args.requesttype, args.daysback]):
            # Use command line arguments
            reqVars = get_args_inputs(args)
            log.info("Using command line arguments for request filters")
            if reqVars:
                log.info(f"Applied filters: {json.dumps(reqVars, indent=2)}")
        else:
            # Use interactive input
            log.info("No command line filters provided, using interactive input")
            while not reqVars:
                reqVars = get_dynamic_inputs()
    else:
        log.info("Using provided reqVars for request filters")
        log.info(f"Applied filters: {json.dumps(reqVars, indent=2)}")

    query = helpers.getQueryFile('async_getRequests',graphqlfolder)
       
    log.debug("Executing GraphQL query: async_getRequests")
    log.debug(f"GraphQL Query:\n{query}")
    log.debug(f"GraphQL Variables:\n{json.dumps(reqVars, indent=2)}")
    result = client.execute_query (query, reqVars)
    job_id = result['governedRequestsAsync']['jobId']
    
    # Return results if requested, otherwise just log them
    return helpers.checkQueryAsync(job_id, client, graphqlfolder, return_results=return_results)


def parse_arguments():
    """
    Parse command line arguments for the get requests script.
    
    Returns:
        argparse.Namespace: Parsed arguments
    """
    parser = argparse.ArgumentParser(
        description='Query Varonis DAG governed requests with filters',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s                                              # Run with interactive prompts for filters
  %(prog)s --id 12345                                   # Get request with specific ID
  %(prog)s --status PENDING,APPROVED                    # Get requests with specific statuses
  %(prog)s --requesttype MEMBERSHIP,PERMISSION          # Get requests of specific types
  %(prog)s --requestedby "domain\\user"                 # Get requests by specific user
  %(prog)s --requestedfor "domain\\user"                # Get requests for specific user
  %(prog)s --daysback 7                                 # Get requests from last 7 days
  %(prog)s --status PENDING --requesttype MEMBERSHIP    # Combine multiple filters
        """
    )
    
    parser.add_argument(
        '--version',
        action='version',
        version='Get Requests Script 1.0'
    )
    
    parser.add_argument(
        '--id',
        type=int,
        help='Request ID (integer)'
    )
    
    parser.add_argument(
        '--requestedby',
        type=str,
        help='Requested by user in format "domain\\user"'
    )
    
    parser.add_argument(
        '--requestedfor', 
        type=str,
        help='Requested for user in format "domain\\user"'
    )
    
    parser.add_argument(
        '--status',
        type=str,
        help='Request status(es), comma-separated. Valid values: APPROVED, CANCELED, DECLINED, ERROR, EXECUTING, EXPIRED, PARTIAL, PENDING, PENDING_ACTIVATION, SIGNED, SUB_REQ'
    )
    
    parser.add_argument(
        '--requesttype',
        type=str, 
        help='Request type(s), comma-separated. Valid values: DIRECT_PERMISSION, ENTITLEMENT_REVIEW, FOLDER_CREATION, MEMBERSHIP, PERMISSION'
    )
    
    parser.add_argument(
        '--daysback',
        type=int,
        help='Number of days back to look for creation date (positive integer)'
    )
    
    return parser.parse_args()

    

if __name__ == "__main__":
    args = parse_arguments()
    main(args)