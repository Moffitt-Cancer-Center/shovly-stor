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
import checkDAGjob
from logger import get_logger

log = get_logger(__name__)

graphqlfolder = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..', 'Config', 'graphql'))



def governedScalable(url,apikey,client,CheckStatusType,AsyncQueryType,AsyncResultType,ResultQueryType,ResultsQueryCheckType):
    query_path = os.path.join(graphqlfolder, AsyncQueryType + '.graphql')
    
    with open(query_path, 'r') as queryfile:
        query = queryfile.read()
    log.debug(f"Executing GraphQL query: {AsyncQueryType}")
    log.debug(f"GraphQL Query:\n{query}")
    log.debug(f"GraphQL Variables:\n{json.dumps({}, indent=2)}")
    result = client.execute_query (query)

    job_id = result[f'{AsyncResultType}']["jobId"]
    vars = {'id': job_id}

    checkStatus = checkDAGjob.checkStatus(vars, client,CheckStatusType,ResultsQueryCheckType)

    if checkStatus == "FAILED":
        log.error(checkStatus)
        sys.exit(-1)
    else: 
        query_path = os.path.join(graphqlfolder, ResultQueryType + '.graphql')
    
        with open(query_path, 'r') as queryfile:
            query = queryfile.read()
        log.debug(f"Executing GraphQL query: {ResultQueryType}")
        log.debug(f"GraphQL Query:\n{query}")
        log.debug(f"GraphQL Variables:\n{json.dumps(vars, indent=2)}")
        result = client.execute_query (query,vars)
        return json.dumps(result,indent=4)

def main(query):
    """
    Main function to execute the script.
    
    This function retrieves tenant information from config and executes the query.
    """
    queryresults = ""
    
    # Always get credentials from config file
    tenantUrl = tenantinfo.getAndReturnTenant()
    apikey = tenantinfo.getAndReturnAPIKey()

    token = authentication.Authenticate (tenantUrl, apikey)
    client = graphQLclient.GraphqlClient(tenantUrl, apikey, token,api_option='dag')
    if query == "Groups" or query == "All":
        log.info("Groups")
        AsyncQueryType = "async_getDAGgroups"
        AsyncResultsType = "governedGroupsAsync"
        ResultsQueryCheckType = "governedGroupsQueryJob"
        ResultQueryType = "queryjob_GovernedGroups"
        CheckStatusType = "CheckStatus_GoverenedGroups"
        queryresults += governedScalable (tenantUrl, apikey,client,CheckStatusType,AsyncQueryType,AsyncResultsType,ResultQueryType,ResultsQueryCheckType)
    if query == "GovernedFolders" or query == "All":
        log.info("Governed Folders")
        AsyncQueryType = "async_getManagedFolders"
        AsyncResultsType = "governedResourcesAsync"
        ResultsQueryCheckType = "governedResourcesQueryJob"
        ResultQueryType = "queryjob_governedresources"
        CheckStatusType = "CheckStatus_GoverenedResources"
        queryresults += governedScalable (tenantUrl, apikey,client,CheckStatusType,AsyncQueryType,AsyncResultsType,ResultQueryType,ResultsQueryCheckType)
    
    if query == "RootResources" or query == "All":
        log.info("Root Resources")
        AsyncQueryType = "async_getBaseFolders"
        AsyncResultsType = "governedResourcesAsync"
        ResultsQueryCheckType = "governedResourcesQueryJob"
        ResultQueryType = "queryjob_governedresources"
        CheckStatusType = "CheckStatus_GoverenedResources"
        queryresults += governedScalable (tenantUrl, apikey,client,CheckStatusType,AsyncQueryType,AsyncResultsType,ResultQueryType,ResultsQueryCheckType)
    log.info (queryresults)
    

def parse_arguments():
    """
    Parse command line arguments for the DAG query script.
    
    Returns:
        argparse.Namespace: Parsed arguments
    """
    parser = argparse.ArgumentParser(
        description='Query Varonis DAG API for groups, governed folders, and root resources',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s                    # Query all data types (Groups, GovernedFolders, RootResources)
  %(prog)s Groups             # Query only Groups
  %(prog)s RootResources      # Query only Root Resources
  %(prog)s GovernedFolders    # Query only Governed Folders
        """
    )
    
    parser.add_argument(
        'query_type',
        nargs='?',
        default='All',
        choices=['All', 'Groups', 'GovernedFolders', 'RootResources'],
        help='Type of data to query (default: All)'
    )
    
    parser.add_argument(
        '--version',
        action='version',
        version='DAG Query Script 1.0'
    )
    
    return parser.parse_args()


if __name__ == "__main__":
    args = parse_arguments()
    main(args.query_type)