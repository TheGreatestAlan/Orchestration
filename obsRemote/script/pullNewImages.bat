@echo off
setlocal enabledelayedexpansion

REM Change to the script's directory
cd /d "%~dp0"

REM Define the relative path to the directory containing your .env files
set "ENV_DIR=..\dev"

REM Get the absolute path of the ENV_DIR
for %%i in ("%ENV_DIR%") do set "ABS_ENV_DIR=%%~fi"

REM Define the path to the .env file
set "ENV_FILE=%ABS_ENV_DIR%\docker-compose.env"

REM Load the specified .env file and set environment variables
for /f "usebackq delims=" %%i in ("%ENV_FILE%") do set %%i

REM Set the path to your docker-compose.yml file (one level above)
set "DOCKER_COMPOSE_FILE=..\run_obsidian_remote.yml"

:: Get a list of all images defined in the docker-compose file
for /f "tokens=*" %%i in ('docker-compose -f "%DOCKER_COMPOSE_FILE%" config --images') do (
    set "IMAGE_NAME=%%i"

    REM Get the local image digest
    for /f "tokens=* delims=" %%j in ('docker image inspect --format="{{index .RepoDigests 0}}" "!IMAGE_NAME!" 2^>nul') do (
        set "LOCAL_DIGEST=%%j"
    )

    REM Check if local digest was retrieved
    if not defined LOCAL_DIGEST (
        echo Local image "!IMAGE_NAME!" not found. Pulling image...
        docker pull "!IMAGE_NAME!"
        set "LOCAL_DIGEST=pulled"
    )

    REM Get the remote image digest from Docker Hub using --format to avoid pipe
    for /f "tokens=* delims=" %%k in ('docker manifest inspect --verbose "!IMAGE_NAME!" --format "{{.Descriptor.Digest}}"') do (
        set "REMOTE_DIGEST=%%k"
    )

    REM Remove any prefixes like image name from digests
    for /f "tokens=2 delims=@" %%l in ("!LOCAL_DIGEST!") do set "LOCAL_DIGEST=%%l"
    for /f "tokens=2 delims=@" %%m in ("!REMOTE_DIGEST!") do set "REMOTE_DIGEST=%%m"

    REM Compare the digests
    if "!LOCAL_DIGEST!" neq "!REMOTE_DIGEST!" (
        echo Image "!IMAGE_NAME!" is different from Docker Hub version, updating...

        REM Remove the old local image
        docker rmi "!IMAGE_NAME!" -f

        REM Pull the new image from Docker Hub
        docker pull "!IMAGE_NAME!"
    ) else (
        echo Image "!IMAGE_NAME!" is up to date.
    )
)

:: Optionally clean up unused images
docker image prune -f

endlocal
