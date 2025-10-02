#!/bin/bash

# BMC Emulator Setup Script
# Sets up OpenBMC container and PXE boot environment

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=========================================="
echo "BMC Emulator Setup"
echo "=========================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check prerequisites
check_prerequisites() {
    echo -e "\n${YELLOW}Checking prerequisites...${NC}"
    
    # Check if running on WSL
    if ! grep -q microsoft /proc/version; then
        echo -e "${RED}Warning: Not running on WSL. Some features may not work.${NC}"
    fi
    
    # Check KVM support
    if [ -e /dev/kvm ]; then
        echo -e "${GREEN}✓ KVM device found${NC}"
        
        # Check if user can access KVM
        if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
            echo -e "${GREEN}✓ KVM access available${NC}"
        else
            echo -e "${YELLOW}⚠ KVM access not available for current user${NC}"
            echo "  Run: sudo usermod -aG kvm \$USER"
            echo "  Then log out and log back in"
        fi
    else
        echo -e "${RED}✗ KVM device not found${NC}"
        echo "  Nested virtualization may not be enabled"
    fi
    
    # Check for Docker/Podman
    if command -v docker &> /dev/null; then
        echo -e "${GREEN}✓ Docker found${NC}"
        CONTAINER_ENGINE="docker"
    elif command -v podman &> /dev/null; then
        echo -e "${GREEN}✓ Podman found${NC}"
        CONTAINER_ENGINE="podman"
    else
        echo -e "${RED}✗ Neither Docker nor Podman found${NC}"
        echo "  Install Docker: curl -fsSL https://get.docker.com | sh"
        exit 1
    fi
    
    # Check for QEMU
    if command -v qemu-system-x86_64 &> /dev/null; then
        echo -e "${GREEN}✓ QEMU found${NC}"
    else
        echo -e "${YELLOW}⚠ QEMU not found${NC}"
        echo "  Installing QEMU..."
        sudo apt-get update && sudo apt-get install -y qemu-system-x86 qemu-utils
    fi
    
    # Check for Python
    if command -v python3 &> /dev/null; then
        echo -e "${GREEN}✓ Python 3 found${NC}"
    else
        echo -e "${RED}✗ Python 3 not found${NC}"
        exit 1
    fi
}

# Create directory structure
create_directories() {
    echo -e "\n${YELLOW}Creating directory structure...${NC}"
    
    mkdir -p containers/openbmc
    mkdir -p containers/pxe-server/config
    mkdir -p containers/pxe-server/tftp
    mkdir -p containers/pxe-server/http
    mkdir -p images/ubuntu
    mkdir -p images/vms
    mkdir -p scripts
    mkdir -p src
    mkdir -p config
    mkdir -p logs
    
    echo -e "${GREEN}✓ Directories created${NC}"
}

# Install Python dependencies
install_python_deps() {
    echo -e "\n${YELLOW}Installing Python dependencies...${NC}"
    
    # Check if venv exists, if not create it
    if [ -d "venv" ]; then
        echo "Using existing virtual environment..."
    else
        echo "Creating virtual environment..."
        python3 -m venv venv
        echo -e "${GREEN}✓ Virtual environment created${NC}"
    fi
    
    # Activate virtual environment and install packages
    source venv/bin/activate
    
    # Upgrade pip first
    pip install --upgrade pip
    
    # Install required packages
    pip install pyyaml requests jinja2
    
    echo -e "${GREEN}✓ Python dependencies installed in virtual environment${NC}"
}

