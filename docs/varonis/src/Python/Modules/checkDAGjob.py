# Varonis' sample code(s) are provided on an "as is" and "as available" basis and without any warranty of any kind.  
# Any use of Varonis' sample code(s) is optional at client's sole discretion, responsibility and risk.
# Varonis does not make any commitment with respect to Varonis' sample code(s), their specific functions or their availability, reliability, or ability to meet client's needs.
# Client acknowledges that Varonis may, in its sole discretion, modify, discontinue or update the Varonis' sample code(s) from time to time, without notice and for any reason.

import sys
import os 
from logger import get_logger

log = get_logger(__name__)

graphqlfolder = os.path.abspath(
    os.path.join(os.path.dirname(__file__), '..', '..', 'Config', 'graphql')
)

def checkStatus(vars, client, CheckQueryType, AsyncResultType):
    while True:
        query_path = os.path.join(graphqlfolder, CheckQueryType + '.graphql')

        with open(query_path, 'r') as queryfile:
            query = queryfile.read()
        result = client.execute_query(query, vars)
        statusToCheck = result[f'{AsyncResultType}']["jobStatus"]

        log.debug(statusToCheck)
        if statusToCheck == "PENDING":
            continue
        else:
            return statusToCheck