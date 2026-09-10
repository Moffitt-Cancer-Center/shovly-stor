#!/bin/bash
# Executes the storage summary utility on interactive SSH login

# Put this script in /etc/profile.d/show_storage.sh

# Only execute if the shell is interactive (prevents breaking SCP/rsync)
if [[ $- == *i* ]]; then
    CLI_SCRIPT="/usr/local/bin/user_storage_cli.py"
    
    # Ensure the script exists and is executable to prevent login failures
    if [[ -x "$CLI_SCRIPT" ]]; then
        # Run the Python script, passing the current username, with a timeout 
        # to guarantee the login process is never permanently hung
        timeout 2s python3 "$CLI_SCRIPT" "$USER" 2>/dev/null
        echo "" # Add a blank line for visual spacing before the shell prompt
    fi
fi