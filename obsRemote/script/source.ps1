# Define the path to your .env file
$envFile = "..\dev\docker-compose.env"

# Read the .env file and set the environment variables in the current session
Get-Content $envFile | ForEach-Object {
    if ($_ -match '^\s*#') { return }   # Skip comments
    if ($_ -match '^\s*$') { return }   # Skip empty lines
    $name, $value = $_ -split '=', 2    # Split by the first '='
    $envVarName = $name.Trim()
    $envVarValue = $value.Trim()
    [System.Environment]::SetEnvironmentVariable($envVarName, $envVarValue, 'Process')
}

Write-Host "Environment variables loaded into the current session."
