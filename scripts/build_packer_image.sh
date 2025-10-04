#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd .. && pwd)"
PACKER_DIR="$SCRIPT_DIR/packer"
ISO_FILE="$SCRIPT_DIR/images/iso/ubuntu-22.04.3-live-server-amd64.iso"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=========================================="
echo "Building Ubuntu Image with Packer"
echo "=========================================="
echo ""

# Check if Packer is installed
if ! command -v packer &> /dev/null; then
    echo -e "${RED}Error: Packer is not installed${NC}"
    echo ""
    echo "Install Packer:"
    echo "  Ubuntu/Debian: wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg"
    echo "                 echo \"deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main\" | sudo tee /etc/apt/sources.list.d/hashicorp.list"
    echo "                 sudo apt update && sudo apt install packer"
    echo ""
    echo "  Or download from: https://www.packer.io/downloads"
    exit 1
fi

# Check if qemu is installed
if ! command -v qemu-system-x86_64 &> /dev/null; then
    echo -e "${RED}Error: QEMU is not installed${NC}"
    echo ""
    echo "Install QEMU:"
    echo "  sudo apt-get install -y qemu-system-x86 qemu-utils"
    exit 1
fi

# Check if ISO exists
if [ ! -f "$ISO_FILE" ]; then
    echo -e "${YELLOW}Ubuntu ISO not found!${NC}"
    echo ""
    echo "Downloading Ubuntu ISO..."
    "$SCRIPT_DIR/scripts/download_ubuntu_iso.sh"
fi

# Change to packer directory
cd "$PACKER_DIR"

# Initialize Packer (download plugins)
echo ""
echo -e "${GREEN}Initializing Packer...${NC}"
packer init airgap-ubuntu.pkr.hcl

# Validate Packer configuration
echo ""
echo -e "${GREEN}Validating Packer configuration...${NC}"
packer validate airgap-ubuntu.pkr.hcl

if [ $? -ne 0 ]; then
    echo -e "${RED}Packer configuration validation failed!${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}✓ Packer configuration is valid${NC}"
echo ""

# Build the image
echo "=========================================="
echo "Starting Image Build"
echo "=========================================="
echo ""
echo "This process will:"
echo "  1. Create a VM with QEMU"
echo "  2. Install Ubuntu automatically"
echo "  3. Provision the system"
echo "  4. Clean and prepare for deployment"
echo "  5. Compress the final image"
echo ""
echo "Estimated time: 15-25 minutes"
echo ""
echo "You can monitor the build process:"
echo "  - VNC display: vnc://localhost:5900 (if enabled)"
echo "  - Build logs will appear below"
echo ""
echo "Starting build now..."
echo ""

# Run Packer build
packer build \
    -on-error=ask \
    airgap-ubuntu.pkr.hcl

if [ $? -eq 0 ]; then
    echo ""
    echo "=========================================="
    echo -e "${GREEN}Build Completed Successfully!${NC}"
    echo "=========================================="
    echo ""
    echo "Image location:"
    ls -lh "/home/vapa/dev/apollo-simulator/packer/output-ubuntu-airgap/ubuntu-server-airgap"*.qcow2
    echo ""
    echo "Next steps:"
    echo "  1. Setup PXE server with the image:"
    echo "     ./scripts/setup_pxe_deployment.sh"
    echo ""
    echo "  2. Start the services:"
    echo "     ./start.sh"
    echo ""
    echo "  3. Deploy to VMs via PXE boot"
else
    echo ""
    echo -e "${RED}Build failed!${NC}"
    echo "Check the logs above for errors."
    exit 1
fi
