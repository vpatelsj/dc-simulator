#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

clear

echo "=========================================="
echo "  Air-Gapped PXE Deployment Pipeline"
echo "=========================================="
echo ""
echo "This script will:"
echo "  1. Download Ubuntu ISO (if needed)"
echo "  2. Build custom image with Packer"
echo "  3. Setup PXE deployment infrastructure"
echo "  4. Start services"
echo ""
echo "Estimated total time: 20-30 minutes"
echo ""

read -p "Continue? (y/n) " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

# Check prerequisites
echo ""
echo -e "${BLUE}Checking prerequisites...${NC}"

MISSING_DEPS=()

if ! command -v packer &> /dev/null; then
    MISSING_DEPS+=("packer")
fi

if ! command -v qemu-system-x86_64 &> /dev/null; then
    MISSING_DEPS+=("qemu-system-x86")
fi

if ! command -v qemu-img &> /dev/null; then
    MISSING_DEPS+=("qemu-utils")
fi

if ! command -v docker &> /dev/null; then
    MISSING_DEPS+=("docker")
fi

if [ ${#MISSING_DEPS[@]} -ne 0 ]; then
    echo -e "${RED}Missing dependencies:${NC}"
    for dep in "${MISSING_DEPS[@]}"; do
        echo "  - $dep"
    done
    echo ""
    echo "Install them with:"
    echo "  sudo apt-get update"
    echo "  sudo apt-get install -y qemu-system-x86 qemu-utils docker.io"
    echo ""
    echo "For Packer, see: https://www.packer.io/downloads"
    exit 1
fi

echo -e "${GREEN}✓ All prerequisites met${NC}"

# Step 1: Download ISO
echo ""
echo "=========================================="
echo -e "${BLUE}Step 1/4: Downloading Ubuntu ISO${NC}"
echo "=========================================="
"$SCRIPT_DIR/scripts/download_ubuntu_iso.sh"

# Step 2: Build image with Packer
echo ""
echo "=========================================="
echo -e "${BLUE}Step 2/4: Building Custom Image${NC}"
echo "=========================================="
"$SCRIPT_DIR/scripts/build_packer_image.sh"

# Step 3: Setup PXE deployment
echo ""
echo "=========================================="
echo -e "${BLUE}Step 3/4: Setting up PXE Deployment${NC}"
echo "=========================================="
"$SCRIPT_DIR/scripts/setup_pxe_deployment.sh"

# Step 4: Start services
echo ""
echo "=========================================="
echo -e "${BLUE}Step 4/4: Starting Services${NC}"
echo "=========================================="

read -p "Start PXE and BMC services now? (y/n) " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    "$SCRIPT_DIR/start.sh"
fi

# Final summary
echo ""
echo "=========================================="
echo -e "${GREEN}Setup Complete!${NC}"
echo "=========================================="
echo ""
echo "Your air-gapped PXE deployment system is ready!"
echo ""
echo "📋 Quick Start:"
echo ""
echo "1. Start a VM with PXE boot:"
echo "   python3 src/vm_manager.py start --name ubuntu01 --boot pxe"
echo ""
echo "2. Watch the deployment:"
echo "   - VNC: Connect to localhost:590X (X = vnc_port from config)"
echo "   - Logs: tail -f logs/*.log"
echo ""
echo "3. After deployment, connect via SSH:"
echo "   ssh ubuntu@<vm-ip>"
echo "   Password: ubuntu"
echo ""
echo "📊 System Status:"
echo "   Web Interface: http://192.168.100.1:8080/"
echo "   PXE Server: Running on 192.168.100.1"
echo "   DHCP Range: 192.168.100.100-200"
echo ""
echo "📁 Important Files:"
echo "   Packer config: packer/airgap-ubuntu.pkr.hcl"
echo "   Custom image: images/custom/ubuntu-server-airgap.qcow2"
echo "   PXE data: pxe-data/"
echo "   VM config: config/vms.yaml"
echo ""
echo "🔧 Common Commands:"
echo "   Rebuild image: ./scripts/build_packer_image.sh"
echo "   Stop services: ./stop.sh"
echo "   View logs: ./scripts/view_logs.sh"
echo ""
