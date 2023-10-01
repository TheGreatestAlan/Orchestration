#!/bin/bash

# Get the directory of the currently executing script
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Move one level up from the script directory
PARENT_DIR="$(dirname "$DIR")"

# Change to the parent directory
cd "$PARENT_DIR" || exit 1

# Run docker-compose with the specified file
docker compose -f run_obsidian_remote.yml up 

# Print the working directory and the docker-compose command
echo "Running docker-compose in $PARENT_DIR with file run_obsidian_remote.yml"

