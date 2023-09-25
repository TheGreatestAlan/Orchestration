#!/bin/bash

# Set the REGISTRY_LOCATION environment variable
export REGISTRY_LOCATION="192.168.1.26:5000"

# Set the VAULT_LOCATION environment variable
export VAULT_LOCATION="/home/bi/Documents/SyncedVault/Organizer"

# Set the ORGANIZER_SERVER_PORT environment variable
export ORGANIZER_SERVER_PORT="8081"

# Set the WEB_PORT environment variable
export WEB_PORT="41960"


"$(dirname "$0")"/run_compose_local_registry.sh "$1"
