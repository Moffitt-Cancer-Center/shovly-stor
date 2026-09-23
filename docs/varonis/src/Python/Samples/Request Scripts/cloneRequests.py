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

from logger import get_logger
from getRequests import main as get_requests_main
from membershipRequest import main as membership_main
from permissionRequest import main as permission_main

log = get_logger(__name__)

def get_args_inputs(args):
    """
    Convert command line arguments to the same format as get_dynamic_inputs()
    
    Args:
        args: Parsed command line arguments
        
    Returns:
        dict: Request variables dictionary
    """
    reqVars = {}
    
    allowed_statuses = {
        "ERROR", "EXPIRED"
    }
    
    # ID
    if args.debugmode_id is not None:
        reqVars["id"] = args.debugmode_id
    
    # Status
    if args.status:
        statuses = [s.strip().upper() for s in args.status.split(",")]
        invalid = [s for s in statuses if s not in allowed_statuses]
        if invalid:
            log.error(f"Invalid status(es): {', '.join(invalid)}. Allowed statuses are: {', '.join(allowed_statuses)}")
            sys.exit(1)
        reqVars["status"] = statuses
    
    # Creation Date Range
    if args.daysback:
        if args.daysback <= 0:
            log.error("Days back must be a positive number.")
            sys.exit(1)
        now = datetime.datetime.now(datetime.UTC)
        creationDateFrom = now - datetime.timedelta(days=args.daysback)
        reqVars["creationDateFrom"] = creationDateFrom.strftime('%Y-%m-%dT%H:%M:%SZ')
        reqVars["creationDateTo"] = now.strftime('%Y-%m-%dT%H:%M:%SZ')

    args.requesttype = ["DIRECT_PERMISSION", "MEMBERSHIP", "PERMISSION"]
    
    return reqVars

