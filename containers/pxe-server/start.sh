#!/bin/bash

echo "Starting PXE Boot Server..."

# Start nginx
echo "Starting nginx..."
service nginx start

# Start dnsmasq
echo "Starting dnsmasq (DHCP/TFTP)..."
dnsmasq --no-daemon --log-queries --log-dhcp

# Keep container running
tail -f /var/log/nginx/access.log /var/log/nginx/error.log
