@echo off

REM Pull the official Docker registry image
docker pull registry:2
REM Run the Docker registry
docker run -d -p 5000:5000 --name local-registry --restart=always registry:2
REM Print a message to indicate the registry is running
echo Local Docker registry is now running on port 5000.
