@echo off

REM Set the image name and tag for DockerHub
SET IMAGE_NAME=happydance/nginx:latest

REM Set the path to your Dockerfile directory (adjust if necessary)
SET DOCKERFILE_PATH=.

REM Build the Docker image
echo Building the Docker image...
docker build -t nginx:latest %DOCKERFILE_PATH%

REM Tag the image for DockerHub
echo Tagging the Docker image as %IMAGE_NAME%...
docker tag nginx:latest %IMAGE_NAME%

REM DockerHub login (this assumes you've already logged in or will be prompted)
docker login

REM Push the image to DockerHub
echo Pushing the image to DockerHub...
docker push %IMAGE_NAME%

REM Print a success message
echo Image %IMAGE_NAME% has been successfully built and pushed to DockerHub.

