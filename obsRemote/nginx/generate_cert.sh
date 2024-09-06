#!/bin/bash

# Define the SSL directory where the certificate and key will be stored
SSL_DIR="/etc/nginx/ssl"

# Create the directory if it doesn't exist
mkdir -p "$SSL_DIR"

# Generate a self-signed SSL certificate and private key
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout "$SSL_DIR/selfsigned.key" \
    -out "$SSL_DIR/selfsigned.crt" \
    -subj "/C=US/ST=State/L=City/O=Organization/OU=Unit/CN=localhost"

# Optionally, generate a Diffie-Hellman group for better security
openssl dhparam -out "$SSL_DIR/dhparam.pem" 2048

# Provide feedback to the user
echo "Self-signed SSL certificate and private key generated in $SSL_DIR"
echo "Diffie-Hellman parameters generated in $SSL_DIR"

# Reminder: Copy the SSL files into the appropriate directory in the Docker image.
