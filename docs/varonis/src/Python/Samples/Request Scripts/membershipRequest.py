# Varonis' sample code(s) are provided on an "as is" and "as available" basis and without any warranty of any kind.  
# Any use of Varonis' sample code(s) is optional at client's sole discretion, responsibility and risk.
# Varonis does not make any commitment with respect to Varonis' sample code(s), their specific functions or their availability, reliability, or ability to meet client's needs.
# Client acknowledges that Varonis may, in its sole discretion, modify, discontinue or update the Varonis' sample code(s) from time to time, without notice and for any reason.

import sys
import os 
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

def parse_arguments():
    """Parse command-line arguments for membership request fields"""
    parser = argparse.ArgumentParser(description='Submit a membership request to DAG')
    
    # Required arguments (URL and API key)
    parser.add_argument('url', nargs='?', help='Tenant URL')
    parser.add_argument('apikey', nargs='?', help='API Key')
    
    # Optional membership request fields
    parser.add_argument('--group', help='Group in format domain\\accountname')
    parser.add_argument('--user', help='User in format domain\\accountname')
    parser.add_argument('--groupId',type=int, help='Group ID, should only be used by other scripts')
    parser.add_argument('--action', choices=['grant', 'revoke', 'Grant', 'Revoke'], 
                       help='Access action (grant or revoke)')
    parser.add_argument('--reason', help='Reason for the request')
    parser.add_argument('--auto-approve', action='store_true', 
                       help='Auto-approve the request')
    parser.add_argument('--expiration-date', 
                       help='Expiration date (YYYY-MM-DDTHH:MM:SS or DD/MM/YYYY)')
    parser.add_argument('--activation-date', 
                       help='Activation date (YYYY-MM-DDTHH:MM:SS or DD/MM/YYYY)')
    parser.add_argument('--expiration-days', type=int, 
                       help='Expiration days interval (positive integer)')
    
    return parser.parse_args()

def validate_and_parse_date(date_str, field_name):
    """Validate and parse date string to ISO format"""
    if not date_str:
        return None
    
    try:
        import datetime
        # Try ISO format first
        try:
            return datetime.datetime.fromisoformat(date_str).isoformat() + "Z"
        except Exception:
            # Try DD/MM/YYYY
            return datetime.datetime.strptime(date_str, "%d/%m/%Y").isoformat() + "Z"
    except Exception:
        log.error(f"Invalid {field_name} format. Please use ISO 8601 (YYYY-MM-DDTHH:MM:SS) or DD/MM/YYYY.")
        return None

def parse_domain_account(domain_account_str, field_name):
    """Parse domain\\account string and return domain and account separately"""
    if not domain_account_str:
        return None, None
    
    if "\\" not in domain_account_str:
        log.error(f"Invalid {field_name} format. Please use domain\\accountname.")
        return None, None
    
    domain, account = domain_account_str.split("\\", 1)
    domain = domain.strip()
    account = account.strip()
    
    if not domain or not account:
        log.error(f"Invalid {field_name} format. Both domain and account name are required.")
        return None, None
    
    return domain, account

