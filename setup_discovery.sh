#!/bin/bash
# Apollo Simulator - Discovery Environment Setup
# Downloads and configures Tiny Core Linux for machine discovery

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DISCOVERY_DIR="$SCRIPT_DIR/pxe-data/tftp/deploy"
HTTP_DIR="$SCRIPT_DIR/pxe-data/http"

echo "=========================================="
echo "  Discovery Environment Setup"
echo "=========================================="
echo ""

# Check if discovery files already exist
if [ -f "$DISCOVERY_DIR/vmlinuz" ] && [ -f "$DISCOVERY_DIR/core.gz" ]; then
    echo "Discovery kernel already exists. Recreating initramfs..."
else
    echo "Downloading Tiny Core Linux..."
    mkdir -p "$DISCOVERY_DIR"
    cd "$DISCOVERY_DIR"
    
    # Download Tiny Core Linux kernel and initramfs
    if [ ! -f vmlinuz ]; then
        wget -q --show-progress \
            http://tinycorelinux.net/14.x/x86_64/release/distribution_files/vmlinuz64 \
            -O vmlinuz
        echo "✓ Kernel downloaded"
    fi
    
    if [ ! -f core.gz.orig ]; then
        wget -q --show-progress \
            http://tinycorelinux.net/14.x/x86_64/release/distribution_files/corepure64.gz \
            -O core.gz.orig
        echo "✓ Base initramfs downloaded"
    fi
fi

# Create custom initramfs with discovery script
echo ""
echo "Building custom initramfs with discovery script..."

cd "$DISCOVERY_DIR"
WORK_DIR=$(mktemp -d)
cd "$WORK_DIR"

# Extract base initramfs
zcat "$DISCOVERY_DIR/core.gz.orig" | cpio -id

# Customize the initramfs
echo "Adding discovery script..."
mkdir -p opt/discovery
cp "$DISCOVERY_DIR/discovery.sh" opt/discovery/
chmod +x opt/discovery/discovery.sh

# Create custom init script that runs discovery
cat > init.custom <<'EOF'
#!/bin/sh
# Mount proc, sys, dev
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev

# Setup network
echo "Configuring network..."
ip link set lo up
ip link set eth0 up
udhcpc -i eth0 -q -n

# Run discovery
clear
/opt/discovery/discovery.sh
EOF

chmod +x init.custom

# Backup original init and use custom one
if [ ! -f init.orig ]; then
    cp init init.orig
fi
cp init.custom init

# Repack initramfs
echo "Packing custom initramfs..."
find . | cpio -o -H newc | gzip > "$DISCOVERY_DIR/core.gz"

# Cleanup
cd "$SCRIPT_DIR"
rm -rf "$WORK_DIR"

echo "✓ Custom initramfs created"
echo ""

# Update PXE menu
echo "Updating PXE boot menu..."

MENU_FILE="$SCRIPT_DIR/pxe-data/tftp/pxelinux.cfg/default"

# Check if discovery menu already exists
if ! grep -q "LABEL discovery" "$MENU_FILE"; then
    cat >> "$MENU_FILE" <<'MENUEOF'

LABEL discovery
  MENU LABEL ^Discovery Mode (Register Machine)
  KERNEL /deploy/vmlinuz
  APPEND initrd=/deploy/core.gz quiet
  TEXT HELP
    Boot into discovery mode to register this machine
    with the Apollo provisioning service.
  ENDTEXT

LABEL deploy
  MENU LABEL Deploy ^Ubuntu Image
  KERNEL /deploy/vmlinuz
  APPEND initrd=/deploy/core.gz quiet auto_deploy=true
  TEXT HELP
    Automatically deploy Ubuntu image after registration.
    Machine will reboot after deployment completes.
  ENDTEXT
MENUEOF
    echo "✓ Added discovery options to PXE menu"
else
    echo "✓ Discovery options already in PXE menu"
fi

# Make sure HTTP directory exists for images
mkdir -p "$HTTP_DIR/images"

echo ""
echo "=========================================="
echo "  Setup Complete!"
echo "=========================================="
echo ""
echo "Discovery kernel: $DISCOVERY_DIR/vmlinuz"
echo "Discovery initramfs: $DISCOVERY_DIR/core.gz"
echo ""
echo "Next steps:"
echo "  1. Start provisioning service: make start-provisioning"
echo "  2. Create VM: make vm-create"
echo "  3. Select 'Discovery Mode' from PXE menu"
echo "  4. View registered machines: make list-machines"
echo "  5. Deploy to machine: make deploy MACHINE=<mac>"
echo ""
