@echo off

REM Check if the service name is provided as a parameter
if "%1"=="" (
    echo Please provide a service name.
    exit /b 1
)

REM Define the relative path to the directory containing your .env files
set "ENV_DIR=..\dev"

REM Get the absolute path of the ENV_DIR
for %%i in ("%ENV_DIR%") do set ABS_ENV_DIR=%%~fi

REM Define the path to the .env file provided as the first argument
set ENV_FILE=%ABS_ENV_DIR%\docker-compose.env

REM Change to the directory where the docker-compose.yml is located (one level above)
cd ..

REM Load the specified .env file and set environment variables
for /f "usebackq delims=" %%i in ("%ENV_FILE%") do set %%i


REM Run Docker Compose
docker-compose -f run_obsidian.yaml exec %1 /bin/bash