def handleInputs(args=None):
    """
    Handle inputs either from command line arguments or interactive prompts
    """
    log.info('Gathering inputs')
    
    # Flag to determine if we're in command-line mode (all required args provided)
    command_line_mode = False
    
    # Initialize variables from args if provided
    if args:
        # Parse group information
        groupDomainName, groupAccountName = parse_domain_account(args.group, "group")
        groupId = args.groupId
        # Parse user information  
        requesteeDomainName, requesteeAccountName = parse_domain_account(args.user, "user")
        # Get other fields from args
        accessAction = args.action
        reason = args.reason
        isAutoApprove = args.auto_approve if args.auto_approve else False  # Default to False instead of None
        expirationDate = validate_and_parse_date(args.expiration_date, "expiration date") if args.expiration_date else None
        activationDate = validate_and_parse_date(args.activation_date, "activation date") if args.activation_date else None
        expirationDaysInterval = args.expiration_days if args.expiration_days else None
        
        # Check if we have all required fields from command line
        hasGroupinfo = bool((groupDomainName and groupAccountName) or groupId)
        if (hasGroupinfo and requesteeDomainName and 
            requesteeAccountName and accessAction and reason):
            command_line_mode = True
    else:
        # Initialize all as None for interactive mode
        groupAccountName = groupDomainName = None
        requesteeAccountName = requesteeDomainName = groupId = None
        accessAction = reason = None
        isAutoApprove = expirationDate = activationDate = expirationDaysInterval = None
    
    # Interactive prompts for missing required fields
    if not ((groupAccountName and groupDomainName) or groupId):
        while not groupAccountName or not groupDomainName:
            group_input = input(r"Group (domain\sam account name): ").strip()
            if "\\" in group_input:
                groupDomainName, groupAccountName = group_input.split("\\", 1)
                groupDomainName = groupDomainName.strip()
                groupAccountName = groupAccountName.strip()
                if groupDomainName and groupAccountName:
                    break
                else:
                    log.error("Invalid format. Both domain and account name are required.")
            else:
                log.error("Invalid format. Please use domain\\accountname.")
    
    while not requesteeAccountName or not requesteeDomainName:
        requestee_input = input(r"User (domain\sam account name): ").strip()
        if "\\" in requestee_input:
            requesteeDomainName, requesteeAccountName = requestee_input.split("\\", 1)
            requesteeDomainName = requesteeDomainName.strip()
            requesteeAccountName = requesteeAccountName.strip()
            if requesteeDomainName and requesteeAccountName:
                break
            else:
                log.error("Invalid format. Both domain and account name are required.")
        else:
            log.error("Invalid format. Please use domain\\accountname.")
    
    if not accessAction:
        accessAction = input(r"Access Action (Grant or revoke): ").strip()
    while accessAction.title() not in ('Grant', 'Revoke'):
        log.error('invalid input')
        accessAction = input(r"Access Action (Grant or revoke): ").strip()
    
    while not reason:
        reason = input(r"Reason: ").strip()
        if not reason:
            log.error("Reason is required and cannot be empty.")

    # isAutoApprove (optional, Boolean) - only prompt if not in command-line mode
    if not command_line_mode and isAutoApprove is None:
        while True:
            auto_input = input(r"Auto Approve? (yes/no, optional): ").strip().lower()
            if auto_input in ['yes', 'true', 'y', '1']:
                isAutoApprove = True
                break
            elif auto_input in ['no', 'false', 'n', '0', '']:
                isAutoApprove = False
                break
            else:
                log.error("Invalid input. Please enter yes, no, or leave blank.")

    # expirationDate (optional, DateTime ISO 8601, DD/MM/YYYY allowed) - only prompt if not in command-line mode
    if not command_line_mode and expirationDate is None and expirationDaysInterval is None:
        while True:
            exp_input = input(r"Expiration Date (YYYY-MM-DDTHH:MM:SS or DD/MM/YYYY, optional): ").strip()
            if not exp_input:
                # If no expiration date, ask for interval
                while True:
                    interval_input = input(r"Expiration Days Interval (positive integer, optional): ").strip()
                    if not interval_input:
                        break
                    if interval_input.isdigit() and int(interval_input) > 0:
                        expirationDaysInterval = int(interval_input)
                        break
                    else:
                        log.error("Invalid input. Please enter a positive integer or leave blank.")
                break
            else:
                expirationDate = validate_and_parse_date(exp_input, "expiration date")
                if expirationDate:
                    break

    # activationDate (optional, DateTime ISO 8601, DD/MM/YYYY allowed) - only prompt if not in command-line mode
    if not command_line_mode and activationDate is None:
        while True:
            act_input = input(r"Activation Date (YYYY-MM-DDTHH:MM:SS or DD/MM/YYYY, optional): ").strip()
            if not act_input:
                activationDate = None
                break
            else:
                activationDate = validate_and_parse_date(act_input, "activation date")
                if activationDate:
                    break

    reqVars = {
        "groupAccountName": groupAccountName,
        "groupDomainName": groupDomainName,
        "groupId": groupId,
        "requestedForSamAccountName": requesteeAccountName,
        "requestedForDirectoryServicesName": requesteeDomainName,
        "accessAction": accessAction.upper(),
        "reason": reason,
        "isAutoApprove": isAutoApprove,
        "expirationDate": expirationDate,
        "activationDate": activationDate,
        "expirationDaysInterval": expirationDaysInterval
    }
    # Remove keys with None values
    reqVars = {k: v for k, v in reqVars.items() if v is not None}
    print(reqVars)
    return reqVars



