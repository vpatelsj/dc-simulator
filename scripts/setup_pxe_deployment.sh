#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd .. && pwd)"
PXE_TFTP="$SCRIPT_DIR/pxe-data/tftp"
PXE_HTTP="$SCRIPT_DIR/pxe-data/http"
CUSTOM_IMAGE="$SCRIPT_DIR/images/custom/ubuntu-server-airgap.qcow2"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "=========================================="
echo "Setting up PXE Deployment Infrastructure"
echo "=========================================="
echo ""

# Check if custom image exists
if [ ! -f "$CUSTOM_IMAGE" ]; then
    echo -e "${RED}Error: Custom image not found!${NC}"
    echo ""
    echo "Build the image first:"
    echo "  ./scripts/build_packer_image.sh"
    exit 1
fi

# Create directories
mkdir -p "$PXE_TFTP/boot"
mkdir -p "$PXE_TFTP/pxelinux.cfg"
mkdir -p "$PXE_HTTP/images"
mkdir -p "$PXE_HTTP/scripts"

echo -e "${GREEN}Copying deployment image...${NC}"
cp -v "$CUSTOM_IMAGE" "$PXE_HTTP/images/"

# Download netboot files if not present
if [ ! -f "$PXE_TFTP/boot/vmlinuz" ]; then
    echo ""
    echo -e "${GREEN}Copying netboot files from existing installation...${NC}"
    
    # Check if we have existing netboot files
    if [ -f "$SCRIPT_DIR/images/ubuntu/ubuntu-installer/amd64/linux" ]; then
        echo "Using existing netboot files from images/ubuntu/"
        
        # Copy kernel and initrd
        cp "$SCRIPT_DIR/images/ubuntu/ubuntu-installer/amd64/linux" "$PXE_TFTP/boot/vmlinuz"
        cp "$SCRIPT_DIR/images/ubuntu/ubuntu-installer/amd64/initrd.gz" "$PXE_TFTP/boot/initrd.gz"
        
        # Copy pxelinux files
        cp "$SCRIPT_DIR/images/ubuntu/pxelinux.0" "$PXE_TFTP/" 2>/dev/null || true
        cp "$SCRIPT_DIR/images/ubuntu/ldlinux.c32" "$PXE_TFTP/" 2>/dev/null || true
        cp "$SCRIPT_DIR/images/ubuntu/ubuntu-installer/amd64/boot-screens/"*.c32 "$PXE_TFTP/" 2>/dev/null || true
        
        echo -e "${GREEN}✓ Netboot files copied${NC}"
    else
        echo -e "${RED}Error: No netboot files found!${NC}"
        echo ""
        echo "Run setup first:"
        echo "  ./setup.sh"
        exit 1
    fi
else
    echo -e "${GREEN}✓ Netboot files already exist${NC}"
fi

# Create image deployment script
echo ""
echo -e "${GREEN}Creating deployment scripts...${NC}"

cat > "$PXE_HTTP/scripts/deploy-image.sh" << 'DEPLOY_SCRIPT'
#!/bin/bash
# Automated bare-metal image deployment script for air-gapped environments

set -e

IMAGE_URL="http://192.168.100.1:8080/images/ubuntu-server-airgap.qcow2"
TARGET_DISK="/dev/vda"

echo "=========================================="
echo "Bare-Metal Image Deployment"
echo "=========================================="
echo "Target Disk: $TARGET_DISK"
echo "Image URL: $IMAGE_URL"
echo ""

# Detect the actual target disk
if [ ! -b "$TARGET_DISK" ]; then
    echo "Warning: $TARGET_DISK not found, detecting available disks..."
    
    for disk in /dev/vda /dev/sda /dev/nvme0n1; do
        if [ -b "$disk" ]; then
            TARGET_DISK="$disk"
            echo "Found disk: $TARGET_DISK"
            break
        fi
    done
    
    if [ ! -b "$TARGET_DISK" ]; then
        echo "Error: No suitable disk found!"
        exit 1
    fi
fi

echo "Using disk: $TARGET_DISK"
echo ""

# Install required tools
echo "Installing deployment tools..."
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y wget qemu-utils parted cloud-utils

# Download image
echo ""
echo "Downloading system image..."
echo "This may take several minutes..."
wget --progress=bar:force -O /tmp/system.qcow2 "$IMAGE_URL"

if [ $? -ne 0 ]; then
    echo "Error: Failed to download image"
    exit 1
fi

echo ""
echo "Download complete!"
echo ""

# Convert qcow2 to raw and write to disk
echo ""
echo "Writing image to disk: $TARGET_DISK"
echo "This may take several minutes..."
echo ""

qemu-img convert -f qcow2 -O raw -p /tmp/system.qcow2 "$TARGET_DISK"

if [ $? -ne 0 ]; then
    echo "Error: Failed to write image to disk"
    exit 1
fi

# Sync to ensure all data is written
sync

echo ""
echo "Image written successfully!"
echo ""

# Expand partition to fill disk
DISK_SIZE=$(blockdev --getsize64 "$TARGET_DISK")
PARTITION="${TARGET_DISK}1"

# Handle nvme naming
if [[ "$TARGET_DISK" == *"nvme"* ]]; then
    PARTITION="${TARGET_DISK}p1"
fi

echo "Expanding partition to fill disk..."
growpart "$TARGET_DISK" 1 2>/dev/null || echo "Partition already at maximum size"

# Resize filesystem
echo "Resizing filesystem..."
if blkid "$PARTITION" | grep -q "TYPE=\"ext4\""; then
    e2fsck -f -y "$PARTITION" || true
    resize2fs "$PARTITION" || true
fi

echo ""
echo "=========================================="
echo "Deployment Complete!"
echo "=========================================="
echo ""
echo "Default credentials:"
echo "  Username: ubuntu"
echo "  Password: ubuntu"
echo ""
echo "The system will now reboot..."
sleep 3
reboot
DEPLOY_SCRIPT

chmod +x "$PXE_HTTP/scripts/deploy-image.sh"

# Create PXE boot menu
echo ""
echo -e "${GREEN}Creating PXE boot menu...${NC}"

cat > "$PXE_TFTP/pxelinux.cfg/default" << 'PXEMENU'
DEFAULT menu
TIMEOUT 100
PROMPT 0

MENU TITLE Bare-Metal Deployment System

LABEL deploy
    MENU LABEL Deploy Ubuntu Image to Disk
    MENU DEFAULT
    KERNEL boot/vmlinuz
    APPEND initrd=boot/initrd.gz boot=casper netboot=url url=http://192.168.100.1:8080/scripts/deploy-image.sh ip=dhcp --- quiet

LABEL local
    MENU LABEL Boot from Local Disk
    LOCALBOOT 0
PXEMENU

echo ""
echo "=========================================="
echo -e "${GREEN}PXE Deployment Setup Complete!${NC}"
echo "=========================================="
echo ""
echo "Image ready:"
ls -lh "$PXE_HTTP/images/"
echo ""
echo "Next steps:"
echo "  1. Start services: ./start.sh"
echo "  2. Create/start VM with PXE boot"
echo "  3. VM will auto-deploy the image"
echo ""