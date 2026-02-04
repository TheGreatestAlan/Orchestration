#!/bin/bash

# Vaultwarden Monitoring Script
# Checks if Vaultwarden is healthy and running

CONTAINER_NAME="vaultwarden"
HEALTH_URL="http://localhost:8080/alive"
LOG_FILE="./logs/monitor.log"

# Create logs directory
mkdir -p ./logs

# Get timestamp
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Check if container is running
if ! docker ps --format "table {{.Names}}" | grep -q "$CONTAINER_NAME"; then
    STATUS="❌ Container not running"
    EXIT_CODE=1
else
    # Check container health
    HEALTH=$(docker inspect --format='{{.State.Health.Status}}' "$CONTAINER_NAME" 2>/dev/null)

    # Check if responding to requests
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$HEALTH_URL" 2>/dev/null)

    if [ "$HTTP_CODE" = "200" ]; then
        if [ "$HEALTH" = "healthy" ]; then
            STATUS="✅ Healthy and responding"
            EXIT_CODE=0
        else
            STATUS="⚠️  Responding but not healthy ($HEALTH)"
            EXIT_CODE=1
        fi
    else
        STATUS="❌ Not responding (HTTP $HTTP_CODE)"
        EXIT_CODE=1
    fi
fi

# Log status
echo "[$TIMESTAMP] $STATUS" | tee -a "$LOG_FILE"

# Optional: Send alert if unhealthy (configure webhook)
if [ $EXIT_CODE -ne 0 ] && [ -n "$ALERT_WEBHOOK" ]; then
    curl -X POST -H "Content-Type: application/json" \
         -d "{\"text\":\"Vaultwarden Alert: $STATUS\"}" \
         "$ALERT_WEBHOOK" 2>/dev/null
fi

exit $EXIT_CODE