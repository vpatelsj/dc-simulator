#!/bin/bash

# DC Simulator - Complete Cleanup Script
# Stops all services, kills VMs, and cleans up resources

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=========================================="
echo "DC Simulator - Complete Cleanup"
echo "=========================================="

# Detect container engine
if command -v docker &> /dev/null; then
    CONTAINER_ENGINE="docker"
elif command -v podman &> /dev/null; then
    CONTAINER_ENGINE="podman"
else
    echo -e "${RED}Error: Neither Docker nor Podman found${NC}"
    exit 1
fi

echo -e "\n${YELLOW}Using: $CONTAINER_ENGINE${NC}"

# Function to stop all QEMU VMs
stop_all_vms() {
    echo -e "\n${YELLOW}Stopping all QEMU VMs...${NC}"
    
    # Stop VMs managed by vm_manager.py
    if [ -f "config/vms.yaml" ]; then
        echo "Stopping managed VMs..."
        if command -v python3 &> /dev/null && [ -f "src/vm_manager.py" ]; then
            for vm in $(python3 -c "import yaml; vms = yaml.safe_load(open('config/vms.yaml')).get('vms', {}); print(' '.join(vms.keys()))" 2>/dev/null || echo ""); do
                if [ -n "$vm" ]; then
                    echo "  Stopping VM: $vm"
                    python3 src/vm_manager.py stop --name "$vm" 2>/dev/null || echo "    (VM was not running)"
                fi
            done
        fi
    fi
    
    # Kill any remaining QEMU processes
    echo "Checking for stray QEMU processes..."
    QEMU_PIDS=$(ps aux | grep qemu-system | grep -v grep | awk '{print $2}' || true)
    if [ -n "$QEMU_PIDS" ]; then
        echo -e "${YELLOW}Found running QEMU processes, killing them...${NC}"
        for pid in $QEMU_PIDS; do
            echo "  Killing PID: $pid"
            kill -9 $pid 2>/dev/null || true
        done
    else
        echo "  No stray QEMU processes found"
    fi
    
    # Clean up PID files
    if [ -d "images/vms" ]; then
        echo "Cleaning up VM PID files..."
        rm -f images/vms/*.pid 2>/dev/null || true
    fi
    
    echo -e "${GREEN}✓ All VMs stopped${NC}"
}

# Function to stop and remove containers
stop_containers() {
    echo -e "\n${YELLOW}Stopping and removing containers...${NC}"
    
    # Stop containers
    if $CONTAINER_ENGINE ps -a | grep -E "bmc-openbmc|bmc-pxe" > /dev/null 2>&1; then
        echo "Stopping containers..."
        $CONTAINER_ENGINE stop bmc-openbmc bmc-pxe 2>/dev/null || true
        echo "Removing containers..."
        $CONTAINER_ENGINE rm bmc-openbmc bmc-pxe 2>/dev/null || true
    else
        echo "  No DC Simulator containers running"
    fi
    
    echo -e "${GREEN}✓ Containers stopped and removed${NC}"
}

# Function to clean up network resources
cleanup_network() {
    echo -e "\n${YELLOW}Cleaning up network resources...${NC}"
    
    # Clean up tap interfaces
    echo "Checking for tap interfaces..."
    TAP_INTERFACES=$(ip link show type tun 2>/dev/null | grep -o 'tap[0-9]*' || true)
    if [ -n "$TAP_INTERFACES" ]; then
        echo -e "${YELLOW}Found tap interfaces, attempting to remove...${NC}"
        for tap in $TAP_INTERFACES; do
            echo "  Removing $tap"
            sudo ip link delete $tap 2>/dev/null || echo "    (Could not remove $tap, may require manual cleanup)"
        done
    else
        echo "  No tap interfaces found"
    fi
    
    echo -e "${GREEN}✓ Network cleanup complete${NC}"
}

# Function to clean up temporary files
cleanup_files() {
    echo -e "\n${YELLOW}Cleaning up temporary files...${NC}"
    
    # Clean up log files (optional - ask user)
    if [ -d "logs" ] && [ "$(ls -A logs 2>/dev/null)" ]; then
        echo "Found log files in logs/ directory"
        read -p "Do you want to clean up log files? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo "Cleaning logs..."
            rm -f logs/*.log 2>/dev/null || true
            echo -e "${GREEN}✓ Logs cleaned${NC}"
        else
            echo "Keeping log files"
        fi
    fi
    
    # Clean up PXE data (runtime files)
    if [ -d "pxe-data" ]; then
        echo "Cleaning up PXE runtime data..."
        # Don't delete the netboot files, just runtime data
        find pxe-data/http -type f -not -name '.gitkeep' -delete 2>/dev/null || true
        echo -e "${GREEN}✓ PXE data cleaned${NC}"
    fi
    
    # Ask about cleaning Ubuntu netboot files
    if [ -d "images/ubuntu" ] && [ "$(ls -A images/ubuntu 2>/dev/null)" ]; then
        echo "Found Ubuntu netboot files (~60MB)"
        read -p "Do you want to clean up Ubuntu netboot files? (will need re-download) (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo "Cleaning Ubuntu netboot files..."
            rm -rf images/ubuntu/* 2>/dev/null || true
            echo -e "${GREEN}✓ Ubuntu netboot files removed${NC}"
            echo -e "${YELLOW}Note: Run 'make setup' or 'make setup-pxe' to re-download${NC}"
        else
            echo "Keeping Ubuntu netboot files"
        fi
    fi
    
    echo -e "${GREEN}✓ Temporary files cleaned${NC}"
}

# Function to show cleanup summary
show_summary() {
    echo -e "\n=========================================="
    echo -e "${GREEN}Cleanup Complete!${NC}"
    echo "=========================================="
    echo ""
    echo "Summary:"
    echo "  ✓ All VMs stopped and processes killed"
    echo "  ✓ Containers stopped and removed"
    echo "  ✓ Network resources cleaned"
    echo "  ✓ Temporary files cleaned"
    echo ""
    echo "Note: The following are preserved:"
    echo "  • VM disk images (images/vms/*.qcow2)"
    echo "  • Ubuntu netboot files (images/ubuntu/)"
    echo "  • Configuration files (config/)"
    echo "  • Python virtual environment (venv/)"
    echo ""
    echo "To completely reset, run: make clean-all"
    echo ""
}

# Main execution
main() {
    stop_all_vms
    stop_containers
    cleanup_network
    cleanup_files
    show_summary
}

# Run main function
main
