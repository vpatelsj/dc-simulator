#!/bin/bash

# Quick test script to verify t# Test 3: Check Python
echo ""
echo "3. Checking Python..."setup

echo "BMC Emulator - Quick Test"
echo "=========================="
echo ""

# Test 1: Check KVM
echo "1. Checking KVM support..."
if [ -e /dev/kvm ]; then
    echo "   ✓ KVM device found"
    if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
        echo "   ✓ KVM accessible"
    else
        echo "   ✗ KVM not accessible (need to log out/in after adding to kvm group)"
    fi
else
    echo "   ✗ KVM not found"
fi

# Test 2: Check QEMU
echo ""
echo "2. Checking QEMU..."
if command -v qemu-system-x86_64 &> /dev/null; then
    echo "   ✓ QEMU installed"
    qemu-system-x86_64 --version | head -n1
else
    echo "   ✗ QEMU not installed"
fi

# Test 3: Check Python
echo ""
echo "4. Checking Python..."
if command -v python3 &> /dev/null; then
    echo "   ✓ Python 3 found"
    python3 --version
else
    echo "   ✗ Python 3 not found"
fi

# Test 4: Check network
echo ""
echo "4. Checking network..."
if ip link show br0 &> /dev/null; then
    echo "   ✓ Bridge br0 exists"
    ip addr show br0 | grep "inet "
else
    echo "   ✗ Bridge br0 not found"
fi

echo ""
echo "=========================="
echo "Test complete!"
