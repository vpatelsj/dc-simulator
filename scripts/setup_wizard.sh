#!/bin/bash

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

clear

echo "=========================================="
echo "  DC Simulator - Deployment Setup"
echo "=========================================="
echo ""
echo "This simulator supports two deployment methods:"
echo ""

echo -e "${BLUE}1. Legacy PXE Boot (Netboot Installer)${NC}"
echo "   ✓ Quick setup (~5 minutes)"
echo "   ✓ Downloads ~120MB netboot files"
echo "   ✓ Manual Ubuntu installation wizard"
echo "   ✓ Good for: Learning, testing, development"
echo "   ⏱ Deployment time: 20-30 minutes per VM"
echo ""

echo -e "${BLUE}2. Modern Image Deployment (Packer + PXE)${NC}"
echo "   ✓ One-time build (~20 minutes)"
echo "   ✓ Downloads ~1.4GB Ubuntu ISO"
echo "   ✓ Automated deployment, no wizard"
echo "   ✓ Good for: Production, air-gapped, scaling"
echo "   ⏱ Build time: 20 minutes (once)"
echo "   ⏱ Deployment time: 2-5 minutes per VM"
echo ""

echo "=========================================="
echo ""

read -p "Which method would you like to use? (1/2): " choice

case $choice in
    1)
        echo ""
        echo -e "${GREEN}Setting up Legacy PXE Boot...${NC}"
        echo ""
        ./setup.sh
        
        echo ""
        echo "=========================================="
        echo -e "${GREEN}Setup Complete!${NC}"
        echo "=========================================="
        echo ""
        echo "Next steps:"
        echo "  1. Start services:     ${CYAN}./start.sh${NC}"
        echo "  2. Create VM:          ${CYAN}python3 src/vm_manager.py create --name ubuntu01${NC}"
        echo "  3. Start VM with PXE:  ${CYAN}python3 src/vm_manager.py start --name ubuntu01 --boot pxe${NC}"
        echo "  4. Connect via VNC:    ${CYAN}vncviewer localhost:5901${NC}"
        echo ""
        echo "The VM will boot into Ubuntu installer wizard."
        echo ""
        ;;
        
    2)
        echo ""
        echo -e "${GREEN}Setting up Modern Image Deployment...${NC}"
        echo ""
        
        # Check prerequisites
        echo "Checking prerequisites..."
        MISSING=()
        
        if ! command -v packer &> /dev/null; then
            MISSING+=("packer")
        fi
        
        if ! command -v qemu-system-x86_64 &> /dev/null; then
            MISSING+=("qemu-system-x86")
        fi
        
        if ! command -v docker &> /dev/null; then
            MISSING+=("docker")
        fi
        
        if [ ${#MISSING[@]} -ne 0 ]; then
            echo -e "${RED}Missing required tools:${NC}"
            for tool in "${MISSING[@]}"; do
                echo "  - $tool"
            done
            echo ""
            echo "Install them with:"
            echo "  ${CYAN}sudo apt-get update${NC}"
            echo "  ${CYAN}sudo apt-get install -y qemu-system-x86 qemu-utils docker.io${NC}"
            echo ""
            echo "For Packer:"
            echo "  ${CYAN}wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg${NC}"
            echo "  ${CYAN}echo \"deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com \$(lsb_release -cs) main\" | sudo tee /etc/apt/sources.list.d/hashicorp.list${NC}"
            echo "  ${CYAN}sudo apt update && sudo apt install packer${NC}"
            echo ""
            exit 1
        fi
        
        echo -e "${GREEN}✓ All prerequisites met${NC}"
        echo ""
        
        # Run build and deploy pipeline
        ./scripts/build_and_deploy.sh
        ;;
        
    *)
        echo ""
        echo -e "${RED}Invalid choice. Please run again and select 1 or 2.${NC}"
        exit 1
        ;;
esac

echo ""
echo "For more information:"
echo "  Legacy method:  See ${CYAN}README.md${NC}"
echo "  Modern method:  See ${CYAN}AIRGAP_DEPLOYMENT.md${NC} and ${CYAN}packer/README.md${NC}"
echo "  System status:  Run ${CYAN}./scripts/status.sh${NC}"
echo ""
