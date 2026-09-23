# Varonis' sample code(s) are provided on an "as is" and "as available" basis and without any warranty of any kind.  
# Any use of Varonis' sample code(s) is optional at client's sole discretion, responsibility and risk.
# Varonis does not make any commitment with respect to Varonis' sample code(s), their specific functions or their availability, reliability, or ability to meet client's needs.
# Client acknowledges that Varonis may, in its sole discretion, modify, discontinue or update the Varonis' sample code(s) from time to time, without notice and for any reason.

import requests
import warnings
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

def Authenticate(tenanturl, apikey):
    """
    Authenticates with the Varonis API using the provided tenant URL and API key.
    Returns the access token if successful, raises an exception otherwise.
    """
    url = tenanturl.rstrip('/') + '/api/authentication/api_keys/token'
    headers = {
        'x-api-key': apikey,
        'Content-Type': 'application/x-www-form-urlencoded',
        'Accept': 'application/json'
    }
    data = {'grant_type': 'varonis_custom'}

    log.info(f"Attempting to authenticate with URL: {url}")

    try:
        response = requests.post(url, headers=headers, data=data, verify=False)
        response.raise_for_status()
        token = response.json().get('access_token')

        if not token:
            log.error("Authentication response received but no access_token found.")
            raise Exception('No access_token found in response')

        log.info("Authentication succeeded.")
        return token

    except Exception as e:
        log.exception("Authentication failed.")
        raise Exception(f"Authentication failed: {e}")
