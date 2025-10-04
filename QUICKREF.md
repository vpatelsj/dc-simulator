# Quick Reference: Air-Gapped PXE Deployment

## 🚀 Quick Start Commands

### First-Time Setup (Choose One)

#### Option 1: Automated (Recommended)
```bash
./scripts/setup_wizard.sh
```

#### Option 2: Modern Image Deployment (Complete Pipeline)
```bash
./scripts/build_and_deploy.sh
```

#### Option 3: Manual Steps
```bash
./scripts/download_ubuntu_iso.sh       # Download ISO
./scripts/build_packer_image.sh        # Build image (~20 min)
./scripts/setup_pxe_deployment.sh      # Configure PXE
./start.sh                             # Start services
```

#### Option 4: Legacy Netboot
```bash
./setup.sh                             # Download netboot files
./start.sh                             # Start services
```

---

## 📊 Status & Monitoring

```bash
./scripts/status.sh                    # System overview
docker ps                              # Running services
docker logs bmc-pxe                    # PXE server logs
docker logs bmc-openbmc                # BMC logs
```

---

## 🖥️ VM Management

### Create VM
```bash
python3 src/vm_manager.py create --name <name> --memory <MB> --cpus <count>

# Example
python3 src/vm_manager.py create --name ubuntu01 --memory 2048 --cpus 2
```

### Start VM
```bash
# PXE boot (downloads and deploys image)
python3 src/vm_manager.py start --name <name> --boot pxe

# Disk boot (normal boot from disk)
python3 src/vm_manager.py start --name <name> --boot disk
```

### Manage VMs
```bash
python3 src/vm_manager.py list         # List all VMs
python3 src/vm_manager.py stop --name <name>   # Stop VM
python3 src/vm_manager.py delete --name <name> # Delete VM
```

---

## 🔧 Access VMs

### VNC Console
```bash
vncviewer localhost:5901               # ubuntu01
vncviewer localhost:5902               # ubuntu02
# Port = 5900 + vnc_port (from config/vms.yaml)
```

### Serial Console
```bash
telnet localhost 5001                  # ubuntu01
telnet localhost 5002                  # ubuntu02
# Port = serial_port (from config/vms.yaml)
```

### SSH
```bash
ssh ubuntu@<vm-ip>
# Password: ubuntu

# Find VM IP
ip neigh | grep br0
docker exec bmc-pxe cat /var/lib/misc/dnsmasq.leases
```

---

## 🏗️ Image Building (Packer)

### Build Custom Image
```bash
cd packer
packer init airgap-ubuntu.pkr.hcl      # One-time: download plugins
packer validate airgap-ubuntu.pkr.hcl  # Validate config
packer build airgap-ubuntu.pkr.hcl     # Build image (~20 min)
```

### Build with Custom Parameters
```bash
packer build \
  -var 'disk_size=40960' \
  -var 'memory=4096' \
  -var 'cpus=4' \
  -var 'vm_name=ubuntu-custom.qcow2' \
  airgap-ubuntu.pkr.hcl
```

### Monitor Build
```bash
# Watch with VNC (if headless=false)
vncviewer localhost:5900

# Watch logs
tail -f /tmp/packer-*.log
```

---

## 🔄 Service Management

### Start/Stop Services
```bash
./start.sh                             # Start all services
./stop.sh                              # Stop all services
docker restart bmc-pxe                 # Restart PXE server
docker restart bmc-openbmc             # Restart BMC
```

### Clean Up
```bash
./cleanup.sh                           # Stop and clean everything
./stop.sh                              # Just stop services
```

---

## 🌐 Service Endpoints

| Service | Endpoint | Credentials |
|---------|----------|-------------|
| BMC Redfish API | http://localhost:5000/redfish/v1/ | admin:admin |
| BMC SSH | ssh root@localhost -p 22 | root:root |
| PXE HTTP | http://localhost:8080/ | - |
| PXE Dashboard | http://192.168.100.1:8080/ | - |
| VM VNC | localhost:590X | - |
| VM Serial | telnet localhost 500X | - |

---

## 📁 Important Files & Directories

