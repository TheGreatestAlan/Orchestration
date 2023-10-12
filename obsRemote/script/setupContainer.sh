#!/bin/bash
set -e  # Exit if any command fails

# Check if correct number of arguments is provided
if [ "$#" -ne 5 ]; then
    echo "Error: Missing arguments."
    echo "Usage: ${BASH_SOURCE[0]} [username] [password] [GUSERNAME] [GPASSWORD] [GTOKEN]"
    exit 1
fi

# Get values from arguments
username="$1"
password="$2"
GUSERNAME="$3"
GPASSWORD="$4"
GTOKEN="$5"

# Validate arguments
if [ -z "$username" ] || [ -z "$password" ] || [ -z "$GUSERNAME" ] || [ -z "$GPASSWORD" ] || [ -z "$GTOKEN" ]; then
    echo "Error: All arguments must be non-empty."
    echo "Usage: ${BASH_SOURCE[0]} [username] [password] [GUSERNAME] [GPASSWORD] [GTOKEN]"
    exit 1
fi

# Change to one directory above the script location
cd "$(dirname "${BASH_SOURCE[0]}")/.."
echo "Creating .htpasswd in $(pwd)"  # Debug: Confirm directory

# Generate .htpasswd file
echo "${username}:$(openssl passwd -apr1 "${password}")" > .htpasswd

echo ".htpasswd created successfully."

# Define the paths
OBSIDIAN_VAULTS="$HOME/obsidian/vaults"
OBSIDIAN_CONFIG="$HOME/obsidian/config"
ORGANIZER_VAULT="$OBSIDIAN_VAULTS/SyncedVault"
OUTPUT_PATH="$HOME/outputpath"

# Write to /etc/environment
echo "OBSIDIAN_VAULTS=$OBSIDIAN_VAULTS" | sudo tee -a /etc/environment
echo "OBSIDIAN_CONFIG=$OBSIDIAN_CONFIG" | sudo tee -a /etc/environment
echo "ORGANIZER_VAULT=$ORGANIZER_VAULT" | sudo tee -a /etc/environment
echo "GUSERNAME=$GUSERNAME"  | sudo tee -a /etc/environment
echo "GPASSWORD=$GPASSWORD"  | sudo tee -a /etc/environment
echo "GTOKEN=$GTOKEN"  | sudo tee -a /etc/environment
echo "OUTPUT_PATH=$OUTPUT_PATH"  | sudo tee -a /etc/environment

echo "Environment variables set successfully."

# Get the directory where the script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check if run.sh is already in crontab
if ! crontab -l | grep -q "run.sh"; then
    # If not, add it
    (crontab -l 2>/dev/null; echo "@reboot ${SCRIPT_DIR}/run.sh") | crontab -
    echo "run.sh added to crontab"
else
    echo "run.sh is already in crontab"
fi

bash "$(dirname "$BASH_SOURCE")/setBaseUrl.sh"
