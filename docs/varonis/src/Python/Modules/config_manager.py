# Varonis' sample code(s) are provided on an "as is" and "as available" basis and without any warranty of any kind.  
# Any use of Varonis' sample code(s) is optional at client's sole discretion, responsibility and risk.
# Varonis does not make any commitment with respect to Varonis' sample code(s), their specific functions or their availability, reliability, or ability to meet client's needs.
# Client acknowledges that Varonis may, in its sole discretion, modify, discontinue or update the Varonis' sample code(s) from time to time, without notice and for any reason.

"""
Configuration module for reading tenant and API settings from config.json
"""
import os
import json
from logger import get_logger

log = get_logger(__name__)

class ConfigManager:
    def __init__(self):
        self.config_path = self._get_config_path()
        self.config_data = None
        self._load_config()
    
    def _get_config_path(self):
        """Get the path to the config.json file"""
        # Get the path relative to this module's location
        current_dir = os.path.dirname(os.path.abspath(__file__))
        config_path = os.path.abspath(os.path.join(current_dir, '..', '..', 'Config', 'config.json'))
        return config_path
    
    def _load_config(self):
        """Load configuration from config.json file"""
        try:
            if not os.path.exists(self.config_path):
                log.error(f"Configuration file not found: {self.config_path}")
                log.error("Please create config.json with your tenant URL and API key")
                raise FileNotFoundError(f"Configuration file not found: {self.config_path}")
            
            with open(self.config_path, 'r', encoding='utf-8-sig') as f:
                self.config_data = json.load(f)
            
            log.debug(f"Configuration loaded successfully from: {self.config_path}")
            
        except json.JSONDecodeError as e:
            log.error(f"Invalid JSON in configuration file: {e}")
            raise
        except Exception as e:
            log.error(f"Error loading configuration: {e}")
            raise
    
    def get_tenant_url(self):
        """Get tenant URL from configuration"""
        if not self.config_data:
            raise ValueError("Configuration not loaded")
        
        url = self.config_data.get('tenant', {}).get('url')
        if not url or url == "https://your-tenant.varonis.io":
            log.error("Tenant URL not configured. Please update config.json with your actual tenant URL")
            raise ValueError("Tenant URL not configured in config.json")
        
        log.debug("Tenant URL retrieved from configuration")
        return url
    
    def get_api_key(self):
        """Get API key from configuration"""
        if not self.config_data:
            raise ValueError("Configuration not loaded")
        
        api_key = self.config_data.get('tenant', {}).get('apiKey')
        if not api_key or api_key == "your-api-key-here":
            log.error("API key not configured. Please update config.json with your actual API key")
            raise ValueError("API key not configured in config.json")
        
        log.debug("API key retrieved from configuration")
        return api_key
    
    def reload_config(self):
        """Reload configuration from file"""
        log.info("Reloading configuration")
        self._load_config()

# Global configuration instance
_config_manager = None

def get_config_manager():
    """Get the global configuration manager instance"""
    global _config_manager
    if _config_manager is None:
        _config_manager = ConfigManager()
    return _config_manager

def get_tenant_url():
    """Convenience function to get tenant URL"""
    return get_config_manager().get_tenant_url()

def get_api_key():
    """Convenience function to get API key"""
    return get_config_manager().get_api_key()
