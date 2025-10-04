#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd .. && pwd)"
ISO_DIR="$SCRIPT_DIR/images/iso"
ISO_FILE="$ISO_DIR/ubuntu-22.04.3-live-server-amd64.iso"
ISO_URL="https://releases.ubuntu.com/22.04.3/ubuntu-22.04.3-live-server-amd64.iso"
ISO_CHECKSUM="a4acfda10b18da50e2ec50ccaf860d7f20b389df8765611142305c0e911d16fd"

echo "=========================================="
echo "Downloading Ubuntu ISO for Packer Build"
echo "=========================================="
echo ""

# Create ISO directory
mkdir -p "$ISO_DIR"

# Check if ISO already exists
if [ -f "$ISO_FILE" ]; then
    echo "ISO file already exists: $ISO_FILE"
    echo "Verifying checksum..."
    
    ACTUAL_CHECKSUM=$(sha256sum "$ISO_FILE" | awk '{print $1}')
    
    if [ "$ACTUAL_CHECKSUM" = "$ISO_CHECKSUM" ]; then
        echo "✓ Checksum verified successfully"
        echo ""
        echo "ISO is ready for Packer build!"
        exit 0
    else
        echo "✗ Checksum verification failed!"
        echo "Expected: $ISO_CHECKSUM"
        echo "Got:      $ACTUAL_CHECKSUM"
        echo "Removing corrupted ISO and re-downloading..."
        rm -f "$ISO_FILE"
    fi
fi

# Download ISO
echo "Downloading Ubuntu 22.04.3 Live Server ISO..."
echo "Source: $ISO_URL"
echo "Destination: $ISO_FILE"
echo ""
echo "This may take several minutes depending on your connection..."
echo ""

if command -v wget &> /dev/null; then
    wget -O "$ISO_FILE" "$ISO_URL" --progress=bar:force
elif command -v curl &> /dev/null; then
    curl -L -o "$ISO_FILE" "$ISO_URL" --progress-bar
else
    echo "Error: Neither wget nor curl is available"
    echo "Please install wget or curl and try again"
    exit 1
fi

# Verify checksum
echo ""
echo "Verifying checksum..."
ACTUAL_CHECKSUM=$(sha256sum "$ISO_FILE" | awk '{print $1}')

if [ "$ACTUAL_CHECKSUM" = "$ISO_CHECKSUM" ]; then
    echo "✓ Checksum verified successfully"
    echo ""
    echo "=========================================="
    echo "Download Complete!"
    echo "=========================================="
    echo "ISO file: $ISO_FILE"
    echo "Size: $(du -h "$ISO_FILE" | cut -f1)"
    echo ""
    echo "You can now build the image with:"
    echo "  ./scripts/build_packer_image.sh"
else
    echo "✗ Checksum verification failed!"
    echo "Expected: $ISO_CHECKSUM"
    echo "Got:      $ACTUAL_CHECKSUM"
    echo ""
    echo "The downloaded file may be corrupted."
    echo "Please try downloading again."
    exit 1
fi