```
images/
├── iso/ubuntu-22.04.3-live-server-amd64.iso   # Source ISO
├── custom/ubuntu-server-airgap.qcow2          # Built image
└── vms/*.qcow2                                 # VM disks

packer/
├── airgap-ubuntu.pkr.hcl                       # Build config
└── http/user-data                              # Install config

pxe-data/
├── http/images/ubuntu-server-airgap.qcow2     # Deployment image
└── tftp/                                       # Boot files

config/
├── network.conf                                # Network settings
└── vms.yaml                                    # VM configurations
```

---

## 🐛 Quick Troubleshooting

### PXE Boot Not Working
```bash
docker logs bmc-pxe | grep -i dhcp     # Check DHCP
ip addr show br0                       # Check bridge
ping 192.168.100.1                     # Test connectivity
```

### Image Build Fails
```bash
packer validate airgap-ubuntu.pkr.hcl  # Validate config
ls -la /dev/kvm                        # Check KVM
vncviewer localhost:5900               # Watch build
```

### VM Won't Start
```bash
python3 src/vm_manager.py list         # Check status
ps aux | grep qemu                     # Check processes
cat logs/*.log                         # Check logs
```

### Deployment Fails
```bash
# Test HTTP server
curl http://192.168.100.1:8080/images/ubuntu-server-airgap.qcow2

# Check if image exists
ls -lh pxe-data/http/images/

# Watch deployment via VNC
vncviewer localhost:5901
```

---

## ⚙️ Configuration Files

### Customize Installation
Edit `packer/http/user-data` for packages, users, etc.

### Customize Build
Edit `packer/airgap-ubuntu.pkr.hcl` for disk size, provisioning, etc.

### VM Network Settings
Edit `config/network.conf`

### VM Definitions
Edit `config/vms.yaml`

---

## 📚 Documentation

| Document | Purpose |
|----------|---------|
| README.md | Project overview and quick start |
| AIRGAP_DEPLOYMENT.md | Complete deployment guide |
| packer/README.md | Packer configuration details |
| IMPLEMENTATION.md | Technical implementation details |
| USAGE.md | Detailed usage instructions |
| TROUBLESHOOTING.md | Problem solving guide |

---

## 🎯 Common Workflows

### Deploy Fresh VM (Fast Method)
```bash
# One-time: build image
./scripts/build_and_deploy.sh

# Then for each VM:
python3 src/vm_manager.py create --name ubuntu01
python3 src/vm_manager.py start --name ubuntu01 --boot pxe
# Wait 2-5 minutes
ssh ubuntu@<vm-ip>  # Password: ubuntu
```

### Deploy Fresh VM (Legacy Method)
```bash
# One-time: setup
./setup.sh
./start.sh

# Then for each VM:
python3 src/vm_manager.py create --name ubuntu01
python3 src/vm_manager.py start --name ubuntu01 --boot pxe
# Wait 20-30 minutes, go through installer
```

### Rebuild Custom Image
```bash
# Edit customizations
vim packer/http/user-data

# Rebuild
./scripts/build_packer_image.sh

# Update PXE
./scripts/setup_pxe_deployment.sh
```

### Clone Existing VM
```bash
# Stop source VM
python3 src/vm_manager.py stop --name ubuntu01

# Clone disk
cp images/vms/ubuntu01.qcow2 images/vms/ubuntu02.qcow2

# Create new VM config and start
python3 src/vm_manager.py create --name ubuntu02
python3 src/vm_manager.py start --name ubuntu02 --boot disk
```

---

## 💡 Tips & Best Practices

1. **Always test new images** before mass deployment
2. **Keep image versions** for rollback capability
3. **Monitor first boot** of any new image
4. **Use meaningful VM names** (e.g., web01, db01)
5. **Document customizations** in image manifest
6. **Check disk space** before building (~20GB needed)
7. **Use KVM acceleration** for faster builds
8. **Save Packer logs** for troubleshooting

---

## 🔗 Quick Links

- HashiCorp Packer: https://www.packer.io/
- Ubuntu Autoinstall: https://ubuntu.com/server/docs/install/autoinstall
- QEMU Documentation: https://www.qemu.org/documentation/

---

## 📞 Getting Help

1. Check `./scripts/status.sh` for system status
2. Review relevant documentation (see table above)
3. Check logs: `docker logs bmc-pxe` or `cat logs/*.log`
4. Enable VNC to watch VM boots
5. Validate Packer config: `packer validate`

---

**Version:** 1.0  
**Last Updated:** 2025-10-03