def main(return_results=False, reqVars=None):
    """
    Main function
    
    Args:
        return_results: If True, returns the results instead of just logging them
        reqVars: Pre-built request variables dict (optional, overrides args/interactive input)
        
    Returns:
        Mutation results if return_results=True, otherwise None
    """
    # If reqVars is provided, skip command-line argument parsing
    if reqVars is None:
        # Parse command-line arguments only when reqVars not provided
        args = parse_arguments()
        
        url = args.url
        apikey = args.apikey
        
        # First validate group specification if any group arguments are provided
        if args.group and args.groupId:
            log.error("Cannot specify both --group and --groupId. Please use only one.")
            sys.exit(1)
        
        # Check if all required fields are provided via command line
        hasGroupinfo = bool(args.group or args.groupId)
        all_required_provided = (
            hasGroupinfo and args.user and args.action and args.reason
        )
        
        if all_required_provided:
            log.info("All required fields provided via command line arguments")
            # Validate the provided arguments
            requesteeDomainName, requesteeAccountName = parse_domain_account(args.user, "user")
            
            if not (requesteeDomainName and requesteeAccountName):
                log.error("Invalid user format in command line arguments")
                sys.exit(1)
            
            # Validate group information if --group is provided
            if args.group:
                groupDomainName, groupAccountName = parse_domain_account(args.group, "group")
                if not (groupDomainName and groupAccountName):
                    log.error("Invalid group format in command line arguments")
                    sys.exit(1)
            
            if args.action.title() not in ('Grant', 'Revoke'):
                log.error("Invalid access action. Must be 'grant' or 'revoke'")
                sys.exit(1)
                
        elif any([args.group, args.groupId, args.user, args.action, args.reason]):
            log.error("When providing request fields via command line, all required fields must be provided: either --group OR --groupId, plus --user, --action, and --reason")
            sys.exit(1)
    else:
        # reqVars provided - skip argument parsing
        log.info("Using provided reqVars, skipping command-line argument parsing")
        args = None
        url = None
        apikey = None
        all_required_provided = False

    # Handle tenant URL and API key - try config first, then command line, then prompts
    if not url and not apikey:
        # Try to get both from config file
        if tenantinfo.hasValidConfiguration():
            log.info("Using credentials from configuration file")
            tenantUrl, apikey = tenantinfo.getConfiguredCredentials()
        else:
            log.info("Configuration not available or invalid, prompting for credentials")
            tenantUrl = tenantinfo.getAndReturnTenant()
            apikey = tenantinfo.getAndReturnAPIKey()
    else:
        # Handle individual parameters
        if not url:
            tenantUrl = tenantinfo.getAndReturnTenant()
        else: 
            while True:
                check = tenantinfo.validateTenantURl(url)
                if check:
                    tenantUrl = url
                    break
                else:
                    log.error ('Invalid URL')
                    tenantUrl = tenantinfo.getAndReturnTenant()
            
        if not apikey:
            apikey = tenantinfo.getAndReturnAPIKey()
        else:
            while True:
                check = tenantinfo.validateAPIKey(apikey)
                if check: 
                    apikey = apikey
                    break 
                else: 
                    log.error ('Invalid API Key')
                    apikey = tenantinfo.getAndReturnAPIKey()

    #generate auth token and graphql client 
    token = authentication.Authenticate (tenantUrl, apikey)
    client = graphQLclient.GraphqlClient(tenantUrl, apikey, token,api_option='dag')
    #end generate token and graphql client 

    #Take the inputs and get valid inputs into a json var ready to send to gql 
    # Use provided reqVars, or get them from args/interactive input
    if reqVars is None:
        if all_required_provided:
            # Use command line arguments
            reqVars = handleInputs(args)
        else:
            # Use interactive mode
            reqVars = handleInputs()
    else:
        log.info("Using provided reqVars for membership request")
        log.info(f"Request variables: {json.dumps(reqVars, indent=2)}")

    #open the mutation query file and bring it into a var 
    query = helpers.getQueryFile('async_submitMembershipRequest',graphqlfolder)
    #run the query 
    log.debug("Executing GraphQL mutation: async_submitMembershipRequest")
    log.debug(f"GraphQL Query:\n{query}")
    log.debug(f"GraphQL Variables:\n{json.dumps(reqVars, indent=2)}")
    result = client.execute_query (query, reqVars)
    job_id = f"{result['createGovernedMembershipRequestsAsync']['jobId']}"
    
    # Return results if requested, otherwise just log them
    return helpers.checkMutation(job_id, client, graphqlfolder, return_results=return_results)

if __name__ == "__main__":
    main()