# Download Ubuntu netboot files
download_ubuntu_netboot() {
    echo -e "\n${YELLOW}Downloading Ubuntu netboot files...${NC}"
    
    UBUNTU_VERSION="22.04"
    
    # Try multiple URLs in case one is down
    NETBOOT_URLS=(
        "http://archive.ubuntu.com/ubuntu/dists/jammy/main/installer-amd64/current/legacy-images/netboot/netboot.tar.gz"
        "http://us.archive.ubuntu.com/ubuntu/dists/jammy/main/installer-amd64/current/legacy-images/netboot/netboot.tar.gz"
        "http://mirrors.kernel.org/ubuntu/dists/jammy/main/installer-amd64/current/legacy-images/netboot/netboot.tar.gz"
    )
    
    # Check if valid netboot files already exist
    if [ -f "images/ubuntu/pxelinux.0" ] && [ -s "images/ubuntu/pxelinux.0" ]; then
        echo -e "${GREEN}✓ Ubuntu netboot files already present${NC}"
        return 0
    fi
    
    # Try downloading from available mirrors
    download_success=false
    for url in "${NETBOOT_URLS[@]}"; do
        echo "Trying to download from: $url"
        if wget -q --timeout=30 --tries=2 --show-progress -O images/ubuntu/netboot.tar.gz "$url" 2>&1; then
            # Check if download was successful (file size > 0)
            if [ -s "images/ubuntu/netboot.tar.gz" ]; then
                echo "Download successful!"
                download_success=true
                break
            else
                echo "Download failed (0 bytes), trying next mirror..."
                rm -f images/ubuntu/netboot.tar.gz
            fi
        else
            echo "Download failed, trying next mirror..."
            rm -f images/ubuntu/netboot.tar.gz
        fi
    done
    
    if [ "$download_success" = true ]; then
        echo "Extracting netboot files..."
        cd images/ubuntu
        tar -xzf netboot.tar.gz 2>/dev/null || {
            echo -e "${RED}Failed to extract netboot files${NC}"
            cd "$SCRIPT_DIR"
            return 1
        }
        cd "$SCRIPT_DIR"
        echo -e "${GREEN}✓ Ubuntu netboot files downloaded and extracted${NC}"
    else
        echo -e "${YELLOW}⚠ Could not download Ubuntu netboot files automatically${NC}"
        echo ""
        echo "This is optional - you can:"
        echo "  1. Skip for now and download later"
        echo "  2. Use cloud-init or other provisioning methods"
        echo "  3. Manually download from: https://releases.ubuntu.com/22.04/"
        echo ""
        echo "The BMC emulator will still work for VM management."
        echo "PXE boot will work once you add netboot files to images/ubuntu/"
        echo ""
        return 0  # Don't fail setup, just warn
    fi
}

# Setup network bridge
setup_network() {
    echo -e "\n${YELLOW}Setting up network bridge...${NC}"
    
    # Check if bridge already exists
    if ip link show br0 &> /dev/null; then
        echo -e "${GREEN}✓ Bridge br0 already exists${NC}"
    else
        echo "Creating bridge br0..."
        sudo ip link add name br0 type bridge
        sudo ip addr add 192.168.100.1/24 dev br0
        sudo ip link set br0 up
        
        echo -e "${GREEN}✓ Bridge br0 created${NC}"
    fi
}

# Create configuration files
create_configs() {
    echo -e "\n${YELLOW}Creating configuration files...${NC}"
    
    # Network configuration
    cat > config/network.conf << 'EOF'
# Network Configuration
BRIDGE_NAME=br0
BRIDGE_IP=192.168.100.1
BRIDGE_SUBNET=192.168.100.0/24
DHCP_RANGE_START=192.168.100.100
DHCP_RANGE_END=192.168.100.200
BMC_IP=192.168.100.10
PXE_SERVER_IP=192.168.100.1
EOF

    # VM defaults
    cat > config/vms.yaml << 'EOF'
# Default VM configurations
defaults:
  memory: 2048  # MB
  cpus: 2
  disk_size: 20  # GB
  network: br0
  boot_order:
    - network
    - disk

vms: {}
EOF

    echo -e "${GREEN}✓ Configuration files created${NC}"
}

# Main setup
main() {
    check_prerequisites
    create_directories
    install_python_deps
    download_ubuntu_netboot
    setup_network
    create_configs
    
    echo -e "\n=========================================="
    echo -e "${GREEN}Setup completed successfully!${NC}"
    echo "=========================================="
    echo ""
    echo "Next steps:"
    echo "1. If you weren't in the kvm group, log out and back in to WSL"
    echo "2. Run: ./start.sh to start all services"
    echo "3. Run: python3 src/vm_manager.py --help for VM management"
    echo ""
}

main
