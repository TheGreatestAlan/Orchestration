#!/bin/sh

echo "$(date): Starting certificate renewal check..."

# Check required environment variables
if [ -z "$DOMAINS" ]; then
    echo "ERROR: DOMAINS environment variable is not set"
    exit 1
fi

if [ -z "$CERTBOT_EMAIL" ]; then
    echo "ERROR: CERTBOT_EMAIL environment variable is not set"
    exit 1
fi

echo "Renewing certificates for domains: $DOMAINS"
echo "Using email: $CERTBOT_EMAIL"

# Try to renew certificates
certbot renew \
    --webroot \
    --webroot-path=/var/www/certbot \
    --email "$CERTBOT_EMAIL" \
    --agree-tos \
    --non-interactive \
    --quiet

RENEW_EXIT_CODE=$?

if [ $RENEW_EXIT_CODE -eq 0 ]; then
    echo "$(date): Certificate renewal successful"
else
    echo "$(date): Certificate renewal failed with exit code $RENEW_EXIT_CODE"
    exit $RENEW_EXIT_CODE
fi

echo "$(date): Certificate renewal check completed"
