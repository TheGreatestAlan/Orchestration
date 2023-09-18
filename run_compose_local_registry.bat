@echo off

REM Check and prompt for REGISTRY_LOCATION if not set
if not defined REGISTRY_LOCATION (
    set /p REGISTRY_LOCATION="Enter the REGISTRY_LOCATION: "
)

REM Check and prompt for VAULT_LOCATION if not set
if not defined VAULT_LOCATION (
    set /p VAULT_LOCATION="Enter the VAULT_LOCATION: "
)

REM Check and prompt for ORGANIZER_SERVER_PORT if not set
if not defined ORGANIZER_SERVER_PORT (
    set /p ORGANIZER_SERVER_PORT="Enter the ORGANIZER_SERVER_PORT: "
)

REM Set default value for ORGANIZER_SERVER_LOCATION
set ORGANIZER_SERVER_LOCATION=http://localhost:%ORGANIZER_SERVER_PORT%

REM Check for flags and set ORGANIZER_SERVER_LOCATION accordingly
if "%1"=="local" (
    REM Default value is already set
) else if "%1"=="internal" (
    REM Get the internal IP address using ipconfig and findstr
    for /f "tokens=2 delims=:" %%a in ('ipconfig ^| findstr /I "IPv4 Address"') do set ip=%%a
    set ORGANIZER_SERVER_LOCATION=http://%ip%:%ORGANIZER_SERVER_PORT%
) else if "%1"=="external" (
    set /p ip="Enter the external url: "
    set ORGANIZER_SERVER_LOCATION=%ip%
)

REM Run docker-compose up
docker compose up
