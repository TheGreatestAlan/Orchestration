#!/bin/bash

# Check and prompt for REGISTRY_LOCATION if not set
if [ -z "$REGISTRY_LOCATION" ]; then
    read -p "Enter the REGISTRY_LOCATION: " REGISTRY_LOCATION
    export REGISTRY_LOCATION
fi

# Check and prompt for VAULT_LOCATION if not set
if [ -z "$VAULT_LOCATION" ]; then
    read -p "Enter the VAULT_LOCATION: " VAULT_LOCATION
    export VAULT_LOCATION
fi

# Check and prompt for ORGANIZER_SERVER_PORT if not set
if [ -z "$ORGANIZER_SERVER_PORT" ]; then
    read -p "Enter the ORGANIZER_SERVER_PORT: " ORGANIZER_SERVER_PORT
    export ORGANIZER_SERVER_PORT
fi

# Set default value for ORGANIZER_SERVER_LOCATION
ORGANIZER_SERVER_LOCATION="http://localhost:$ORGANIZER_SERVER_PORT"
export ORGANIZER_SERVER_LOCATION

# Check for flags and set ORGANIZER_SERVER_LOCATION accordingly
if [ "$1" == "local" ]; then
    # Default value is already set
    :
elif [ "$1" == "internal" ]; then
    # Get the internal IP address
    ip=$(hostname -I | awk '{print $1}')
    ORGANIZER_SERVER_LOCATION="http://$ip:$ORGANIZER_SERVER_PORT"
    export ORGANIZER_SERVER_LOCATION
elif [ "$1" == "external" ]; then
    read -p "Enter the external url: " ip
    ORGANIZER_SERVER_LOCATION="$ip"
    export ORGANIZER_SERVER_LOCATION
fi

# Run docker-compose up
docker compose up
