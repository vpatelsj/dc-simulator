# DC Simulator - Usage Guide

## Complete Setup and Usage Instructions

### Initial Setup

**Step 1: Log out and back in to WSL** (after adding yourself to kvm group)
```bash
# Close WSL terminal and reopen it
# Or from PowerShell:
wsl --shutdown
# Then start WSL again
```

**Step 2: Run the setup script**
```bash
cd /home/vapa/dev/dc-simulator
./setup.sh
```

This will:
- Check prerequisites (KVM, QEMU, Docker, Python)
- Create directory structure
- Download Ubuntu netboot files
- Setup network bridge
- Create configuration files

**Step 3: Install Python dependencies**
```bash
pip3 install -r requirements.txt
```

**Step 4: Test your setup**
```bash
./test.sh
```

### Starting the Environment

**Start all services:**
```bash
./start.sh
```

This starts:
1. OpenBMC container (BMC firmware)
2. PXE server container (DHCP/TFTP/HTTP)
3. Network bridge for VMs

### Creating and Managing VMs

**Create a new VM:**
```bash
python3 src/vm_manager.py create --name ubuntu01 --memory 2048 --cpus 2 --disk 20
```

**Start VM with PXE boot:**
```bash
python3 src/vm_manager.py start --name ubuntu01 --boot pxe
```

**Start VM with disk boot:**
```bash
python3 src/vm_manager.py start --name ubuntu01 --boot disk
```

**Stop a VM:**
```bash
python3 src/vm_manager.py stop --name ubuntu01
```

**List all VMs:**
```bash
python3 src/vm_manager.py list
```

### Using BMC Features

**Access Redfish API:**
```bash
# Get system information
curl -k https://localhost:8443/redfish/v1/Systems/1

# Set boot device to PXE
curl -k -X PATCH https://localhost:8443/redfish/v1/Systems/1 \
  -H "Content-Type: application/json" \
  -d '{"Boot": {"BootSourceOverrideTarget": "Pxe", "BootSourceOverrideEnabled": "Once"}}'

# Power on system
curl -k -X POST https://localhost:8443/redfish/v1/Systems/1/Actions/ComputerSystem.Reset \
  -H "Content-Type: application/json" \
  -d '{"ResetType": "On"}'
```

**Use IPMI commands:**
```bash
# Install ipmitool if needed
sudo apt-get install ipmitool

# Get chassis power status
ipmitool -I lanplus -H 192.168.100.10 -U openbmc -P 0penBmc chassis power status

# Set boot device to PXE
ipmitool -I lanplus -H 192.168.100.10 -U openbmc -P 0penBmc chassis bootdev pxe

# Power on
ipmitool -I lanplus -H 192.168.100.10 -U openbmc -P 0penBmc chassis power on

# Get sensor data
ipmitool -I lanplus -H 192.168.100.10 -U openbmc -P 0penBmc sensor list
```

**SSH to OpenBMC:**
```bash
ssh openbmc@localhost -p 2222
# Password: 0penBmc
```

### Using BMC Bridge (Advanced)

The BMC Bridge connects BMC commands to VM operations:

```bash
# PXE boot a VM via BMC
python3 src/bmc_bridge.py pxe-boot ubuntu01

# Get BMC status
python3 src/bmc_bridge.py status ubuntu01
```

### Connecting to VMs

**Via VNC:**
```bash
# VMs expose VNC on ports starting from 5901
vncviewer localhost:5901  # For first VM
```

**Via Serial Console:**
```bash
# Serial console exposed via telnet
telnet localhost 5000  # For first VM
```

### Complete PXE Boot Workflow

1. **Setup PXE server with Ubuntu files:**
   ```bash
   ./setup.sh  # Downloads Ubuntu netboot automatically
   ./start.sh  # Starts PXE server
   ```

2. **Create a VM:**
   ```bash
   python3 src/vm_manager.py create --name server01 --memory 4096 --cpus 4
   ```

3. **Configure boot via BMC:**
   ```bash
   # Set next boot to PXE
   curl -k -X PATCH https://localhost:8443/redfish/v1/Systems/1 \
     -H "Content-Type: application/json" \
     -d '{"Boot": {"BootSourceOverrideTarget": "Pxe", "BootSourceOverrideEnabled": "Once"}}'
   ```

