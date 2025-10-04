#!/bin/bash
# Deploy VM with PXE boot using Packer-built image
set -e

echo "=========================================="
echo "  PXE VM Deployment with Packer Image"
echo "=========================================="
echo ""

# Configuration
VM_NAME="ubuntu-pxe-01"
BASE_IMAGE="images/vms/ubuntu-pxe-base.qcow2"
VM_IMAGE="images/vms/${VM_NAME}.qcow2"

# Check if base image exists
if [ ! -f "$BASE_IMAGE" ]; then
    echo "❌ Base image not found: $BASE_IMAGE"
    echo "Please run the Packer build first:"
    echo "  cd packer && packer build airgap-ubuntu.pkr.hcl"
    exit 1
fi

echo "✓ Found base image: $BASE_IMAGE"
echo ""

# Create VM-specific image from base (copy-on-write)
echo "Creating VM disk image..."
if [ -f "$VM_IMAGE" ]; then
    echo "  VM image already exists, removing old version..."
    rm -f "$VM_IMAGE"
fi

# Create a copy-on-write image based on the Packer image
qemu-img create -f qcow2 -b "$BASE_IMAGE" -F qcow2 "$VM_IMAGE" 20G
echo "✓ Created VM image: $VM_IMAGE"
echo ""

# Get image info
echo "Image information:"
qemu-img info "$VM_IMAGE" | grep -E "virtual size|disk size|backing file"
echo ""

# Start PXE server (if not running)
echo "Checking PXE server..."
if docker ps | grep -q pxe-server; then
    echo "✓ PXE server is running"
else
    echo "Starting PXE server..."
    docker-compose up -d pxe-server || ./start.sh pxe
fi
echo ""

# Start BMC emulator (if not running)
echo "Checking BMC emulator..."
if docker ps | grep -q openbmc; then
    echo "✓ BMC emulator is running"
else
    echo "Starting BMC emulator..."
    docker-compose up -d openbmc || ./start.sh bmc
fi
echo ""

# Start VM with PXE boot
echo "=========================================="
echo "Starting VM with PXE boot..."
echo "=========================================="
echo ""

# VM Configuration from vms.yaml
MEMORY=2048
CPUS=2
MAC="52:54:00:12:34:01"
VNC_PORT=5901
SSH_PORT=2201

echo "VM Configuration:"
echo "  Name:       $VM_NAME"
echo "  Memory:     ${MEMORY}MB"
echo "  CPUs:       $CPUS"
echo "  MAC:        $MAC"
echo "  VNC:        localhost:$VNC_PORT (port $((5900 + VNC_PORT - 5900)))"
echo "  SSH:        localhost:$SSH_PORT"
echo ""

# Check if VM is already running
if pgrep -f "qemu.*${VM_NAME}" > /dev/null; then
    echo "⚠️  VM is already running. Stopping it first..."
    pkill -f "qemu.*${VM_NAME}" || true
    sleep 2
fi

# Start VM with QEMU
echo "Starting QEMU VM..."
qemu-system-x86_64 \
    -name "$VM_NAME" \
    -enable-kvm \
    -cpu host \
    -m "$MEMORY" \
    -smp "$CPUS" \
    -drive "file=$VM_IMAGE,format=qcow2,if=virtio" \
    -netdev "user,id=net0,net=10.0.0.0/24,dhcpstart=10.0.0.101,hostfwd=tcp::${SSH_PORT}-:22" \
    -device "virtio-net-pci,netdev=net0,mac=$MAC,romfile=" \
    -boot order=nc \
    -vnc ":$((VNC_PORT - 5900))" \
    -serial mon:stdio \
    -pidfile "images/vms/${VM_NAME}.pid" \
    -daemonize

echo ""
echo "=========================================="
echo "  VM Started Successfully!"
echo "=========================================="
echo ""
echo "Access methods:"
echo "  • VNC:    vncviewer localhost:$VNC_PORT"
echo "  • SSH:    ssh -p $SSH_PORT ubuntu@localhost"
echo "  • Serial: Available in foreground mode"
echo ""
echo "Credentials:"
echo "  Username: ubuntu"
echo "  Password: ubuntu"
echo ""
echo "The VM will:"
echo "  1. Attempt PXE boot first (network)"
echo "  2. Fall back to disk boot (pre-installed Ubuntu)"
echo ""
echo "To stop the VM:"
echo "  pkill -f 'qemu.*${VM_NAME}'"
echo "  or"
echo "  kill \$(cat images/vms/${VM_NAME}.pid)"
echo ""
echo "To view VM status:"
echo "  ./scripts/status.sh"
echo ""
