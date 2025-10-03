#!/bin/bash

# Start all DC Simulator services

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=========================================="
echo "Starting DC Simulator Services"
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
$CONTAINER_ENGINE build -t dc-openbmc .
cd "$SCRIPT_DIR"

# Build PXE server container
echo ""
echo "Building PXE server container..."
cd containers/pxe-server
$CONTAINER_ENGINE build -t dc-pxe .
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
    dc-openbmc

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

# Use host network so PXE server can serve DHCP on the bridge interface
$CONTAINER_ENGINE run -d \
    --name bmc-pxe \
    --network host \
    --cap-add NET_ADMIN \
    -v "$SCRIPT_DIR/pxe-data/tftp:/tftp" \
    -v "$SCRIPT_DIR/pxe-data/http:/var/www/html/ubuntu" \
    dc-pxe

echo "PXE Server started at:"
echo "  - HTTP: http://localhost:8080/"
echo "  - TFTP: localhost:69"

# Create bridge for VMs if it doesn't exist
echo ""
echo "Setting up VM network bridge..."
if ! ip link show br0 &> /dev/null; then
    sudo ip link add name br0 type bridge
    sudo ip addr add 192.168.100.1/24 dev br0
    sudo ip link set br0 up
    echo "Created bridge: br0"
else
    echo "Bridge already exists: br0"
fi

# Setup NAT and forwarding for VM internet access
echo "Configuring VM internet access..."
MAIN_IFACE=$(ip route | grep default | awk '{print $5}' | head -n 1)

if [ -n "$MAIN_IFACE" ]; then
    # Add NAT rule if not exists
    if ! sudo iptables -t nat -C POSTROUTING -s 192.168.100.0/24 -o "$MAIN_IFACE" -j MASQUERADE 2>/dev/null; then
        sudo iptables -t nat -A POSTROUTING -s 192.168.100.0/24 -o "$MAIN_IFACE" -j MASQUERADE
        echo "  Added NAT rule"
    fi
    
    # Add forwarding rules if not exists
    if ! sudo iptables -C FORWARD -i br0 -o "$MAIN_IFACE" -j ACCEPT 2>/dev/null; then
        sudo iptables -A FORWARD -i br0 -o "$MAIN_IFACE" -j ACCEPT
    fi
    
    if ! sudo iptables -C FORWARD -i "$MAIN_IFACE" -o br0 -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null; then
        sudo iptables -A FORWARD -i "$MAIN_IFACE" -o br0 -m state --state RELATED,ESTABLISHED -j ACCEPT
    fi
    
    # Disable bridge netfilter
    sudo sysctl -w net.bridge.bridge-nf-call-iptables=0 >/dev/null 2>&1 || true
    sudo sysctl -w net.bridge.bridge-nf-call-ip6tables=0 >/dev/null 2>&1 || true
    
    echo "  VM internet access configured via $MAIN_IFACE"
else
    echo "  Warning: Could not detect main network interface"
fi

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
