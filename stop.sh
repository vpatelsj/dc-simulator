#!/bin/bash

# DEPRECATED: This script is for legacy Docker-based setup
# Please use the new native systemd-based approach:
#
#   make stop     # Stop all services
#
# Or directly:
#   python3 src/service_manager.py stop

echo "=========================================="
echo "DEPRECATED: Docker-based stop.sh"
echo "=========================================="
echo ""
echo "This script uses Docker and is no longer maintained."
echo ""
echo "Please use the new native systemd approach:"
echo "  make stop    # Stop all services"
echo ""
echo "Exiting..."
exit 1

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
