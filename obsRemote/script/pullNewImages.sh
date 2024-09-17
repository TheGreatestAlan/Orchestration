#!/bin/bash

set -e  # Exit immediately if a command exits with a non-zero status
set -o pipefail  # Pipelines fail if any command fails

# Change to the script's directory
cd "$(dirname "$0")"

# Define the relative path to the directory containing your .env files
ENV_DIR="../dev"

# Get the absolute path of the ENV_DIR
ABS_ENV_DIR=$(realpath "$ENV_DIR")

# Define the path to the .env file
ENV_FILE="$ABS_ENV_DIR/docker-compose.env"

# Load the specified .env file and set environment variables
export $(grep -v '^#' "$ENV_FILE" | xargs)

# Define the path to your docker-compose.yml file (one level above)
DOCKER_COMPOSE_FILE="../run_obsidian_remote.yml"

# Get a list of all images defined in the docker-compose file
IMAGES=$(docker compose -f "$DOCKER_COMPOSE_FILE" config --images)

for IMAGE_NAME in $IMAGES; do
    echo "Processing image: $IMAGE_NAME"

    # Get the local image digest
    LOCAL_DIGEST=$(docker image inspect --format="{{index .RepoDigests 0}}" "$IMAGE_NAME" 2>/dev/null || echo "")

    if [ -z "$LOCAL_DIGEST" ]; then
        echo "Local image $IMAGE_NAME not found. Pulling image..."
        docker pull "$IMAGE_NAME"
        LOCAL_DIGEST="pulled"
    fi

    # Get the remote image digest from Docker Hub
    REMOTE_DIGEST=$(docker manifest inspect --verbose "$IMAGE_NAME" 2>/dev/null | grep -oP '"digest": "\K[^"]+')

    # Strip any prefixes from digests (in case of image name)
    LOCAL_DIGEST=${LOCAL_DIGEST#*@}
    REMOTE_DIGEST=${REMOTE_DIGEST#*@}

    # Compare the digests
    if [ "$LOCAL_DIGEST" != "$REMOTE_DIGEST" ]; then
        echo "Image $IMAGE_NAME is different from Docker Hub version, updating..."

        # Remove the old local image
        docker rmi "$IMAGE_NAME" -f

        # Pull the new image from Docker Hub
        docker pull "$IMAGE_NAME"
    else
        echo "Image $IMAGE_NAME is up to date."
    fi
done

# Optionally clean up unused images
docker image prune -f
