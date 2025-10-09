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

# Copy PXE bootloader files from local system if they exist
if [ -f "/usr/lib/PXELINUX/pxelinux.0" ] && [ -f "/usr/lib/syslinux/modules/bios/ldlinux.c32" ] && [ -f "/usr/lib/syslinux/modules/bios/libutil.c32" ] && [ -f "/usr/lib/syslinux/modules/bios/libcom32.c32" ] && [ -f "/usr/lib/syslinux/modules/bios/vesamenu.c32" ]; then
    echo "Copying PXE bootloader files from local system..."
    cp "/usr/lib/PXELINUX/pxelinux.0" "$SCRIPT_DIR/pxe-data/tftp/"
    cp "/usr/lib/syslinux/modules/bios/ldlinux.c32" "$SCRIPT_DIR/pxe-data/tftp/"
    cp "/usr/lib/syslinux/modules/bios/libutil.c32" "$SCRIPT_DIR/pxe-data/tftp/"
    cp "/usr/lib/syslinux/modules/bios/libcom32.c32" "$SCRIPT_DIR/pxe-data/tftp/"
    cp "/usr/lib/syslinux/modules/bios/vesamenu.c32" "$SCRIPT_DIR/pxe-data/tftp/"
    echo "✓ PXE bootloader files copied"
else
    echo "PXE bootloader files not found locally. Please run 'sudo apt-get install pxelinux syslinux-common' to install them."
    exit 1
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
cp "$SCRIPT_DIR/scripts/discovery.sh" opt/discovery/
chmod +x opt/discovery/discovery.sh

# Create custom init script that runs discovery
cat > init.custom <<'EOF'
#!/bin/sh
# Mount proc, sys, dev
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev

# Prepare module dependency data
if command -v depmod >/dev/null 2>&1; then
    depmod -a 2>/dev/null || true
fi

# Setup network
echo "Configuring network..."

# Ensure loopback is up
ip link set lo up 2>/dev/null || ifconfig lo up 2>/dev/null

# Load common virtual NIC drivers
load_module() {
    mod="$1"
    if command -v modprobe >/dev/null 2>&1 && modprobe -n "$mod" >/dev/null 2>&1; then
        if modprobe "$mod" >/dev/null 2>&1; then
            echo "Loaded module via modprobe: $mod"
            return 0
        fi
    fi
    if command -v find >/dev/null 2>&1; then
        for path in $(find /lib/modules -type f -name "${mod}.ko" -o -name "${mod}.ko.gz" 2>/dev/null); do
            if printf '%s' "$path" | grep -q '\.gz$'; then
                tmp="/tmp/${mod}.ko"
                gzip -dc "$path" > "$tmp" 2>/dev/null || continue
                insmod "$tmp" >/dev/null 2>&1 && {
                    echo "Loaded module via insmod: $mod";
                    rm -f "$tmp"
                    return 0
                }
                rm -f "$tmp"
            else
                insmod "$path" >/dev/null 2>&1 && {
                    echo "Loaded module via insmod: $mod";
                    return 0
                }
            fi
        done
    fi
    return 1
}

for module in mii mdio virtio_net virtio_pci virtio_ring e1000 e1000e 8139cp 8139too; do
    load_module "$module" || true
done

# Detect primary interface
PRIMARY_IF=""
for attempt in 1 2 3 4 5 6 7 8 9 10; do
    for iface_path in /sys/class/net/*; do
        iface="$(basename "$iface_path")"
        case "$iface" in
            lo|dummy*|sit*|tun*|tap*|virbr*|veth*|vmnet*|vbox*|br*|docker*|zt*|wg*)
                continue
                ;;
        esac
        PRIMARY_IF="$iface"
        break
    done
    [ -n "$PRIMARY_IF" ] && break
    sleep 1
done

if [ -z "$PRIMARY_IF" ]; then
    echo "WARNING: No usable network interface detected"
else
    echo "Using network interface: $PRIMARY_IF"
    ip link set "$PRIMARY_IF" up 2>/dev/null || ifconfig "$PRIMARY_IF" up 2>/dev/null
    if command -v udhcpc >/dev/null 2>&1; then
        udhcpc -i "$PRIMARY_IF" -q -n || true
    fi
fi

export DISCOVERY_IF="$PRIMARY_IF"

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

# Set ownership of generated files
echo "Setting ownership of generated files..."
if [ -n "$SUDO_USER" ]; then
    chown -R "$SUDO_USER:$SUDO_USER" "$SCRIPT_DIR/pxe-data"
    echo "✓ Ownership set to $SUDO_USER"
fi

echo "✓ Discovery environment setup complete"

echo ""

# Update PXE menu
echo "Updating PXE boot menu..."

MENU_FILE="$SCRIPT_DIR/pxe-data/tftp/pxelinux.cfg/default"
mkdir -p "$(dirname "$MENU_FILE")"

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
