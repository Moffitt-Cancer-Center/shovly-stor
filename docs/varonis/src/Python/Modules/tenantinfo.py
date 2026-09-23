# Varonis' sample code(s) are provided on an "as is" and "as available" basis and without any warranty of any kind.  
# Any use of Varonis' sample code(s) is optional at client's sole discretion, responsibility and risk.
# Varonis does not make any commitment with respect to Varonis' sample code(s), their specific functions or their availability, reliability, or ability to meet client's needs.
# Client acknowledges that Varonis may, in its sole discretion, modify, discontinue or update the Varonis' sample code(s) from time to time, without notice and for any reason.

import re
from logger import get_logger

log = get_logger(__name__)

# Import config manager, but handle gracefully if it fails
try:
    from config_manager import get_tenant_url, get_api_key
    CONFIG_AVAILABLE = True
    log.debug("Configuration manager loaded successfully")
except ImportError as e:
    CONFIG_AVAILABLE = False
    log.debug(f"Configuration manager not available: {e}")


def getTenantInfo():
    """
    Prompts the user to enter the tenant URL.

    :return: Tenant URL string
    """
    tenant = input("Enter tenant url: ")
    return tenant


def validateTenantURl(tenanturl):
    """
    Validates the provided tenant URL against Varonis format.

    :param tenanturl: Tenant URL to validate
    :return: Match object if valid, else None
    """
    if not tenanturl:
        return None
    validation = re.search(r"^https://\w.*\.(varonis\.io|varonis-preprod\.com)/?$", tenanturl)
    log.debug(f"Tenant URL validation result for '{tenanturl}': {bool(validation)}")
    return validation


def getAndReturnTenant():
    """
    Gets tenant URL from config file first, then prompts user if not available or invalid.

    :return: Validated tenant URL
    """
    # Try to get from config file first
    if CONFIG_AVAILABLE:
        try:
            config_url = get_tenant_url()
            if validateTenantURl(config_url):
                log.info("Using tenant URL from configuration file")
                return config_url
            else:
                log.warning("Tenant URL from config file is invalid, prompting user")
        except Exception as e:
            log.warning(f"Could not read tenant URL from config: {e}")
    
    # Fall back to user input
    while True:
        tenant_info = getTenantInfo()
        log.debug(f"User entered tenant URL: {tenant_info}")
        if validateTenantURl(tenant_info):
            log.debug("Valid tenant URL received.")
            return tenant_info
        else:
            log.warning("Invalid tenant URL entered. Prompting again.")
            print('Invalid URL, try again')


def getAPIKey():
    """
    Prompts the user to enter the API key.

    :return: API key string
    """
    apiKey = input("Provide API Key: ")
    return apiKey


def validateAPIKey(apikey):
    """
    Validates the provided API key format.

    :param apikey: API key string
    :return: Match object if valid, else None
    """
    validation = re.search(r"^vkey1_.*", apikey)
    log.debug(f"API key validation result for '{apikey}': {bool(validation)}")
    return validation


def getAndReturnAPIKey():
    """
    Gets API key from config file first, then prompts user if not available or invalid.

    :return: Validated API key
    """
    # Try to get from config file first
    if CONFIG_AVAILABLE:
        try:
            config_api_key = get_api_key()
            if validateAPIKey(config_api_key):
                log.info("Using API key from configuration file")
                return config_api_key
            else:
                log.warning("API key from config file is invalid, prompting user")
        except Exception as e:
            log.warning(f"Could not read API key from config: {e}")
    
    # Fall back to user input
    while True:
        apikey = getAPIKey()
        log.debug(f"User entered API key: {apikey[:10]}********")  # Mask sensitive output
        if validateAPIKey(apikey):
            log.debug("Valid API key received.")
            return apikey
        else:
            log.warning("Invalid API key entered. Prompting again.")


def getConfiguredCredentials():
    """
    Get both tenant URL and API key from configuration file.
    
    :return: Tuple of (tenant_url, api_key) or (None, None) if config not available
    """
    if not CONFIG_AVAILABLE:
        log.debug("Configuration manager not available")
        return None, None
    
    try:
        tenant_url = get_tenant_url()
        api_key = get_api_key()
        
        # Validate both values
        if validateTenantURl(tenant_url) and validateAPIKey(api_key):
            log.info("Successfully retrieved valid credentials from configuration file")
            return tenant_url, api_key
        else:
            log.warning("Credentials from config file failed validation")
            return None, None
            
    except Exception as e:
        log.warning(f"Error reading credentials from config: {e}")
        return None, None


def hasValidConfiguration():
    """
    Check if valid configuration is available.
    
    :return: Boolean indicating if valid config credentials are available
    """
    tenant_url, api_key = getConfiguredCredentials()
    return tenant_url is not None and api_key is not None


def provideValidation(url, apikey):
    """
    Validates and (if needed) re-prompts the user for tenant URL and API key.

    :param url: Optional preset tenant URL
    :param apikey: Optional preset API key
    :return: Tuple of (validated tenant URL, validated API key)
    """
    while not validateTenantURl(url):
        log.warning(f"Provided tenant URL '{url}' is invalid.")
        print('Invalid URL')
        url = getAndReturnTenant()

    while not validateAPIKey(apikey):
        log.warning("Provided API key is invalid.")
        print('Invalid API Key')
        apikey = getAndReturnAPIKey()

    return url, apikey
