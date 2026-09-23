# Varonis' sample code(s) are provided on an "as is" and "as available" basis and without any warranty of any kind.  
# Any use of Varonis' sample code(s) is optional at client's sole discretion, responsibility and risk.
# Varonis does not make any commitment with respect to Varonis' sample code(s), their specific functions or their availability, reliability, or ability to meet client's needs.
# Client acknowledges that Varonis may, in its sole discretion, modify, discontinue or update the Varonis' sample code(s) from time to time, without notice and for any reason.

import os
import json
import time
from logger import get_logger

log = get_logger(__name__)


def getQueryFile(queryType, graphqlfolder):
    """
    Reads the content of a GraphQL query file from the specified folder.

    :param queryType: Name of the GraphQL file (without .graphql extension)
    :param graphqlfolder: Path to the folder containing .graphql files
    :return: Contents of the .graphql file as a string
    :raises FileNotFoundError: If the file does not exist
    """
    query_path = os.path.join(graphqlfolder, f'{queryType}.graphql')
    log.debug(f"Attempting to load GraphQL file: {query_path}")

    try:
        with open(query_path, 'r') as queryfile:
            query = queryfile.read()
        log.debug("Successfully loaded query file.")
        return query
    except FileNotFoundError:
        log.error(f"Query file not found: {query_path}")
        raise


def checkMutation(jobId, client, graphqlfolder, return_results=False):
    """
    Polls a mutation job until it completes, then logs the results.

    :param jobId: The job ID to track
    :param client: GraphQL client to execute queries
    :param graphqlfolder: Folder containing the result query file
    :param return_results: If True, returns the results instead of just logging them
    :return: Mutation results if return_results=True, otherwise None
    """
    log.info(f"Polling mutation job until completion: {jobId}")
    query = getQueryFile('result_submitRequest', graphqlfolder)
    reqVars = {"id": jobId}
    status = 'pending'
    sleepTime = 10

    while status != 'COMPLETED':
        try:
            result = client.execute_query(query, reqVars)
            status = result['governedRequestMutationJob']['jobStatus']
            if status != 'COMPLETED':
                log.info(f"Job still in progress. Waiting {sleepTime} seconds...")
                time.sleep(sleepTime)
        except Exception as e:
            log.exception(f"Error while polling mutation job {jobId}")
            raise

    printableResult = result['governedRequestMutationJob']['results']
    log.info("Mutation job completed. Result:")
    log.info(json.dumps(printableResult, indent=2))
    
    # Return results if requested
    if return_results:
        return printableResult
    return None


def checkQueryAsync(jobId, client, graphqlfolder, return_results=False):
    """
    Polls a query job until it completes, then logs the results.

    :param jobId: The job ID to track
    :param client: GraphQL client to execute queries
    :param graphqlfolder: Folder containing the result query file
    :param return_results: If True, returns the results instead of just logging them
    :return: Query results if return_results=True, otherwise None
    """
    log.info(f"Polling query job until completion: {jobId}")
    query = getQueryFile('queryjob_getRequesys', graphqlfolder)
    reqVars = {"id": jobId}
    status = 'pending'
    sleepTime = 10

    while status != 'COMPLETED':
        try:
            result = client.execute_query(query, reqVars)
            status = result['governedRequestsQueryJob']['jobStatus']
            if status != 'COMPLETED':
                log.info(f"Job still in progress. Waiting {sleepTime} seconds...")
                time.sleep(sleepTime)
        except Exception as e:
            log.exception(f"Error while polling query job {jobId}")
            raise

    printableResult = result['governedRequestsQueryJob']['results']
    log.info("Query job completed. Result:")
    log.info(json.dumps(printableResult, indent=2))
    
    # Return results if requested
    if return_results:
        return printableResult
    return None
