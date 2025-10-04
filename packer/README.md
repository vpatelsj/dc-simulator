# Packer-based Air-Gapped Deployment

This directory contains HashiCorp Packer configuration for building custom Ubuntu images that can be deployed via PXE boot in air-gapped (no internet) environments.

## Overview

The Packer build process:
1. Boots Ubuntu installer ISO in QEMU
2. Automatically installs Ubuntu using cloud-init
3. Provisions the system with required packages
4. Cleans and prepares the image for deployment
5. Compresses the final image

## Directory Structure

```
packer/
├── airgap-ubuntu.pkr.hcl    # Main Packer configuration
├── http/                     # Cloud-init configs served during install
│   ├── user-data            # Autoinstall configuration
│   └── meta-data            # Instance metadata
└── README.md                # This file
```

## Prerequisites

### Required Software

```bash
# Install Packer
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install packer

# Install QEMU
sudo apt-get install -y qemu-system-x86 qemu-utils

# Verify installations
packer version
qemu-system-x86_64 --version
```

### Required Files

- Ubuntu 22.04 Server ISO (downloaded automatically by scripts)
- At least 20GB free disk space
- KVM support recommended (for faster builds)

## Quick Start

### Option 1: Automated Build Pipeline

Run the complete build and deployment pipeline:

```bash
cd /home/vapa/dev/apollo-simulator
./scripts/build_and_deploy.sh
```

This will:
1. Download Ubuntu ISO
2. Build custom image
3. Setup PXE deployment
4. Start services

### Option 2: Step-by-Step

```bash
# 1. Download Ubuntu ISO
./scripts/download_ubuntu_iso.sh

# 2. Build image with Packer
./scripts/build_packer_image.sh

# 3. Setup PXE deployment
./scripts/setup_pxe_deployment.sh

# 4. Start services
./start.sh
```

### Option 3: Manual Packer Build

```bash
# Navigate to packer directory
cd packer

# Initialize Packer (download plugins)
packer init airgap-ubuntu.pkr.hcl

# Validate configuration
packer validate airgap-ubuntu.pkr.hcl

# Build the image
packer build airgap-ubuntu.pkr.hcl
```

## Configuration

### Build Variables

You can customize the build by setting variables:

```bash
packer build \
  -var 'disk_size=40960' \
  -var 'memory=4096' \
  -var 'cpus=4' \
  -var 'vm_name=my-custom-ubuntu.qcow2' \
  airgap-ubuntu.pkr.hcl
```

Available variables:
- `iso_path`: Path to Ubuntu ISO
- `disk_size`: Disk size in MB (default: 20480 = 20GB)
- `memory`: RAM in MB (default: 2048)
- `cpus`: Number of CPUs (default: 2)
- `vm_name`: Output image filename
- `output_directory`: Where to save the built image

### Customizing the Installation

Edit `http/user-data` to customize:
- Installed packages
- User accounts
- Network configuration
- Storage layout
- Post-install scripts

Example - Add more packages:

```yaml
packages:
  - qemu-guest-agent
  - vim
  - curl
  - wget
  - docker.io        # Add Docker
  - nginx            # Add Nginx
  - postgresql       # Add PostgreSQL
```

## Build Output

After successful build:

```
images/custom/ubuntu-server-airgap.qcow2
```

This image is:
- Fully installed and configured Ubuntu 22.04
- Compressed for faster network transfer
- Ready to be deployed via PXE
- Generalized (no machine-specific data)

## Deployment

Once built, the image can be deployed via PXE:

```bash
# Setup PXE deployment
./scripts/setup_pxe_deployment.sh

# Start a VM with PXE boot
python3 src/vm_manager.py start --name ubuntu01 --boot pxe
```

The VM will:
1. PXE boot from network
2. Download the custom image
3. Write it to disk
4. Reboot into working Ubuntu

## Troubleshooting

### Build Fails During Installation

**Problem:** Packer build hangs or fails during OS installation

