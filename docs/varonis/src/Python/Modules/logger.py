# Varonis' sample code(s) are provided on an "as is" and "as available" basis and without any warranty of any kind.  
# Any use of Varonis' sample code(s) is optional at client's sole discretion, responsibility and risk.
# Varonis does not make any commitment with respect to Varonis' sample code(s), their specific functions or their availability, reliability, or ability to meet client's needs.
# Client acknowledges that Varonis may, in its sole discretion, modify, discontinue or update the Varonis' sample code(s) from time to time, without notice and for any reason.

import logging
import os
import inspect
from datetime import datetime
from logging.handlers import RotatingFileHandler

# Global variable to store the log file path for consistency across all loggers
_log_file_path = None

def get_logger(name: str = __name__):
    global _log_file_path
    logger = logging.getLogger(name)

    if not logger.handlers:
        logger.setLevel(logging.DEBUG)  # Capture all levels internally

        # Ensure logs directory exists
        logs_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'logs'))
        os.makedirs(logs_dir, exist_ok=True)
        
        # Only determine the log file path once for all loggers
        if _log_file_path is None:
            # Get the main script name from the call stack
            frame = inspect.currentframe()
            script_name = 'unknown'
            try:
                # Go up the call stack to find the main script (__main__)
                if frame and frame.f_back:
                    caller_frame = frame.f_back
                    main_filename = None
                    
                    # First, look for the __main__ module in the call stack
                    while caller_frame:
                        filename = caller_frame.f_code.co_filename
                        if filename.endswith('.py') and not filename.endswith('logger.py'):
                            # Check if this frame belongs to __main__
                            frame_globals = caller_frame.f_globals
                            if frame_globals.get('__name__') == '__main__':
                                main_filename = filename
                                break
                        caller_frame = caller_frame.f_back
                    
                    # If we found the main script, use it
                    if main_filename:
                        script_name = os.path.splitext(os.path.basename(main_filename))[0]
                    else:
                        # Fallback: use the topmost Python file that's not logger.py
                        caller_frame = frame.f_back
                        while caller_frame:
                            filename = caller_frame.f_code.co_filename
                            if filename.endswith('.py') and not filename.endswith('logger.py'):
                                script_name = os.path.splitext(os.path.basename(filename))[0]
                                break
                            caller_frame = caller_frame.f_back
            finally:
                del frame
            
            # Create log filename with script name, current date and time
            current_datetime = datetime.now().strftime('%Y%m%d_%H%M%S')
            log_filename = f"{script_name}_{current_datetime}.log"
            _log_file_path = os.path.join(logs_dir, log_filename)

        log_path = _log_file_path

        # Formatter for both handlers
        formatter = logging.Formatter(
            '%(asctime)s - %(levelname)s - %(name)s - %(message)s'
        )

        # Console Handler (INFO+ only)
        console_handler = logging.StreamHandler()
        console_handler.setLevel(logging.INFO)
        console_handler.setFormatter(formatter)

        # File Handler (DEBUG+ with rotation)
        file_handler = RotatingFileHandler(log_path, maxBytes=2_000_000, backupCount=5)
        file_handler.setLevel(logging.DEBUG)
        file_handler.setFormatter(formatter)

        # Attach handlers
        logger.addHandler(console_handler)
        logger.addHandler(file_handler)

    return logger
