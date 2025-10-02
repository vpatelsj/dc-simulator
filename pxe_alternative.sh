#!/bin/bash

# Alternative PXE Boot Setup
# Ubuntu removed legacy netboot from 22.04+ repositories
# This script provides working alternatives

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=========================================="
echo "PXE Boot Setup - Alternative Methods"
echo "=========================================="
echo ""
echo "Ubuntu 22.04+ removed legacy netboot files."
echo "Here are working alternatives:"
echo ""
echo "1. Use Ubuntu 20.04 netboot (works, stable)"
echo "2. Use Ubuntu live-server ISO + iPXE"
echo "3. Skip PXE - boot VMs from disk/ISO directly"
echo "4. Show me manual setup instructions"
echo ""

read -p "Choose option [1-4]: " choice

case $choice in
    1)
        echo ""
        echo "Downloading Ubuntu 20.04 netboot..."
        mkdir -p images/ubuntu
        
        url="http://archive.ubuntu.com/ubuntu/dists/focal/main/installer-amd64/current/legacy-images/netboot/netboot.tar.gz"
        
        echo "Downloading from: $url"
        if curl -fSL --progress-bar -o images/ubuntu/netboot.tar.gz "$url"; then
            cd images/ubuntu
            echo "Extracting files..."
            tar -xzf netboot.tar.gz
            cd "$SCRIPT_DIR"
            
            echo ""
            echo "✅ Ubuntu 20.04 netboot installed successfully!"
            echo ""
            echo "Your PXE server will now serve Ubuntu 20.04 LTS"
            echo "This is a fully supported LTS release until 2025."
            echo ""
        else
            echo "❌ Download failed"
            exit 1
        fi
        ;;
        
    2)
        echo ""
        echo "Live-Server ISO + iPXE Setup"
        echo "============================="
        echo ""
        echo "This method uses the Ubuntu live-server ISO with iPXE boot."
        echo ""
        echo "Step 1: Download Ubuntu 22.04 live-server ISO"
        echo "   URL: https://releases.ubuntu.com/22.04/ubuntu-22.04.5-live-server-amd64.iso"
        echo ""
        echo "Step 2: Extract boot files"
        mkdir -p images/ubuntu/http
        echo "   # After downloading ISO:"
        echo "   sudo mount -o loop ubuntu-22.04.5-live-server-amd64.iso /mnt"
        echo "   cp /mnt/casper/vmlinuz images/ubuntu/http/"
        echo "   cp /mnt/casper/initrd images/ubuntu/http/"
        echo "   sudo umount /mnt"
        echo ""
        echo "Step 3: Update PXE config (see USAGE.md)"
        echo ""
        ;;
        
    3)
        echo ""
        echo "Skip PXE Boot Setup"
        echo "==================="
        echo ""
        echo "You can still use the BMC emulator without PXE boot:"
        echo ""
        echo "Option A: Boot from disk"
        echo "   1. Create VM: make create-vm"
        echo "   2. Download Ubuntu ISO to images/"
        echo "   3. Modify VM config to mount ISO"
        echo "   4. Boot VM normally"
        echo ""
        echo "Option B: Use pre-installed disk images"
        echo "   1. Download Ubuntu cloud image"
        echo "   2. Use as VM disk image"
        echo "   3. Configure with cloud-init"
        echo ""
        echo "The BMC features (IPMI/Redfish/power management) work regardless!"
        echo ""
        ;;
        
    4)
        cat << 'EOF'

Manual PXE Setup Instructions
==============================

Why Ubuntu 22.04+ netboot is unavailable:
- Ubuntu deprecated legacy debian-installer netboot
- Modern installations use live-server ISO + subiquity
- Canonical recommends cloud-init or MAAS for automation

Alternatives:

1. Use Ubuntu 20.04 netboot (supported until 2025)
   Run this script and choose option 1

2. Use Ubuntu live-server with HTTP boot
   - Mount ISO and serve via HTTP
   - Configure PXE to chain-load HTTP boot
   - Use autoinstall with cloud-init

3. Use alternative distributions
   - Debian still provides netboot
   - CentOS/RHEL have netboot
   - Many still support classic PXE

4. Use modern provisioning
   - MAAS (Metal as a Service)
   - Foreman
   - Cobbler
   - Tinkerbell

For this BMC emulator:
- Recommend option 1 (Ubuntu 20.04) for simplicity
- BMC features work without PXE
- VMs can boot from disk images

Example commands:
  ./pxe_alternative.sh   # Choose option 1
  make start             # Start services  
  make create-vm         # Create VM
  python src/vm_manager.py start --name vm01 --boot disk

EOF
        ;;
        
    *)
        echo "Invalid option"
        exit 1
        ;;
esac

echo ""
echo "=========================================="
echo "Next Steps:"
echo "=========================================="
echo ""
echo "1. Run: make start"
echo "2. Create VM: make create-vm"
echo "3. Start VM:"
echo "   - PXE boot: python src/vm_manager.py start --name <vm> --boot pxe"
echo "   - Disk boot: python src/vm_manager.py start --name <vm> --boot disk"
echo ""