4. **Start VM:**
   ```bash
   python3 src/vm_manager.py start --name server01 --boot pxe
   ```

5. **Monitor installation:**
   ```bash
   # Connect via VNC or serial console
   telnet localhost 5000
   ```

### Monitoring and Logs

**View container logs:**
```bash
docker logs bmc-openbmc
docker logs bmc-pxe
```

**View BMC logs:**
```bash
ls -la logs/
tail -f logs/*.log
```

**Check VM status:**
```bash
# List running VMs
ps aux | grep qemu

# Check VM network
ip addr show br0
```

### Stopping Everything

```bash
./stop.sh
```

This stops:
- All running VMs
- OpenBMC container
- PXE server container

### Troubleshooting

**KVM not accessible:**
```bash
# Check if you're in kvm group
groups | grep kvm

# If not, add yourself and restart WSL
sudo usermod -aG kvm $USER
wsl --shutdown  # From PowerShell
```

**Container network issues:**
```bash
# Recreate network
docker network rm bmc-net
./start.sh
```

**PXE boot not working:**
```bash
# Check DHCP/TFTP logs
docker logs bmc-pxe

# Verify netboot files
ls -la images/ubuntu/

# Test TFTP
tftp localhost 69
tftp> get pxelinux.0
```

**VM won't start:**
```bash
# Check if KVM is working
qemu-system-x86_64 -enable-kvm -version

# Verify bridge exists
ip link show br0

# Check for conflicts
ps aux | grep qemu
```

### Advanced Customization

**Custom Ubuntu autoinstall:**
1. Create `user-data` and `meta-data` files
2. Place in `containers/pxe-server/http/`
3. Configure PXE menu to use autoinstall

**Multiple VMs:**
```bash
# Create multiple VMs
for i in {1..5}; do
    python3 src/vm_manager.py create --name server0$i --memory 2048 --cpus 2
done

# Start them all
for i in {1..5}; do
    python3 src/vm_manager.py start --name server0$i --boot pxe
done
```

**Custom network configuration:**
- Edit `config/network.conf`
- Modify `containers/pxe-server/config/dnsmasq.conf`
- Restart services with `./stop.sh && ./start.sh`

### Architecture Summary

```
┌──────────────────────────────────────────────────────────────┐
│                      Your Laptop (Windows + WSL2)            │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐ │
│  │                    Docker/Podman                       │ │
│  │                                                        │ │
│  │  ┌──────────────┐         ┌─────────────────────┐   │ │
│  │  │  OpenBMC     │         │   PXE Server        │   │ │
│  │  │  Container   │         │   Container         │   │ │
│  │  │              │         │                     │   │ │
│  │  │ • Redfish    │         │ • DHCP (dnsmasq)   │   │ │
│  │  │ • IPMI       │         │ • TFTP (netboot)   │   │ │
│  │  │ • SSH        │         │ • HTTP (nginx)     │   │ │
│  │  │              │         │                     │   │ │
│  │  │ :8443, :623  │         │ :8080, :69         │   │ │
│  │  └──────────────┘         └─────────────────────┘   │ │
│  │         │                          │                 │ │
│  │         └──────────┬───────────────┘                 │ │
│  │                    │                                 │ │
│  │              bmc-net (192.168.100.0/24)             │ │
│  └────────────────────────────────────────────────────────┘ │
│                       │                                      │
│  ┌────────────────────┴───────────────────────────────────┐ │
│  │               QEMU/KVM VMs (Host Network)             │ │
│  │                                                        │ │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐           │ │
│  │  │ Ubuntu   │  │ Ubuntu   │  │ Ubuntu   │           │ │
│  │  │ VM 1     │  │ VM 2     │  │ VM 3     │    ...    │ │
│  │  │          │  │          │  │          │           │ │
│  │  │ PXE Boot │  │ PXE Boot │  │ PXE Boot │           │ │
│  │  └──────────┘  └──────────┘  └──────────┘           │ │
│  │                                                        │ │
│  │                  br0 (192.168.100.254/24)            │ │
│  └────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────┘
```

### Next Steps

1. Complete the initial setup
2. Create your first VM
3. PXE boot Ubuntu
4. Experiment with BMC commands
5. Automate VM provisioning
6. Build your own infrastructure!

Enjoy your BMC emulator! 🚀
