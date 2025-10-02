# Apollo Simulator

A complete BMC (Baseboard Management Controller) simulator that runs OpenBMC in containers and supports PXE booting VMs using QEMU/KVM. Apollo provides a realistic server management environment for development and testing.

## 📚 Documentation

- **[USAGE.md](USAGE.md)** - Complete usage guide with examples
- **[TROUBLESHOOTING.md](TROUBLESHOOTING.md)** - Common issues and solutions
- **[REDFISH_TEST_RESULTS.md](REDFISH_TEST_RESULTS.md)** - Redfish API test results

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        WSL2 Environment                      │
│                                                              │
│  ┌────────────────┐  ┌──────────────┐  ┌─────────────────┐ │
│  │ OpenBMC        │  │ PXE Services │  │ QEMU VMs        │ │
│  │ Container      │  │ Container    │  │ (Ubuntu)        │ │
│  │                │  │              │  │                 │ │
│  │ • IPMI         │  │ • DHCP       │  │ • KVM Accel     │ │
│  │ • Redfish API  │  │ • TFTP       │  │ • Network Boot  │ │
│  │ • Web UI       │  │ • HTTP       │  │ • VM Lifecycle  │ │
│  └────────────────┘  └──────────────┘  └─────────────────┘ │
│         │                    │                   │          │
│         └────────────────────┴───────────────────┘          │
│                      Shared Network                         │
│                      (bridge: br0)                          │
└─────────────────────────────────────────────────────────────┘
```

## Features

- ✅ Real OpenBMC firmware (not emulated)
- ✅ KVM hardware acceleration support
- ✅ PXE boot infrastructure (DHCP/TFTP/HTTP)
- ✅ Ubuntu autoinstall via network boot
- ✅ BMC controls QEMU VM power/boot
- ✅ Easy setup on WSL2

## Prerequisites

- Windows 11 with WSL2
- Nested virtualization enabled (already configured ✅)
- Docker or Podman installed in WSL2
- Python 3.8+

## Quick Start

```bash
# 1. Setup environment
./setup.sh

# 2. Start all services
./start.sh

# 3. Create and boot a VM
python3 vm_manager.py create --name server01 --memory 2048 --cpus 2

# 4. PXE boot the VM
python3 vm_manager.py boot --name server01 --mode pxe
```

## Components

1. **OpenBMC Container** - Real BMC firmware
2. **PXE Boot Server** - DHCP, TFTP, HTTP services
3. **VM Manager** - QEMU VM lifecycle management
4. **BMC API Bridge** - Connect BMC commands to QEMU

## Access Points

- OpenBMC Web UI: https://localhost:8443
- IPMI: `ipmitool -I lanplus -H localhost -U root -P 0penBmc`
- Redfish: https://localhost:8443/redfish/v1/
- VM Serial Console: telnet localhost 5000

## Directory Structure

```
apollo-simulator/
├── containers/
│   ├── openbmc/          # OpenBMC container config
│   └── pxe-server/       # PXE boot services
├── images/
│   ├── ubuntu/           # Ubuntu ISO and netboot files
│   └── vms/              # VM disk images
├── scripts/
│   ├── setup.sh          # Initial setup
│   ├── start.sh          # Start all services
│   └── stop.sh           # Stop all services
├── src/
│   ├── vm_manager.py     # QEMU VM management
│   ├── bmc_bridge.py     # BMC to QEMU bridge
│   └── pxe_config.py     # PXE configuration
└── config/
    ├── network.conf      # Network configuration
    └── vms.yaml          # VM definitions
```

## Next Steps

After adding yourself to the kvm group, log out and log back in to WSL, then run:

```bash
# Verify KVM access
ls -la /dev/kvm
groups | grep kvm

# Test QEMU with KVM
qemu-system-x86_64 -enable-kvm -version
```