**Solutions:**
- Check VNC display: `vnc://localhost:5900`
- Verify ISO checksum is correct
- Ensure sufficient disk space
- Check `http/user-data` syntax

### SSH Timeout Errors

**Problem:** Packer can't connect via SSH

**Solutions:**
- Verify cloud-init user-data has correct SSH settings
- Check SSH is enabled in autoinstall config
- Increase `ssh_timeout` in Packer config
- Watch VNC to see if system booted properly

### KVM Not Available

**Problem:** Build is very slow (no KVM acceleration)

**Solutions:**
```bash
# Check if KVM is available
ls -la /dev/kvm

# Add user to kvm group
sudo usermod -aG kvm $USER

# Re-login for changes to take effect
```

### Image Too Large

**Problem:** Image is too big for network deployment

**Solutions:**
- Remove unnecessary packages in provisioning
- Enable compression in Packer config (already enabled)
- Use `virt-sparsify` to reduce image size:
  ```bash
  virt-sparsify --compress \
    images/custom/ubuntu-server-airgap.qcow2 \
    images/custom/ubuntu-server-airgap-sparse.qcow2
  ```

## Advanced Usage

### Building Multiple Image Variants

Create different images for different roles:

```bash
# Web server image
packer build -var 'vm_name=ubuntu-web.qcow2' airgap-ubuntu.pkr.hcl

# Database server image
packer build -var 'vm_name=ubuntu-db.qcow2' airgap-ubuntu.pkr.hcl

# Worker node image
packer build -var 'vm_name=ubuntu-worker.qcow2' airgap-ubuntu.pkr.hcl
```

Customize provisioning scripts for each role.

### Parallel Builds

Build multiple images simultaneously:

```bash
packer build -parallel-builds=3 airgap-ubuntu.pkr.hcl
```

### Debugging

Enable debug mode for detailed logs:

```bash
PACKER_LOG=1 packer build airgap-ubuntu.pkr.hcl
```

### Inspecting Built Images

```bash
# Show image info
qemu-img info images/custom/ubuntu-server-airgap.qcow2

# Mount image to inspect contents
sudo modprobe nbd max_part=8
sudo qemu-nbd --connect=/dev/nbd0 images/custom/ubuntu-server-airgap.qcow2
sudo mount /dev/nbd0p1 /mnt
ls -la /mnt
sudo umount /mnt
sudo qemu-nbd --disconnect /dev/nbd0
```

## Performance Tips

1. **Use KVM**: Builds are 5-10x faster with KVM acceleration
2. **Local ISO**: Keep ISO locally (don't download each time)
3. **Fast Storage**: Use SSD for build directory
4. **Adequate RAM**: Give Packer VM at least 2GB RAM
5. **Compression**: Use zstd compression (fastest with good ratio)

## Security Considerations

### Air-Gapped Environments

This setup is designed for air-gapped deployments:
- ✅ No internet required after ISO download
- ✅ All packages come from ISO or local repos
- ✅ Images can be security scanned before deployment
- ✅ Reproducible builds (same input = same output)

### Hardening

To create hardened images:

1. **Security Updates**: Update `http/user-data` to install security patches
2. **CIS Benchmarks**: Add CIS hardening scripts to provisioners
3. **Minimal Packages**: Remove unnecessary packages
4. **Audit**: Use `lynis` or `oscap` to audit image

Example provisioner for hardening:

```hcl
provisioner "shell" {
  inline = [
    "sudo apt-get install -y lynis",
    "sudo lynis audit system --quick",
  ]
}
```

## References

- [Packer Documentation](https://www.packer.io/docs)
- [QEMU Builder](https://www.packer.io/plugins/builders/qemu)
- [Ubuntu Autoinstall](https://ubuntu.com/server/docs/install/autoinstall)
- [Cloud-init](https://cloudinit.readthedocs.io/)

## Support

For issues or questions:
1. Check troubleshooting section above
2. Review Packer logs
3. Test with VNC display enabled
4. Verify cloud-init configuration syntax
