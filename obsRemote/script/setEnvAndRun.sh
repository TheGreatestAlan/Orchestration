#!/bin/bash

# Define the relative path to the directory containing your .env files
ENV_DIR="../dev"

# Resolve the absolute path of the ENV_DIR
ABS_ENV_DIR=$(cd "$ENV_DIR"; pwd)

# Define the path to the .env file
ENV_FILE="$ABS_ENV_DIR/docker-compose.env"

# Change to the directory where the docker-compose.yml is located (one level above)
cd ..

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
fi

# Define the maximum wait time (60 seconds) and sleep interval (5 seconds)
MAX_WAIT=60
SLEEP_INTERVAL=5
WAIT_TIME=0

# Check if Docker Compose is available and retry if not
while ! docker compose version >/dev/null 2>&1; do
  echo "Docker Compose not found, waiting for it to become available..."
  sleep $SLEEP_INTERVAL
  WAIT_TIME=$((WAIT_TIME + SLEEP_INTERVAL))

  if [ "$WAIT_TIME" -ge "$MAX_WAIT" ]; then
    echo "Docker Compose did not become available after $MAX_WAIT seconds. Exiting..."
    exit 1
  fi
done

# Run Docker Compose
echo "Docker Compose is available, starting..."
docker compose -f run_obsidian_remote.yml pull
docker compose -f run_obsidian_remote.yml up --build
