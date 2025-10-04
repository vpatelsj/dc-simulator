#!/bin/bash
# Quick test script to boot the built image

IMAGE_PATH="packer/output-ubuntu-airgap/ubuntu-server-airgap"

echo "Testing built image: $IMAGE_PATH"
echo "Starting VM with VNC on port 5900..."
echo "Connect with: vncviewer localhost:5900"
echo ""
echo "Press Ctrl+C to stop the test VM"
echo ""

# Boot the image with VNC
qemu-system-x86_64 \
  -enable-kvm \
  -m 2048 \
  -smp 2 \
  -drive file="$IMAGE_PATH",format=qcow2,if=virtio \
  -net nic,model=virtio \
  -net user,hostfwd=tcp::2222-:22 \
  -vnc :0 \
  -daemonize

echo "VM started! SSH available at: ssh -p 2222 ubuntu@localhost (password: ubuntu)"
echo "VNC available at: localhost:5900"
echo ""
echo "To stop: pkill -f qemu-system-x86_64"
