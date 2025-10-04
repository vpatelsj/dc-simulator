# Air-Gapped PXE Deployment Guide

This guide explains how to deploy pre-installed Ubuntu images via PXE boot in air-gapped (no internet) environments using HashiCorp Packer and QEMU.

## Table of Contents

- [Overview](#overview)
- [Why This Approach?](#why-this-approach)
- [Architecture](#architecture)
- [Quick Start](#quick-start)
- [Step-by-Step Guide](#step-by-step-guide)
- [Customization](#customization)
- [Troubleshooting](#troubleshooting)
- [Best Practices](#best-practices)

## Overview

This deployment method uses:
1. **HashiCorp Packer**: Builds custom, pre-installed Ubuntu images
2. **PXE Boot**: Network boots VMs from local infrastructure
3. **Image Deployment**: Writes pre-built images directly to disk
4. **No Internet**: Everything works offline after initial setup

### Deployment Flow

```
┌─────────────────────────────────────────────────────────────┐
│                  One-Time Build Process                      │
│                                                              │
│  Ubuntu ISO ──> Packer ──> Custom Image (.qcow2)           │
│  (download)     (build)    (compressed, ready)              │
│                                                              │
│  Time: ~20 minutes (done once)                              │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│             Repeated Deployment Process                      │
│                                                              │
│  VM PXE Boot ──> Download Image ──> Write to Disk          │
│                  (from local HTTP)   (qemu-img convert)     │
│                                                              │
│  ──> Reboot ──> Working Ubuntu System                       │
│                                                              │
│  Time: 2-5 minutes per VM                                   │
└─────────────────────────────────────────────────────────────┘
```

## Why This Approach?

### Comparison with Traditional Methods

| Feature | Packer + PXE | Manual Install | Cloud-Init Live |
|---------|--------------|----------------|-----------------|
| **Air-gapped** | ✅ Yes | ✅ Yes | ❌ Needs internet |
| **Speed** | ✅ 2-5 min | ❌ 30+ min | ⚠️ 10+ min |
| **Consistency** | ✅ Perfect | ❌ Variable | ⚠️ Good |
| **Automation** | ✅ Full | ❌ Manual | ⚠️ Partial |
| **Scalability** | ✅ 100s at once | ❌ One at a time | ⚠️ Limited |
| **Security** | ✅ Pre-hardened | ⚠️ Manual | ⚠️ Runtime |
| **Enterprise-ready** | ✅ Yes | ❌ No | ⚠️ Limited |

### Real-World Use Cases

This approach is used by:
- **Financial Institutions**: Air-gapped secure environments
- **Government/Military**: Classified networks without internet
- **Healthcare**: HIPAA-compliant isolated networks
- **Manufacturing**: Industrial control systems
- **Enterprise IT**: Consistent server deployments

## Architecture

### Components

```
┌───────────────────────────────────────────────────────────┐
│              Build Environment (One-Time)                 │
│                                                           │
│  ┌──────────────┐                                        │
│  │   Packer     │                                        │
│  │   Builder    │                                        │
│  └──────┬───────┘                                        │
│         │                                                 │
│         ├─> Downloads: Ubuntu ISO (1.4 GB)               │
│         ├─> Installs: Full Ubuntu system                 │
│         ├─> Provisions: Packages, configs                │
│         ├─> Cleans: Machine-specific data                │
│         └─> Outputs: Compressed image (700 MB)           │
│                                                           │
└───────────────────────────────────────────────────────────┘
                          │
                          ▼
┌───────────────────────────────────────────────────────────┐
│           Deployment Environment (Air-Gapped)             │
│                                                           │
│  ┌──────────────┐      ┌──────────────┐                 │
│  │  PXE Server  │      │  HTTP Server │                 │
│  │              │      │              │                 │
│  │  • DHCP      │      │  • Images    │                 │
│  │  • TFTP      │      │  • Scripts   │                 │
│  │  • Boot Menu │      │              │                 │
│  └──────┬───────┘      └──────┬───────┘                 │
│         │                     │                          │
│         └─────────┬───────────┘                          │
│                   │                                      │
│                   ▼                                      │
│  ┌────────────────────────────────────────────┐         │
│  │         Bare-Metal Servers                 │         │
│  │  [VM1]  [VM2]  [VM3]  ...  [VMN]          │         │
│  │                                            │         │
│  │  Each VM:                                  │         │
│  │  1. PXE boots from network                │         │
│  │  2. Gets IP from DHCP                     │         │
│  │  3. Downloads deployment image            │         │
│  │  4. Writes to local disk                  │         │
│  │  5. Reboots into working system           │         │
│  └────────────────────────────────────────────┘         │
│                                                           │
└───────────────────────────────────────────────────────────┘
```

## Quick Start

### Prerequisites

```bash
# Install required packages
sudo apt-get update
sudo apt-get install -y qemu-system-x86 qemu-utils docker.io

# Install Packer
wget -O- https://apt.releases.hashicorp.com/gpg | \
  sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
  https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
  sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install packer

# Verify installations
packer version
qemu-system-x86_64 --version
docker --version
```

### Automated Setup (Recommended)

```bash
# Run complete pipeline
./scripts/build_and_deploy.sh

# This will:
# 1. Download Ubuntu ISO (~1.4GB)
# 2. Build custom image with Packer (~20 min)
# 3. Configure PXE deployment
# 4. Start all services
```

### Manual Setup (Step by Step)

```bash
# Step 1: Download Ubuntu ISO
./scripts/download_ubuntu_iso.sh

# Step 2: Build custom image with Packer
./scripts/build_packer_image.sh

# Step 3: Configure PXE deployment
./scripts/setup_pxe_deployment.sh

# Step 4: Start services
./start.sh

# Step 5: Deploy to VM
python3 src/vm_manager.py create --name ubuntu01
python3 src/vm_manager.py start --name ubuntu01 --boot pxe
```

## Step-by-Step Guide

### 1. Download Ubuntu ISO (One-Time)

```bash
./scripts/download_ubuntu_iso.sh
```

**What it does:**
- Downloads Ubuntu 22.04 Server ISO (~1.4GB)
- Verifies checksum for integrity
- Stores in `images/iso/`

**Files created:**
```
images/iso/ubuntu-22.04.3-live-server-amd64.iso
```

### 2. Build Custom Image with Packer

```bash
./scripts/build_packer_image.sh
```

**What it does:**
1. Initializes Packer and downloads QEMU plugin
2. Creates a VM and boots Ubuntu installer
3. Automatically installs Ubuntu using cloud-init
4. Installs essential packages (qemu-guest-agent, vim, curl, etc.)
5. Configures system for deployment (serial console, networking)
6. Cleans up (removes logs, SSH keys, machine-specific data)
7. Compresses image for faster network transfer

**Build process (~20 minutes):**
```
[0-2 min]   VM creation and boot
[2-15 min]  Ubuntu installation
[15-18 min] Provisioning (packages, configs)
[18-20 min] Cleanup and compression
```

**Monitor build:**
```bash
# Watch build progress
tail -f packer-build.log

# Connect to VNC (if enabled in config)
vncviewer localhost:5900
```

**Files created:**
```
images/custom/ubuntu-server-airgap.qcow2  (~700 MB compressed)
```

### 3. Configure PXE Deployment

```bash
./scripts/setup_pxe_deployment.sh
```

**What it does:**
- Copies custom image to PXE HTTP server
- Downloads netboot files (kernel, initrd)
- Creates deployment scripts
- Configures PXE boot menu
- Sets up HTTP server structure

**Files created:**
```
pxe-data/
├── tftp/
│   ├── boot/
│   │   ├── vmlinuz          # Boot kernel
│   │   └── initrd.gz        # Initial ramdisk
│   ├── pxelinux.0           # PXE bootloader
│   └── pxelinux.cfg/
│       └── default          # Boot menu
└── http/
    ├── images/
    │   └── ubuntu-server-airgap.qcow2  # Deployment image
    ├── scripts/
    │   └── deploy-image.sh             # Deployment script
    └── index.html                       # Status page
```

### 4. Start Services

```bash
./start.sh
```

**What it does:**
- Starts PXE server (DHCP, TFTP, HTTP)
- Starts BMC emulation services
- Creates bridge network

**Services started:**
```
bmc-pxe         PXE boot infrastructure
bmc-openbmc     BMC emulation (IPMI, Redfish)
```

### 5. Deploy to VMs

```bash
# Create VM
python3 src/vm_manager.py create --name ubuntu01 --memory 2048 --cpus 2

# Start with PXE boot
python3 src/vm_manager.py start --name ubuntu01 --boot pxe

# Watch deployment (VNC)
vncviewer localhost:5901

# Or watch serial console
telnet localhost 5001
```

**Deployment process (2-5 minutes):**
```
[0-30 sec]   PXE boot, DHCP, TFTP
[30-180 sec] Download image from HTTP (depends on network)
[180-240 sec] Write image to disk
[240-300 sec] Expand partition, reboot
```

### 6. Access Deployed System

```bash
# SSH (once VM has booted)
ssh ubuntu@<vm-ip>
# Password: ubuntu

# VNC console
vncviewer localhost:5901

# Serial console
telnet localhost 5001
```

## Customization

### Customize Image Contents

Edit `packer/http/user-data` to modify what gets installed:

```yaml
packages:
  - qemu-guest-agent
  - vim
  - curl
  - wget
  - docker.io          # Add Docker
  - nginx              # Add Nginx
  - postgresql         # Add PostgreSQL
  - python3-pip        # Add Python pip
```

### Customize Build Parameters

```bash
# Build with different specs
cd packer
packer build \
  -var 'disk_size=40960' \
  -var 'memory=4096' \
  -var 'cpus=4' \
  -var 'vm_name=ubuntu-custom.qcow2' \
  airgap-ubuntu.pkr.hcl
```

### Create Role-Specific Images

```bash
# Web server image
packer build -var 'vm_name=ubuntu-web.qcow2' airgap-ubuntu.pkr.hcl

# Database server image
packer build -var 'vm_name=ubuntu-db.qcow2' airgap-ubuntu.pkr.hcl

# Customize each with different provisioning scripts
```

### Add Custom Provisioning

Edit `packer/airgap-ubuntu.pkr.hcl`:

```hcl
provisioner "shell" {
  inline = [
    "echo '>>> Installing custom software'",
    "sudo apt-get install -y <your-packages>",
    "sudo systemctl enable <your-service>",
    "echo 'Custom config' | sudo tee /etc/custom.conf"
  ]
}

# Or use external script
provisioner "shell" {
  script = "scripts/custom-provision.sh"
}
```

### Security Hardening

```hcl
provisioner "shell" {
  inline = [
    "# Install security tools",
    "sudo apt-get install -y lynis aide",
    
    "# Apply CIS benchmarks",
    "sudo bash -c 'cat >> /etc/sysctl.conf <<EOF",
    "net.ipv4.conf.all.send_redirects = 0",
    "net.ipv4.conf.default.send_redirects = 0",
    "EOF'",
    
    "# Disable unnecessary services",
    "sudo systemctl disable bluetooth",
    "sudo systemctl disable cups",
    
    "# Configure firewall",
    "sudo ufw default deny incoming",
    "sudo ufw default allow outgoing",
    "sudo ufw allow ssh",
    "sudo ufw --force enable"
  ]
}
```

## Troubleshooting

### Build Issues

#### Packer Hangs During Build

**Symptom:** Build process stops responding

**Solutions:**
```bash
# 1. Enable VNC to see what's happening
# Edit packer/airgap-ubuntu.pkr.hcl:
headless = false

# 2. Connect and watch
vncviewer localhost:5900

# 3. Check if cloud-init is waiting for input
# Look for prompts in VNC

# 4. Verify autoinstall config syntax
cd packer
packer validate airgap-ubuntu.pkr.hcl
```

#### SSH Timeout

**Symptom:** "Timeout waiting for SSH"

**Solutions:**
```bash
# 1. Check if VM booted properly (VNC)
vncviewer localhost:5900

# 2. Verify user-data has SSH enabled
cat packer/http/user-data | grep -A 5 "ssh:"

# 3. Increase timeout in Packer config
ssh_timeout = "60m"  # Increase from 30m
```

#### Build is Very Slow

**Symptom:** Build takes >1 hour

**Solutions:**
```bash
# 1. Check if KVM is available
ls -la /dev/kvm

# 2. Add user to kvm group
sudo usermod -aG kvm $USER
# Re-login

# 3. Verify KVM in use
ps aux | grep qemu | grep -i kvm

# 4. Use local mirror for packages
# Edit packer/http/user-data to use local APT mirror
```

### Deployment Issues

#### VM Won't PXE Boot

**Symptom:** VM doesn't get IP or boot from network

**Solutions:**
```bash
# 1. Check PXE server is running
docker ps | grep bmc-pxe

# 2. Check DHCP logs
docker logs bmc-pxe | grep -i dhcp

# 3. Verify bridge network
ip addr show br0

# 4. Check VM network config
python3 src/vm_manager.py list

# 5. Verify PXE boot order
# VM should have network boot enabled
```

#### Image Download Fails

**Symptom:** "Failed to download image"

**Solutions:**
```bash
# 1. Check HTTP server
curl http://192.168.100.1:8080/images/ubuntu-server-airgap.qcow2

# 2. Check if image exists
ls -lh pxe-data/http/images/

# 3. Verify nginx is serving files
docker exec bmc-pxe ls -la /var/www/html/images/

# 4. Check disk space
df -h
```

#### Image Write Fails

**Symptom:** "Failed to write image to disk"

**Solutions:**
```bash
# 1. Check VM disk size is large enough
qemu-img info images/vms/ubuntu01.qcow2

# 2. Verify qemu-img is available in deployment env
# (Should be installed by deploy-image.sh)

# 3. Check target disk exists
# In deployment, script auto-detects /dev/vda, /dev/sda, etc.
```

### Performance Issues

#### Slow Deployment

**Symptom:** Deployment takes >10 minutes

**Solutions:**
```bash
# 1. Check network performance
docker exec bmc-pxe iftop

# 2. Use uncompressed image for faster write
qemu-img convert -f qcow2 -O qcow2 \
  images/custom/ubuntu-server-airgap.qcow2 \
  images/custom/ubuntu-server-airgap-uncompressed.qcow2

# 3. Monitor VM during deployment
# Watch which step is slow (download vs write)
```

## Best Practices

### Image Management

1. **Version Control**: Tag images with versions
   ```bash
   mv ubuntu-server-airgap.qcow2 ubuntu-server-v1.0.qcow2
   ```

2. **Testing**: Test images before production deployment
   ```bash
   # Deploy to test VM first
   python3 src/vm_manager.py create --name test-vm
   python3 src/vm_manager.py start --name test-vm --boot pxe
   ```

3. **Documentation**: Document what's in each image
   ```bash
   # Create image manifest
   echo "Ubuntu 22.04 - Built $(date)" > ubuntu-server-v1.0.manifest
   echo "Packages: docker, nginx, postgresql" >> ubuntu-server-v1.0.manifest
   ```

4. **Security Scanning**: Scan images for vulnerabilities
   ```bash
   # Mount and scan
   sudo modprobe nbd max_part=8
   sudo qemu-nbd --connect=/dev/nbd0 ubuntu-server-airgap.qcow2
   sudo mount /dev/nbd0p1 /mnt
   sudo lynis audit system --rootdir /mnt
   sudo umount /mnt
   sudo qemu-nbd --disconnect /dev/nbd0
   ```

### Build Process

1. **Automate Builds**: Use CI/CD for image building
2. **Validate Before Deploy**: Always test new images
3. **Keep Build Logs**: Save Packer logs for troubleshooting
4. **Use Variables**: Don't hardcode values in Packer configs

### Deployment

1. **Monitor First Boot**: Watch first deployment of new image
2. **Staged Rollout**: Deploy to subset of VMs first
3. **Backup**: Keep previous image version as backup
4. **Document Changes**: Track what changed between versions

### Security

1. **Minimize Attack Surface**: Only install needed packages
2. **Harden Before Deployment**: Apply security settings in build
3. **Update Regularly**: Rebuild images with security patches
4. **Audit Access**: Log who deploys which images where

## Additional Resources

- [HashiCorp Packer Documentation](https://www.packer.io/docs)
- [Ubuntu Autoinstall](https://ubuntu.com/server/docs/install/autoinstall)
- [QEMU Documentation](https://www.qemu.org/documentation/)
- [PXE Boot Specification](https://en.wikipedia.org/wiki/Preboot_Execution_Environment)

## Support

For detailed Packer configuration options, see [`packer/README.md`](packer/README.md).

For VM management, see [`USAGE.md`](USAGE.md).

For troubleshooting, see [`TROUBLESHOOTING.md`](TROUBLESHOOTING.md).
