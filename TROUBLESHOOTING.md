# Troubleshooting Guide

## Common Issues and Solutions

### 1. Python Virtual Environment (PEP 668)

**Problem**: `pip install` fails with "externally-managed-environment" error on Ubuntu 24.04+

**Cause**: PEP 668 prevents installing packages globally to protect system Python

**Solution**: Use virtual environment (already set up)
```bash
source venv/bin/activate
pip install -r requirements.txt
```

The `setup.sh` script automatically creates and uses a virtual environment.

---

### 2. Ubuntu Netboot 404 Errors

**Problem**: Cannot download Ubuntu 22.04+ netboot images (404 Not Found)

**Cause**: Ubuntu deprecated traditional netboot for Ubuntu 22.04+ in favor of live-server with autoinstall

**Solution**: Use Ubuntu 20.04 LTS netboot (supported until 2025)
```bash
./pxe_alternative.sh
# Select option 1 for Ubuntu 20.04 LTS
```

The `setup.sh` script now defaults to Ubuntu 20.04 with multiple mirror fallbacks.

---

### 3. Docker Port Forwarding on WSL2

**Problem**: Cannot access Redfish API from host (connection reset)

**Cause**: Docker on WSL2 has known issues with port forwarding on custom bridge networks

**Solution**: Use host networking mode (already configured)
```bash
# The start.sh script now uses --network host
docker run --network host apollo-openbmc
```

Access at: `http://localhost:5000/redfish/v1/`

---

### 4. QEMU Bridge Permission Denied

**Problem**: VM fails to start with "bridge helper failed"

**Cause**: QEMU needs explicit permission to use bridge networking

**Solution**: Create bridge configuration
```bash
sudo mkdir -p /etc/qemu
echo "allow br0" | sudo tee /etc/qemu/bridge.conf
sudo chmod 0644 /etc/qemu/bridge.conf
sudo chmod u+s /usr/lib/qemu/qemu-bridge-helper
```

Already done during setup.

---

### 5. KVM Not Available

**Problem**: QEMU fails with "KVM not available"

**Cause**: Nested virtualization not enabled or user not in kvm group

**Solution**:
```bash
# Check if KVM is available
ls -l /dev/kvm

# Add user to kvm group
sudo usermod -a -G kvm $USER

# Log out and back in, or:
newgrp kvm

# Verify nested virtualization (WSL2)
cat /sys/module/kvm_intel/parameters/nested
# Should show: Y
```

---

### 6. Container Build Fails

**Problem**: Docker build fails with package errors

**Cause**: Outdated package lists or network issues

**Solution**:
```bash
# Rebuild with no cache
docker build --no-cache -t apollo-openbmc containers/openbmc/
docker build --no-cache -t apollo-pxe containers/pxe-server/
```

---

### 7. Network Bridge Not Working

**Problem**: VMs cannot get DHCP or reach PXE server

**Cause**: Bridge not properly configured or Docker network conflicts

**Solution**:
```bash
# Recreate bridge
sudo ip link delete br0 2>/dev/null
sudo ip link add br0 type bridge
sudo ip addr add 192.168.100.1/24 dev br0
sudo ip link set br0 up

# Recreate Docker network
docker network rm bmc-net
docker network create --subnet=192.168.100.0/24 bmc-net
```

---

### 8. Redfish API Returns 404

**Problem**: Endpoints return 404 Not Found

**Cause**: Flask/Gunicorn not properly started

**Solution**:
```bash
# Check if service is running
docker exec bmc-openbmc supervisorctl status

# Restart Redfish service
docker exec bmc-openbmc supervisorctl restart redfish-api

# Check logs
docker logs bmc-openbmc
```

---

### 9. VM Stuck at PXE Boot

**Problem**: VM gets stuck or doesn't boot from network

**Cause**: DHCP/TFTP services not running or files missing

**Solution**:
```bash
# Check PXE server logs
docker logs bmc-pxe

# Verify files exist
ls -la images/ubuntu/pxelinux.0
ls -la images/ubuntu/ubuntu-installer/

# Restart PXE server
docker restart bmc-pxe
```

---

### 10. Permission Denied Errors

**Problem**: Cannot create files or access devices

**Cause**: User permissions or group membership

**Solution**:
```bash
# Add user to necessary groups
sudo usermod -a -G docker,kvm $USER

# Fix directory permissions
sudo chown -R $USER:$USER /home/vapa/dev/apollo-simulator

# Log out and back in for group changes to take effect
```

---

## Quick Diagnostics

### Check System Status
```bash
# All components
make status

# Docker containers
docker ps

# VMs
python src/vm_manager.py list

# Network
ip addr show br0
docker network inspect bmc-net
```

### Check Logs
```bash
# Container logs
docker logs bmc-openbmc
docker logs bmc-pxe

# BMC service logs
docker exec bmc-openbmc cat /var/log/openbmc/redfish.log
docker exec bmc-openbmc cat /var/log/openbmc/ipmi.log

# VM console
telnet localhost 5001  # Replace 5001 with your VM's serial port
```

### Test Connectivity
```bash
# Redfish API
curl http://localhost:5000/redfish/v1/

# SSH to BMC
ssh root@localhost -p 22

# IPMI
ipmitool -I lanplus -H localhost -U admin -P admin power status
```

---

## Getting Help

1. Check logs first (see Quick Diagnostics above)
2. Review this troubleshooting guide
3. Check `README.md` and `USAGE.md` for correct usage
4. Verify system requirements are met
5. Try clean rebuild: `make clean && ./setup.sh`

---

## Known Limitations

- **WSL2**: Requires host networking mode for Redfish API
- **Ubuntu 22.04+**: No traditional netboot, use 20.04 LTS
- **Nested Virtualization**: Required for KVM, must be enabled in hypervisor
- **Bridge Networking**: Requires explicit QEMU permission configuration
- **PEP 668**: Python virtual environment required on modern Ubuntu

---

## Clean Reinstall

If all else fails:
```bash
# Stop everything
./stop.sh

# Remove all containers and networks
docker rm -f bmc-openbmc bmc-pxe
docker network rm bmc-net
sudo ip link delete br0

# Clean project
make clean-all

# Start fresh
./setup.sh
./start.sh
```
