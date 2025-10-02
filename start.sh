#!/bin/bash

# Start all Apollo Simulator services

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=========================================="
echo "Starting Apollo Simulator Services"
echo "=========================================="

# Detect container engine
if command -v docker &> /dev/null; then
    CONTAINER_ENGINE="docker"
elif command -v podman &> /dev/null; then
    CONTAINER_ENGINE="podman"
else
    echo "Error: Neither Docker nor Podman found"
    exit 1
fi

echo "Using: $CONTAINER_ENGINE"

# Build OpenBMC container
echo ""
echo "Building OpenBMC container..."
cd containers/openbmc
$CONTAINER_ENGINE build -t apollo-openbmc .
cd "$SCRIPT_DIR"

# Build PXE server container
echo ""
echo "Building PXE server container..."
cd containers/pxe-server
$CONTAINER_ENGINE build -t apollo-pxe .
cd "$SCRIPT_DIR"

# Create network if it doesn't exist
echo ""
echo "Setting up container network..."
if ! $CONTAINER_ENGINE network inspect bmc-net &> /dev/null; then
    $CONTAINER_ENGINE network create \
        --driver bridge \
        --subnet 192.168.100.0/24 \
        --gateway 192.168.100.1 \
        bmc-net
    echo "Created network: bmc-net"
else
    echo "Network already exists: bmc-net"
fi

# Clean up any existing containers
echo ""
echo "Cleaning up old containers..."
$CONTAINER_ENGINE rm -f bmc-openbmc bmc-pxe 2>/dev/null || true

# Start OpenBMC container
echo ""
echo "Starting OpenBMC container..."
# Note: Using host networking due to WSL2 port forwarding issues
# This means BMC services are directly on host network
$CONTAINER_ENGINE run -d \
    --name bmc-openbmc \
    --network host \
    -v "$SCRIPT_DIR/logs:/var/log/openbmc" \
    apollo-openbmc

echo "OpenBMC started at:"
echo "  - Redfish API: http://localhost:5000/redfish/v1/"
echo "  - SSH: ssh root@localhost -p 22 (password: root)"
echo "  - IPMI: ipmitool -I lanplus -H localhost -U admin -P admin"

# Start PXE server container
echo ""
echo "Starting PXE server container..."

# Copy netboot files to container volume location
mkdir -p "$SCRIPT_DIR/pxe-data/tftp"
mkdir -p "$SCRIPT_DIR/pxe-data/http"

if [ -d "$SCRIPT_DIR/images/ubuntu" ]; then
    echo "Copying PXE boot files..."
    cp -r "$SCRIPT_DIR/images/ubuntu/." "$SCRIPT_DIR/pxe-data/tftp/"
fi

$CONTAINER_ENGINE run -d \
    --name bmc-pxe \
    --network bmc-net \
    -p 8080:80 \
    -p 69:69/udp \
    -p 67:67/udp \
    --cap-add NET_ADMIN \
    -v "$SCRIPT_DIR/pxe-data/tftp:/tftp" \
    -v "$SCRIPT_DIR/pxe-data/http:/var/www/html/ubuntu" \
    apollo-pxe

echo "PXE Server started at:"
echo "  - HTTP: http://localhost:8080/"
echo "  - TFTP: localhost:69"

# Create bridge for VMs if it doesn't exist
echo ""
echo "Setting up VM network bridge..."
if ! ip link show br0 &> /dev/null; then
    sudo ip link add name br0 type bridge
    sudo ip addr add 192.168.100.254/24 dev br0
    sudo ip link set br0 up
    echo "Created bridge: br0"
else
    echo "Bridge already exists: br0"
fi

# Connect container network to bridge
# Note: This may require additional configuration depending on your setup

echo ""
echo "=========================================="
echo "All services started successfully!"
echo "=========================================="
echo ""
echo "Next steps:"
echo "1. Create a VM:"
echo "   python3 src/vm_manager.py create --name ubuntu01 --memory 2048 --cpus 2"
echo ""
echo "2. Start VM with PXE boot:"
echo "   python3 src/vm_manager.py start --name ubuntu01 --boot pxe"
echo ""
echo "3. List VMs:"
echo "   python3 src/vm_manager.py list"
echo ""
echo "4. View logs:"
echo "   $CONTAINER_ENGINE logs bmc-openbmc"
echo "   $CONTAINER_ENGINE logs bmc-pxe"
echo ""
