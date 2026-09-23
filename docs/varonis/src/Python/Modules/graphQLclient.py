# Varonis' sample code(s) are provided on an "as is" and "as available" basis and without any warranty of any kind.  
# Any use of Varonis' sample code(s) is optional at client's sole discretion, responsibility and risk.
# Varonis does not make any commitment with respect to Varonis' sample code(s), their specific functions or their availability, reliability, or ability to meet client's needs.
# Client acknowledges that Varonis may, in its sole discretion, modify, discontinue or update the Varonis' sample code(s) from time to time, without notice and for any reason.

import requests
import warnings
import json
import authentication
from logger import get_logger

log = get_logger(__name__)

# Custom warning handler to redirect SSL warnings to our logger
def custom_warning_handler(message, category, filename, lineno, file=None, line=None):
    if 'Unverified HTTPS request' in str(message):
        log.debug(f"SSL verification disabled: {message}")
    else:
        # For non-SSL warnings, use default behavior
        original_showwarning(message, category, filename, lineno, file, line)

# Store original warning handler and set our custom one
original_showwarning = warnings.showwarning
warnings.showwarning = custom_warning_handler


class GraphqlClient:
    """
    GraphQL client for the Varonis API.

    Handles both standard and DAG API endpoints, manages authentication, and provides a method
    for executing GraphQL queries and mutations with automatic token refresh on failure.
    """

    def __init__(self, origin, apikey, auth_token=None, api_option="default"):
        """
        Initializes the GraphQL client.

        :param origin: Base URL of the Varonis tenant (e.g., https://mytenant.varonis.io)
        :param apikey: Varonis API key
        :param auth_token: Optional pre-obtained auth token
        :param api_option: 'dag' or 'default' to control the endpoint path
        """
        if not api_option or api_option.lower() == "default":
            graphql_path = "/api/graphql"
        elif api_option.lower() == "dag":
            graphql_path = "/api/graphql"
        else:
            graphql_path = "/api/graphql"

        self.url = origin.rstrip('/') + graphql_path
        self.origin = origin
        self.apikey = apikey
        self.auth_token = auth_token

        log.info(f"GraphQL client initialized with endpoint: {self.url}")

    def execute_query(self, query, variables=None):
        """
        Executes a GraphQL query or mutation with automatic retry on auth failure.

        :param query: The GraphQL query string
        :param variables: Optional dictionary of GraphQL variables
        :return: The 'data' portion of the response
        """
        headers = {
            'Authorization': f'Bearer {self.auth_token}',
            'Content-Type': 'application/json'
        }
        body = {
            'query': query,
            'variables': variables if variables is not None else {}
        }

        log.debug(f"Sending GraphQL query to {self.url}")

        try:
            response = requests.post(self.url, headers=headers, json=body, verify=False)
            log.debug(f"SSL verification disabled for request to {self.url}")
            
            response.raise_for_status()
            data = response.json().get('data')

            if not data:
                log.warning("Response JSON did not contain 'data'. Full response: %s", response.text)

            return data

        except requests.exceptions.HTTPError as e:
            if response.status_code in (401, 403):
                log.warning(f"Token may have expired. Refreshing token and retrying request.")
                self.auth_token = authentication.Authenticate(self.origin, self.apikey)
                headers['Authorization'] = f'Bearer {self.auth_token}'

                try:
                    response = requests.post(self.url, headers=headers, json=body, verify=False)
                    log.debug(f"SSL verification disabled for retry request to {self.url}")
                    
                    response.raise_for_status()
                    data = response.json().get('data')
                    return data
                except Exception as retry_error:
                    log.exception("Retry after token refresh failed.")
                    raise Exception(f"Retry failed: {retry_error}")
            else:
                log.exception("HTTP error during GraphQL query execution.")
                raise Exception(f"GraphQL query execution failed: {e}")
        except Exception as ex:
            log.exception("Unexpected error during GraphQL query.")
            raise Exception(f"GraphQL query execution failed: {ex}")
