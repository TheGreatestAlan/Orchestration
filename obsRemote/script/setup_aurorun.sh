#!/bin/bash

# Get the directory of the current script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME="setEnvAndRun.sh"
FULL_SCRIPT_PATH="$SCRIPT_DIR/$SCRIPT_NAME"
SERVICE_PATH="/etc/systemd/system/dockercompose.service"

# Check if the script exists
if [ ! -f "$FULL_SCRIPT_PATH" ]; then
	    echo "Error: Script $FULL_SCRIPT_PATH not found!"
	        exit 1
fi

# Create the systemd service file
echo "Creating systemd service at $SERVICE_PATH"
sudo tee $SERVICE_PATH > /dev/null <<EOF
[Unit]
Description=Run my custom startup script
After=network.target

[Service]
Type=simple
ExecStart=$FULL_SCRIPT_PATH
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# Make the script executable
echo "Making the script executable"
sudo chmod +x "$FULL_SCRIPT_PATH"

# Reload systemd to recognize the new service
echo "Reloading systemd daemon"
sudo systemctl daemon-reload

# Enable the service to run on startup
echo "Enabling the service to start on boot"
sudo systemctl enable dockercompose.service

# Optional: Start the service immediately
echo "Starting the service"

# Optional: Start the service immediately
echo "Starting the service"
sudo systemctl start dockercompose.service

echo "Setup complete. The script $SCRIPT_NAME will run on startup!"
