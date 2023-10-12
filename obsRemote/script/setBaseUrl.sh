#!/bin/bash

# Get the IP address of the system
IP_ADDRESS=$(hostname -I | awk '{print $1}')

# Check if IP address is non-empty
if [[ -z "$IP_ADDRESS" ]]; then
    echo "Error: Could not retrieve the IP address."
    exit 1
fi

# Set the IP address as an environment variable in /etc/environment
# This may require superuser privileges
echo "ORGANIZER_SERVER_LOCATION=http://$IP_ADDRESS/api" | sudo tee -a /etc/environment > /dev/null
echo "WEB_BASE_URL=http://$IP_ADDRESS/web" | sudo tee -a /etc/environment > /dev/null

# Inform the user
echo "BASE_URL has been set to http://$IP_ADDRESS and added to /etc/environment"

# Optionally: Export the variable immediately for use in the current session
export ORGANIZER_SERVER_LOCATION="http://$IP_ADDRESS/api"
export WEB_BASE_URL="http://$IP_ADDRESS/web"