def main(args=None):
    """
    Main function to query governed requests
    
    Args:
        args: Command line arguments (optional)
    """
   
    reqVars = {}
    
    # Check if any command line arguments were provided (excluding just --help or --version)
    if args and any([args.debugmode_id is not None, args.status, args.daysback]):
        # Use command line arguments
        reqVars = get_args_inputs(args)
        log.info("Using command line arguments")
        if reqVars:
            log.info(f"Applied filters: {json.dumps(reqVars, indent=2)}")
    else:
        # Use interactive input
        log.info("No command line filters provided, using interactive input")
        log.error("Interactive Inputs not available yet, use command line")
        sys.exit (-1)
        #while not reqVars:
            #reqVars = get_dynamic_inputs()

    # Get cloneable requests using the imported main function
    cloneableRequests = get_requests_main(args=None, return_results=True, reqVars=reqVars)
    ##filter out where approval samAccountName: "samAccountName": "VaronisSystem"


    if cloneableRequests:
        log.info(f"Found {len(cloneableRequests)} requests to clone")
        # TODO: Add cloning logic here
        for request in cloneableRequests:
            log.info(f"Processing request ID: {request.get('id', 'Unknown')}")
            cloneReqVars = {}
            if request.get('status') == "ERROR":
                cloneReqVars['autoApprove'] = True
            elif request.get('status') == "EXPIRED":
                cloneReqVars['autoApprove'] = False
            
            # Extract requestedFor information
            requested_for = request.get('requestedFor', {})
            cloneReqVars['requestedForSamAccountName'] = requested_for.get('samAccountName')
            cloneReqVars['requestedForDomainName'] = requested_for.get('directoryServices', {}).get('name')
            
            cloneReqVars['action'] = request.get('accessAction')
            cloneReqVars['reason'] = f"Clone of request ID: {request.get('id', 'Unknown')}"
            ###There is a SCHEMA ISSUE, we can't fill in the requested entity, this is on hold now 
            
            if request.get('type') in ["DIRECT_PERMISSION", "PERMISSION"]:
                log.error("Permission clone is not supported yet; skipping request.")
                log.warning("Please note, if your permission request had a membership subrequest, it will be picked up")
                """
                # Handle permission-type requests
                # NOT SUPPORTED: permission requests require permissionTypeName, but the request query doesn't return it and schema doesn't support fetching it yet.
                log.info(f"Processing permission request: {request.get('type')}")
                cloneReqVars['EntityID'] = request.get('affectedResource', {}).get('id')
                if cloneReqVars['EntityID'] is not None:
                    try:
                        cloneReqVars['EntityID'] = int(cloneReqVars['EntityID'])
                    except (TypeError, ValueError):
                        log.warning(f"Invalid resourceId value: {cloneReqVars['EntityID']}")
                
                # Build the reqVars for permission_main
                permission_vars = {
                    "resourceId": cloneReqVars['EntityID'],
                    "permissionTypeName": cloneReqVars.get('permissionType'),  # Need to add this earlier
                    "requestedForSamAccountName": cloneReqVars.get('requestedForSamAccountName'),
                    "requestedForDirectoryServicesName": cloneReqVars.get('requestedForDomainName'),
                    "accessAction": cloneReqVars['action'],
                    "reason": cloneReqVars['reason'],
                    "isAutoApprove": cloneReqVars.get('autoApprove', False)
                }
                # Remove None values
                permission_vars = {k: v for k, v in permission_vars.items() if v is not None}
                
                # Call permission_main with the built variables
                log.info(f"Submitting permission request with vars: {json.dumps(permission_vars, indent=2)}")
                result = permission_main(return_results=True, reqVars=permission_vars)
                log.info(f"Permission request result: {result}")
                """
                
            elif request.get('type') in ["MEMBERSHIP"]:
                # Handle membership request types
                log.info(f"Processing {request.get('type')} request")
                cloneReqVars['EntityID'] = request.get('affectedGroup', {}).get('group', {}).get('id')
                if cloneReqVars['EntityID'] is not None:
                    try:
                        cloneReqVars['EntityID'] = int(cloneReqVars['EntityID'])
                    except (TypeError, ValueError):
                        log.warning(f"Invalid groupId value: {cloneReqVars['EntityID']}")
                
                # Build the reqVars for membership_main
                membership_vars = {
                    "groupId": cloneReqVars['EntityID'],
                    "requestedForSamAccountName": cloneReqVars.get('requestedForSamAccountName'),
                    "requestedForDirectoryServicesName": cloneReqVars.get('requestedForDomainName'),
                    "accessAction": cloneReqVars['action'],
                    "reason": cloneReqVars['reason'],
                    "isAutoApprove": cloneReqVars.get('autoApprove', False)
                }
                # Remove None values
                membership_vars = {k: v for k, v in membership_vars.items() if v is not None}
                
                # Call membership_main with the built variables
                log.info(f"Submitting membership request with vars: {json.dumps(membership_vars, indent=2)}")
                result = membership_main(return_results=True, reqVars=membership_vars)
                log.info(f"Membership request result: {result}")

            else:
                log.warning(f"Unexpected request type: {request.get('type')}")
    else:
        log.info("No requests found matching the criteria")


def parse_arguments():
    """
    Parse command line arguments for the get requests script.
    
    Returns:
        argparse.Namespace: Parsed arguments
    """
    parser = argparse.ArgumentParser(
        description='Clone requests that are in error or expired status',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s                                              # Run with interactive prompts for filters
  %(prog)s --status EXPIRED, ERROR                      # Status of requests to clone 
  %(prog)s --daysback 7                                 # How far back to look for requests to clone
  %(prog)s --status ERROR --daysback 7                  # Combine multiple filters
        """
    )
    
    parser.add_argument(
        '--version',
        action='version',
        version='Get Requests Script 1.0'
    )
    
    parser.add_argument(
        '--debugmode_id',
        type=int,
        help='Specific request ID for debugging purposes'
    )
    
    parser.add_argument(
        '--status',
        type=str,
        help='Request status(es), comma-separated. Valid values: ERROR, EXPIRED'
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