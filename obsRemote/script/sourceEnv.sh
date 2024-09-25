#!/bin/bash

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Define the relative path to the directory containing your .env files
ENV_DIR="$SCRIPT_DIR/../dev"

# Resolve the absolute path of the ENV_DIR
ABS_ENV_DIR=$(cd "$ENV_DIR"; pwd)

# Define the path to the .env file
ENV_FILE="$ABS_ENV_DIR/docker-compose.env"

# Change to the directory where the docker-compose.yml is located (one level above the script)
cd "$SCRIPT_DIR/.."

# Load the specified .env file and export environment variables
if [ -f "$ENV_FILE" ]; then
  echo "Sourcing the .env file: $ENV_FILE"

  # Enable export of variables in the .env file
  set -o allexport
  source "$ENV_FILE"
  set +o allexport

  # Print the variables to verify
  echo "AGENT_SERVER_REST_ADDRESS: $AGENT_SERVER_REST_ADDRESS"
else
  echo ".env file not found: $ENV_FILE"
  exit 1
fi
