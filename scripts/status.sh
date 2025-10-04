#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd .. && pwd)"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

clear

echo "=========================================="
echo "  DC Simulator - System Status"
echo "=========================================="
echo ""

# Check Docker containers
echo -e "${BLUE}Docker Containers:${NC}"
if docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -q "bmc"; then
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "NAMES|bmc"
    echo -e "${GREEN}✓ Services running${NC}"
else
    echo -e "${RED}✗ No services running${NC}"
    echo "  Start with: ./start.sh"
fi

echo ""

# Check for Packer
echo -e "${BLUE}Build Tools:${NC}"
if command -v packer &> /dev/null; then
    echo -e "${GREEN}✓ Packer installed:${NC} $(packer version | head -1)"
else
    echo -e "${YELLOW}⚠ Packer not installed${NC}"
fi

if command -v qemu-system-x86_64 &> /dev/null; then
    echo -e "${GREEN}✓ QEMU installed:${NC} $(qemu-system-x86_64 --version | head -1)"
else
    echo -e "${RED}✗ QEMU not installed${NC}"
fi

echo ""

# Check for images
echo -e "${BLUE}Available Images:${NC}"

if [ -f "$SCRIPT_DIR/images/custom/ubuntu-server-airgap.qcow2" ]; then
    SIZE=$(du -h "$SCRIPT_DIR/images/custom/ubuntu-server-airgap.qcow2" | cut -f1)
    echo -e "${GREEN}✓ Custom Packer image:${NC} $SIZE"
else
    echo -e "${YELLOW}⚠ No custom image built${NC}"
    echo "  Build with: ./scripts/build_packer_image.sh"
fi

if [ -d "$SCRIPT_DIR/images/ubuntu/ubuntu-installer" ]; then
    echo -e "${GREEN}✓ Netboot installer files${NC}"
else
    echo -e "${YELLOW}⚠ Netboot files not downloaded${NC}"
    echo "  Download with: ./setup.sh"
fi

echo ""

# Check for VMs
echo -e "${BLUE}Virtual Machines:${NC}"
if [ -d "$SCRIPT_DIR/images/vms" ] && [ "$(ls -A $SCRIPT_DIR/images/vms/*.qcow2 2>/dev/null)" ]; then
    for vm in "$SCRIPT_DIR/images/vms"/*.qcow2; do
        if [ -f "$vm" ]; then
            VM_NAME=$(basename "$vm" .qcow2)
            SIZE=$(du -h "$vm" | cut -f1)
            
            # Check if VM is running
            if [ -f "$SCRIPT_DIR/images/vms/${VM_NAME}.pid" ]; then
                PID=$(cat "$SCRIPT_DIR/images/vms/${VM_NAME}.pid")
                if ps -p "$PID" > /dev/null 2>&1; then
                    echo -e "  ${GREEN}● $VM_NAME${NC} (Running, PID: $PID, Size: $SIZE)"
                else
                    echo -e "  ${YELLOW}○ $VM_NAME${NC} (Stopped, Size: $SIZE)"
                fi
            else
                echo -e "  ${YELLOW}○ $VM_NAME${NC} (Stopped, Size: $SIZE)"
            fi
        fi
    done
else
    echo -e "${YELLOW}⚠ No VMs created${NC}"
    echo "  Create with: python3 src/vm_manager.py create --name ubuntu01"
fi

echo ""

# Check network
echo -e "${BLUE}Network Configuration:${NC}"
if ip addr show br0 &> /dev/null; then
    BR_IP=$(ip addr show br0 | grep "inet " | awk '{print $2}')
    echo -e "${GREEN}✓ Bridge br0:${NC} $BR_IP"
else
    echo -e "${RED}✗ Bridge br0 not found${NC}"
    echo "  Create with: ./setup.sh"
fi

echo ""

# Check PXE files
echo -e "${BLUE}PXE Deployment:${NC}"
if [ -f "$SCRIPT_DIR/pxe-data/http/images/ubuntu-server-airgap.qcow2" ]; then
    SIZE=$(du -h "$SCRIPT_DIR/pxe-data/http/images/ubuntu-server-airgap.qcow2" | cut -f1)
    echo -e "${GREEN}✓ Deployment image ready:${NC} $SIZE"
    echo "  URL: http://192.168.100.1:8080/images/ubuntu-server-airgap.qcow2"
else
    echo -e "${YELLOW}⚠ No deployment image configured${NC}"
    echo "  Setup with: ./scripts/setup_pxe_deployment.sh"
fi

echo ""

# Service endpoints
echo -e "${BLUE}Service Endpoints:${NC}"
if docker ps | grep -q "bmc-openbmc"; then
    echo -e "${GREEN}✓ BMC Redfish API:${NC} http://localhost:5000/redfish/v1/"
    echo -e "${GREEN}✓ BMC SSH:${NC} ssh root@localhost -p 22 (root:root)"
fi

if docker ps | grep -q "bmc-pxe"; then
    echo -e "${GREEN}✓ PXE HTTP Server:${NC} http://localhost:8080/"
    echo -e "${GREEN}✓ TFTP Server:${NC} Port 69"
    echo -e "${GREEN}✓ DHCP Server:${NC} 192.168.100.100-200"
fi

echo ""

# Quick commands
echo -e "${BLUE}Quick Commands:${NC}"
echo "  Start services:    ${CYAN}./start.sh${NC}"
echo "  Stop services:     ${CYAN}./stop.sh${NC}"
echo "  Build image:       ${CYAN}./scripts/build_packer_image.sh${NC}"
echo "  Create VM:         ${CYAN}python3 src/vm_manager.py create --name ubuntu01${NC}"
echo "  Start VM (PXE):    ${CYAN}python3 src/vm_manager.py start --name ubuntu01 --boot pxe${NC}"
echo "  List VMs:          ${CYAN}python3 src/vm_manager.py list${NC}"
echo "  View logs:         ${CYAN}docker logs -f bmc-pxe${NC}"
echo ""
