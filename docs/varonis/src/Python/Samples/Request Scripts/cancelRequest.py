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

def main(reqId):
    """
    Main function to cancel a governed request.
    
    Args:
        reqId (str): The request ID to cancel
    """
    # Always get credentials from config file
    tenantUrl = tenantinfo.getAndReturnTenant()
    apikey = tenantinfo.getAndReturnAPIKey()
    #end tenant and api validation 

    #generate auth token and graphql client 
    token = authentication.Authenticate (tenantUrl, apikey)
    client = graphQLclient.GraphqlClient(tenantUrl, apikey, token,api_option='dag')
    #end generate token and graphql client 

    #Take the inputs and get valid inputs into a json var ready to send to gql 
    reqVars = {"id": int(reqId)}

    #open the mutation query file and bring it into a var 
    query = helpers.getQueryFile('async_cancelRequest',graphqlfolder)
    #run the query 
    log.debug("Executing GraphQL mutation: async_cancelRequest")
    log.debug(f"GraphQL Query:\n{query}")
    log.debug(f"GraphQL Variables:\n{json.dumps(reqVars, indent=2)}")
    result = client.execute_query (query, reqVars)
    job_id = f"{result['cancelGovernedRequestsAsync']['jobId']}"
    helpers.checkMutation(job_id,client,graphqlfolder)


def parse_arguments():
    """
    Parse command line arguments for the cancel request script.
    
    Returns:
        argparse.Namespace: Parsed arguments
    """
    parser = argparse.ArgumentParser(
        description='Cancel a Varonis DAG governed request',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s 12345              # Cancel request with ID 12345
  %(prog)s --request-id 12345 # Cancel request with ID 12345 using named argument
        """
    )
    
    parser.add_argument(
        'request_id',
        nargs='?',
        help='Request ID to cancel'
    )
    
    parser.add_argument(
        '--request-id',
        dest='request_id_named',
        help='Request ID to cancel (alternative to positional argument)'
    )
    
    parser.add_argument(
        '--version',
        action='version',
        version='Cancel Request Script 1.0'
    )
    
    args = parser.parse_args()
    
    # Use named argument if provided, otherwise use positional
    request_id = args.request_id_named or args.request_id
    
    # Prompt for request ID if not provided
    while not request_id:
        request_id = input("Enter the request ID to cancel: ")
        if not request_id:
            log.error("Request ID is required.")
    
    return request_id


if __name__ == "__main__":
    request_id = parse_arguments()
    main(request_id)