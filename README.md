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

> **Note**: Setup automatically downloads ~60MB of Ubuntu 20.04 LTS netboot files for PXE boot functionality. These files are not included in the repository to keep it lightweight.

## ⚡ Quick Start

### 1. Initial Setup
```bash
# Clone and setup environment
git clone <repository>
cd dc-simulator

# Install dependencies and setup environment
make install
make setup
```

### 2. Start Services
```bash
# Start BMC and PXE services
make start
```

### 3. Create and Boot VM
```bash
# Create a new VM (interactive)
make create-vm

# Or create with specific parameters
make vm-start  # Interactive start with boot options

# List all VMs
make list-vms
```

### 4. Access Your VM
```bash
# Install VNC viewer first
sudo apt install tigervnc-viewer

# VNC GUI access (recommended for Ubuntu installation)
vncviewer localhost:5901

# Serial console access (alternative)
telnet localhost 5001

# Monitor services
make logs
```

> **Note**: New VMs start with empty disks. Use VNC to complete Ubuntu installation via PXE boot, then restart with disk boot for full networking.

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
│   ├── vms.yaml              # VM configurations (runtime state, git-ignored)
│   └── vms.yaml.template     # Template for vms.yaml
├── 📜 scripts & utilities
│   ├── setup.sh              # Environment setup
│   ├── start.sh              # Start all services
│   ├── stop.sh               # Stop all services
│   ├── cleanup.sh            # Complete cleanup script
│   └── test.sh               # System tests
└── 📋 logs/                  # Service logs
```

> **Note**: `config/vms.yaml` is automatically generated and tracks VM runtime state (running/stopped). It's git-ignored to avoid conflicts. The `vms.yaml.template` file is the tracked version.

## 🛠️ Management Commands

### VM Management
```bash
# Interactive VM management (recommended)
make create-vm    # Create a new VM with prompts
make list-vms     # List all VMs and their status  
make vm-start     # Start a VM with boot options
make vm-stop      # Stop a VM

# Direct VM management (advanced)
python3 src/vm_manager.py list
python3 src/vm_manager.py create --name <name> --memory <MB> --cpus <count>
python3 src/vm_manager.py start --name <name> --boot pxe
python3 src/vm_manager.py start --name <name> --boot disk
python3 src/vm_manager.py stop --name <name>
python3 src/vm_manager.py delete --name <name>
```

### Service Management
```bash
# Recommended: Use make commands
make start        # Start all services
make stop         # Stop all services
make restart      # Restart all services
make status       # Show system status
make logs         # View service logs
make test         # Test system readiness

# Advanced: Direct script access
./start.sh        # Start services directly
./stop.sh         # Stop services directly
docker ps         # View container status
docker logs bmc-openbmc  # BMC service logs
docker logs bmc-pxe      # PXE service logs
```

### Setup & Cleanup Commands
```bash
# Setup
make help         # View all available commands
make install      # Install dependencies
make setup        # Initial setup (downloads netboot)
make setup-pxe    # Alternative PXE setup if netboot fails

# Cleanup Options
make cleanup      # Complete cleanup (interactive)
make clean        # Remove VM disks and logs
make clean-all    # Full cleanup (includes venv)
make clean-everything  # Nuclear cleanup (includes netboot files)
```

## � Recommended Workflow

```bash
# 1. First time setup
make install      # Install system dependencies
make setup        # Download Ubuntu netboot files and create venv
make test         # Verify everything is working

# 2. Daily usage
make start        # Start services
make create-vm    # Create and configure VMs
make logs         # Monitor services
make stop         # Stop services when done

# 3. Maintenance
make status       # Check system health
make cleanup      # Clean temporary files (keeps netboot files)
make clean-all    # Full reset (removes venv too)
```

## �🔧 Network Configuration

- **Bridge Interface**: `br0` (192.168.100.1/24)
- **DHCP Range**: 192.168.100.100 - 192.168.100.200
- **VM Network**: Bridged to `br0` for PXE boot
- **Container Network**: Host networking for service access

## 🐛 Troubleshooting

### Quick Diagnostics
```bash
make status       # Check overall system status
make test         # Run system readiness tests
make logs         # View all service logs
```

### Setup Issues
```bash
# If netboot download fails
make setup-pxe    # Use alternative Ubuntu 20.04 LTS

# Reset everything and start fresh
make clean-everything
make install
make setup
```

### VM Internet Connectivity Issues
```bash
# If Ubuntu installer can't reach mirrors or VMs have no internet:

# 1. Restart services (this reconfigures NAT automatically)
make restart

# 2. Verify NAT rules are in place
sudo iptables -t nat -L POSTROUTING -n | grep 192.168.100

# 3. If still not working, check the main interface
ip route | grep default

# 4. The start script should have configured this automatically
# If it didn't work, check setup.sh or start.sh for errors
```

### PXE Boot Issues
```bash
# Check service logs
make logs

# Check DHCP server specifically
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
# Restart services cleanly
make stop
make start

# Complete reset
make cleanup
make start

# Check container status
docker ps -a
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
