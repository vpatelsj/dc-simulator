#!/bin/bash

# Stop all Apollo Simulator services

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=========================================="
echo "Stopping Apollo Simulator Services"
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

# Stop all VMs
echo ""
echo "Stopping all VMs..."
if [ -f "config/vms.yaml" ]; then
    for vm in $(python3 -c "import yaml; print(' '.join(yaml.safe_load(open('config/vms.yaml'))['vms'].keys()))" 2>/dev/null); do
        python3 src/vm_manager.py stop --name "$vm" 2>/dev/null || true
    done
fi

# Stop containers
echo ""
echo "Stopping containers..."
$CONTAINER_ENGINE stop bmc-openbmc bmc-pxe 2>/dev/null || true
$CONTAINER_ENGINE rm bmc-openbmc bmc-pxe 2>/dev/null || true

echo ""
echo "All services stopped"
