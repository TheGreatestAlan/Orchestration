# Use the official Nginx image
FROM jc21/nginx-proxy-manager:latest


# Set up the SSL directory
RUN mkdir -p /etc/nginx/ssl

# Copy the self-signed SSL generation script into the container
COPY generate_cert.sh /usr/local/bin/generate_cert.sh

# Make the script executable
RUN chmod +x /usr/local/bin/generate_cert.sh

# Run the script to generate SSL certificates and the Diffie-Hellman group
RUN /usr/local/bin/generate_cert.sh

