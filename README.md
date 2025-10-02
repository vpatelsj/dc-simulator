# DC Simulator

A local datacenter simulator that provides realistic server management capabilities such as BMC services with IPMI and Redfish APIs and a PXE server. DC Simulator runs OpenBMC services in docker containers and manages QEMU/KVM virtual machines to simulate real datacenter hardware.

## � Features

- ✅ **BMC Emulation**: IPMI and Redfish API endpoints
- ✅ **PXE Network Boot**: Full DHCP/TFTP/HTTP infrastructure  
- ✅ **KVM Acceleration**: High-performance VM execution
- ✅ **Ubuntu Installation**: Automated network-based OS deployment
- ✅ **Container-Based**: Isolated, reproducible environment
- ✅ **WSL2 Optimized**: Designed for Windows development workflows

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      DC Simulator                           │
│                                                              │
│  ┌────────────────┐  ┌──────────────┐  ┌─────────────────┐ │
│  │ BMC Services   │  │ PXE Server   │  │ Virtual Machine │ │
│  │ (Docker)       │  │ (Docker)     │  │ (QEMU/KVM)      │ │
│  │                │  │              │  │                 │ │
│  │ • IPMI API     │  │ • DHCP       │  │ • Ubuntu 22.04  │ │
│  │ • Redfish API  │  │ • TFTP       │  │ • Network Boot  │ │
│  │ • SSH Access   │  │ • HTTP Files │  │ • VNC Console   │ │
│  └────────────────┘  └──────────────┘  └─────────────────┘ │
│         │                    │                   │          │
│         └────────────────────┴───────────────────┘          │
│                  Bridge Network (br0)                       │
│                   192.168.100.0/24                          │
└─────────────────────────────────────────────────────────────┘
```

## 📋 Prerequisites

- **WSL2** on Windows 10/11
- **Docker** installed in WSL2
- **Python 3.8+** with venv support
- **KVM** support (nested virtualization)

> **Note**: Setup script automatically downloads ~120MB of Ubuntu 22.04 netboot files for PXE boot functionality. These files are not included in the repository to keep it lightweight.

## ⚡ Quick Start

### 1. Initial Setup
```bash
# Clone and setup environment
git clone <repository>
cd dc-simulator

# Run setup (creates Python venv, downloads Ubuntu netboot files)
./setup.sh
```

### 2. Start Services
```bash
# Start BMC and PXE services
./start.sh
```

### 3. Create and Boot VM
```bash
# Activate Python environment
source venv/bin/activate

# Create a new VM
python3 src/vm_manager.py create --name ubuntu01 --memory 2048 --cpus 2

# Start VM with PXE boot
python3 src/vm_manager.py start --name ubuntu01 --boot pxe

# List all VMs
python3 src/vm_manager.py list
```

### 4. Access Your VM
```bash
# VNC GUI access (install vncviewer)
vncviewer localhost:5901

# Serial console access
telnet localhost 5001

# Monitor DHCP/TFTP activity
docker logs bmc-pxe
```

## 🎯 Service Endpoints

| Service | Endpoint | Credentials |
|---------|----------|-------------|
| **BMC Redfish API** | `http://localhost:5000/redfish/v1/` | `admin:admin` |
| **BMC SSH** | `ssh root@localhost -p 22` | `root:root` |
| **PXE HTTP Server** | `http://localhost:8080/` | - |
| **VM VNC Console** | `localhost:5901` | - |
| **VM Serial Console** | `telnet localhost 5001` | - |

## 📁 Project Structure

```
dc-simulator/
├── 🐳 containers/
│   ├── openbmc/              # BMC emulation container
│   │   ├── Dockerfile
│   │   ├── scripts/          # IPMI & Redfish APIs
│   │   └── supervisord.conf
│   └── pxe-server/           # PXE boot services
│       ├── Dockerfile
│       ├── config/           # DHCP & HTTP config
│       └── start.sh
├── 💾 images/
│   ├── ubuntu/               # Ubuntu netboot files
│   └── vms/                  # VM disk images (.qcow2)
├── 🔧 src/
│   ├── vm_manager.py         # VM lifecycle management
│   └── bmc_bridge.py         # BMC to VM integration
├── ⚙️ config/
│   ├── network.conf          # Network settings
│   └── vms.yaml              # VM configurations
├── 📜 scripts & utilities
│   ├── setup.sh              # Environment setup
│   ├── start.sh              # Start all services
│   ├── stop.sh               # Stop all services
│   └── test.sh               # System tests
└── 📋 logs/                  # Service logs
```

## 🛠️ Management Commands

### VM Management
```bash
# List all VMs and their status
python3 src/vm_manager.py list

# Create a new VM
python3 src/vm_manager.py create --name <name> --memory <MB> --cpus <count>

# Start VM (boot order: network first, then disk)
python3 src/vm_manager.py start --name <name> --boot pxe

# Start VM (disk boot only)
python3 src/vm_manager.py start --name <name> --boot disk

# Stop a VM
python3 src/vm_manager.py stop --name <name>

# Delete a VM (removes disk image)
python3 src/vm_manager.py delete --name <name>
```

### Service Management
```bash
# Start all services
./start.sh

# Stop all services  
./stop.sh

# View service status
docker ps

# View logs
docker logs bmc-openbmc  # BMC services
docker logs bmc-pxe      # PXE services
```

### Makefile Commands
```bash
# View all available commands
make help

# Install dependencies
make install

# Start services
make start

# Create VM interactively
make create-vm

# Clean up everything
make clean-all
```

## 🔧 Network Configuration

- **Bridge Interface**: `br0` (192.168.100.1/24)
- **DHCP Range**: 192.168.100.100 - 192.168.100.200
- **VM Network**: Bridged to `br0` for PXE boot
- **Container Network**: Host networking for service access

## 🐛 Troubleshooting

### PXE Boot Issues
```bash
# Check DHCP server logs
docker logs bmc-pxe | grep -i dhcp

# Verify bridge network
ip addr show br0

# Test VM network connectivity
ping 192.168.100.1
```

### KVM/Virtualization Issues
```bash
# Check KVM device
ls -la /dev/kvm

# Verify user in KVM group
groups | grep kvm

# Test KVM functionality
qemu-system-x86_64 -enable-kvm -version
```

### Container Issues
```bash
# Rebuild containers
docker system prune -a
./start.sh

# Check container logs
docker logs <container-name>
```

## 📚 Documentation

- **[USAGE.md](USAGE.md)** - Detailed usage examples
- **[TROUBLESHOOTING.md](TROUBLESHOOTING.md)** - Common problems and solutions

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.
