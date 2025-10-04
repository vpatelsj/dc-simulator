# System Architecture: Air-Gapped PXE Deployment

## Complete System Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                                                                             │
│                     DC SIMULATOR WITH PACKER DEPLOYMENT                     │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│  BUILD PHASE (One-Time, ~20 minutes)                                        │
│                                                                             │
│  ┌──────────────┐     ┌──────────────────┐     ┌───────────────────┐      │
│  │ Ubuntu ISO   │────▶│ Packer Builder   │────▶│ Custom Image      │      │
│  │ (1.4 GB)     │     │                  │     │ (700 MB)          │      │
│  │              │     │ • Boot VM        │     │                   │      │
│  │ Download     │     │ • Autoinstall    │     │ Ready for         │      │
│  │ Once         │     │ • Provision      │     │ Deployment        │      │
│  │              │     │ • Clean          │     │                   │      │
│  └──────────────┘     │ • Compress       │     └───────────────────┘      │
│                       └──────────────────┘              │                  │
│                                                          │                  │
│  Scripts:                                                ▼                  │
│  • download_ubuntu_iso.sh                  images/custom/ubuntu.qcow2      │
│  • build_packer_image.sh                                                   │
└─────────────────────────────────────────────────────────────────────────────┘

                                    │
                                    │ setup_pxe_deployment.sh
                                    ▼

┌─────────────────────────────────────────────────────────────────────────────┐
│  DEPLOYMENT INFRASTRUCTURE (Persistent Services)                            │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │  Docker Container: bmc-pxe                                          │   │
│  │                                                                     │   │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────────┐ │   │
│  │  │ DHCP Server  │  │ TFTP Server  │  │ HTTP Server (Nginx)      │ │   │
│  │  │              │  │              │  │                          │ │   │
│  │  │ Assigns IPs  │  │ Serves:      │  │ Serves:                  │ │   │
│  │  │ .100 - .200  │  │ • pxelinux   │  │ • Custom image (700MB)   │ │   │
│  │  │              │  │ • Boot menu  │  │ • Deploy scripts         │ │   │
│  │  │              │  │ • Kernel     │  │ • Status dashboard       │ │   │
│  │  │              │  │ • initrd     │  │                          │ │   │
│  │  └──────────────┘  └──────────────┘  └──────────────────────────┘ │   │
│  │                                                                     │   │
│  │  Network: br0 (192.168.100.1/24)                                   │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │  Docker Container: bmc-openbmc                                      │   │
│  │                                                                     │   │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐            │   │
│  │  │ IPMI API     │  │ Redfish API  │  │ SSH Access   │            │   │
│  │  │ Port 623     │  │ Port 5000    │  │ Port 22      │            │   │
│  │  └──────────────┘  └──────────────┘  └──────────────┘            │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘

                                    │
                                    │ vm_manager.py start --boot pxe
                                    ▼

┌─────────────────────────────────────────────────────────────────────────────┐
│  DEPLOYMENT PHASE (Per VM, 2-5 minutes)                                     │
│                                                                             │
│  ┌────────────────────────────────────────────────────────────────────┐    │
│  │  Virtual Machine (QEMU/KVM)                                        │    │
│  │                                                                    │    │
│  │  Step 1: PXE Boot                                                  │    │
│  │  ┌──────────────────────────────────────────────────────────┐     │    │
│  │  │ VM powers on → PXE boot ROM → Broadcast DHCP request     │     │    │
│  │  └──────────────────────────────────────────────────────────┘     │    │
│  │                              │                                     │    │
│  │                              ▼                                     │    │
│  │  Step 2: Network Configuration                                    │    │
│  │  ┌──────────────────────────────────────────────────────────┐     │    │
│  │  │ DHCP assigns IP: 192.168.100.XXX                         │     │    │
│  │  │ Provides PXE server: 192.168.100.1                       │     │    │
│  │  └──────────────────────────────────────────────────────────┘     │    │
│  │                              │                                     │    │
│  │                              ▼                                     │    │
│  │  Step 3: Boot Files Download (TFTP)                               │    │
│  │  ┌──────────────────────────────────────────────────────────┐     │    │
│  │  │ Download: pxelinux.0, boot menu, kernel, initrd         │     │    │
│  │  │ Size: ~50 MB                                             │     │    │
│  │  │ Time: 10-30 seconds                                      │     │    │
│  │  └──────────────────────────────────────────────────────────┘     │    │
│  │                              │                                     │    │
│  │                              ▼                                     │    │
│  │  Step 4: Boot Linux Kernel                                        │    │
│  │  ┌──────────────────────────────────────────────────────────┐     │    │
│  │  │ Kernel boots with initrd                                 │     │    │
│  │  │ Runs: boot=casper url=http://192.168.100.1:8080/...     │     │    │
│  │  └──────────────────────────────────────────────────────────┘     │    │
│  │                              │                                     │    │
│  │                              ▼                                     │    │
│  │  Step 5: Image Download (HTTP)                                    │    │
│  │  ┌──────────────────────────────────────────────────────────┐     │    │
│  │  │ wget http://192.168.100.1:8080/images/ubuntu.qcow2      │     │    │
│  │  │ Size: ~700 MB                                            │     │    │
│  │  │ Time: 1-3 minutes (depends on network)                  │     │    │
│  │  └──────────────────────────────────────────────────────────┘     │    │
│  │                              │                                     │    │
│  │                              ▼                                     │    │
│  │  Step 6: Write to Disk                                            │    │
│  │  ┌──────────────────────────────────────────────────────────┐     │    │
│  │  │ qemu-img convert -O raw ubuntu.qcow2 /dev/vda           │     │    │
│  │  │ Time: 1-2 minutes                                        │     │    │
│  │  └──────────────────────────────────────────────────────────┘     │    │
│  │                              │                                     │    │
│  │                              ▼                                     │    │
│  │  Step 7: Expand & Reboot                                          │    │
│  │  ┌──────────────────────────────────────────────────────────┐     │    │
│  │  │ growpart /dev/vda 1                                      │     │    │
│  │  │ resize2fs /dev/vda1                                      │     │    │
│  │  │ reboot                                                   │     │    │
│  │  └──────────────────────────────────────────────────────────┘     │    │
│  │                              │                                     │    │
│  │                              ▼                                     │    │
│  │  Step 8: Working System                                           │    │
│  │  ┌──────────────────────────────────────────────────────────┐     │    │
│  │  │ ✓ Ubuntu 22.04 fully installed                          │     │    │
│  │  │ ✓ All packages configured                               │     │    │
│  │  │ ✓ SSH accessible (ubuntu/ubuntu)                        │     │    │
│  │  │ ✓ Ready for use                                         │     │    │
│  │  └──────────────────────────────────────────────────────────┘     │    │
│  │                                                                    │    │
│  │  Access:                                                           │    │
│  │  • VNC: localhost:590X                                             │    │
│  │  • Serial: telnet localhost:500X                                   │    │
│  │  • SSH: ubuntu@<vm-ip> (password: ubuntu)                          │    │
│  └────────────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│  SCALE: Deploy Multiple VMs Simultaneously                                  │
│                                                                             │
│  [VM1]     [VM2]     [VM3]     [VM4]     ...     [VM100]                   │
│    │         │         │         │                  │                       │
│    └─────────┴─────────┴─────────┴──────────────────┘                       │
│                           │                                                 │
│              All download same image in parallel                            │
│                           │                                                 │
│                  Limited only by network bandwidth                          │
│                (Not by build time - image built once!)                      │
└─────────────────────────────────────────────────────────────────────────────┘
```

## File Flow Diagram

```
PROJECT STRUCTURE WITH PACKER

apollo-simulator/
│
├── 🔨 BUILD TOOLS
│   ├── packer/
│   │   ├── airgap-ubuntu.pkr.hcl         ─────────┐
│   │   ├── http/                                   │
│   │   │   ├── user-data                          │ Packer reads these
│   │   │   └── meta-data                          │
│   │   └── README.md                     ──────────┘
│   │
│   └── scripts/
│       ├── download_ubuntu_iso.sh         ───┐
│       ├── build_packer_image.sh          ───┤ Build pipeline
│       ├── setup_pxe_deployment.sh        ───┤
│       └── build_and_deploy.sh            ───┘
│
├── 💾 IMAGES (Build Artifacts)
│   ├── iso/
│   │   └── ubuntu-22.04.3.iso            ← Downloaded by script
│   │
│   ├── custom/
│   │   └── ubuntu-server-airgap.qcow2    ← Built by Packer
│   │
│   └── vms/
│       ├── ubuntu01.qcow2                ← Created per VM
│       ├── ubuntu02.qcow2
│       └── ubuntu03.qcow2
│
├── 🌐 PXE SERVER DATA
│   └── pxe-data/
│       ├── tftp/
│       │   ├── pxelinux.0                ← Boot loader
│       │   ├── boot/
│       │   │   ├── vmlinuz               ← Kernel
│       │   │   └── initrd.gz             ← Initial RAM disk
│       │   └── pxelinux.cfg/
│       │       └── default               ← Boot menu
│       │
│       └── http/
│           ├── images/
│           │   └── ubuntu-server-airgap.qcow2  ← Copy of built image
│           ├── scripts/
│           │   └── deploy-image.sh       ← Deployment automation
│           └── index.html                ← Status dashboard
│
├── 🐳 CONTAINERS
│   ├── openbmc/                          ← BMC emulation
│   └── pxe-server/                       ← PXE services
│
├── ⚙️ CONFIGURATION
│   ├── config/
│   │   ├── network.conf                  ← Network settings
│   │   └── vms.yaml                      ← VM definitions
│   │
│   └── src/
│       ├── vm_manager.py                 ← VM lifecycle
│       └── bmc_bridge.py                 ← BMC integration
│
└── 📚 DOCUMENTATION
    ├── README.md                         ← Project overview
    ├── QUICKREF.md                       ← Quick reference
    ├── AIRGAP_DEPLOYMENT.md              ← Deployment guide
    ├── IMPLEMENTATION.md                 ← Technical details
    └── ARCHITECTURE.md (this file)       ← System architecture
```

## Data Flow Timeline

```
TIME: 0 min (One-Time Setup)
┌─────────────────────────────────────────────────────┐
│ ADMINISTRATOR                                       │
│ ./scripts/build_and_deploy.sh                      │
└─────────────────────────────────────────────────────┘
                    │
                    ▼
TIME: 0-10 min (Download)
┌─────────────────────────────────────────────────────┐
│ download_ubuntu_iso.sh                              │
│ Downloads: Ubuntu ISO (1.4 GB)                      │
│ Result: images/iso/ubuntu-22.04.3.iso               │
└─────────────────────────────────────────────────────┘
                    │
                    ▼
TIME: 10-30 min (Build)
┌─────────────────────────────────────────────────────┐
│ build_packer_image.sh                               │
│ Packer: Builds custom image                         │
│ - Installs Ubuntu                                   │
│ - Provisions packages                               │
│ - Cleans and compresses                             │
│ Result: images/custom/ubuntu-server-airgap.qcow2    │
└─────────────────────────────────────────────────────┘
                    │
                    ▼
TIME: 30-32 min (PXE Setup)
┌─────────────────────────────────────────────────────┐
│ setup_pxe_deployment.sh                             │
│ - Copies image to pxe-data/http/images/             │
│ - Downloads netboot files                           │
│ - Creates deployment scripts                        │
│ - Configures boot menu                              │
└─────────────────────────────────────────────────────┘
                    │
                    ▼
TIME: 32 min+ (Ready for Deployments)
┌─────────────────────────────────────────────────────┐
│ System Ready!                                       │
│ Can now deploy unlimited VMs (2-5 min each)         │
└─────────────────────────────────────────────────────┘

════════════════════════════════════════════════════════

TIME: 0 min (Deploy VM #1)
┌─────────────────────────────────────────────────────┐
│ ADMINISTRATOR                                       │
│ python3 src/vm_manager.py start --boot pxe          │
└─────────────────────────────────────────────────────┘
                    │
                    ▼
TIME: 0-0.5 min (Boot)
┌─────────────────────────────────────────────────────┐
│ VM: PXE boot, DHCP, TFTP (50 MB)                    │
└─────────────────────────────────────────────────────┘
                    │
                    ▼
TIME: 0.5-3 min (Download)
┌─────────────────────────────────────────────────────┐
│ VM: Download image via HTTP (700 MB)                │
└─────────────────────────────────────────────────────┘
                    │
                    ▼
TIME: 3-5 min (Write & Boot)
┌─────────────────────────────────────────────────────┐
│ VM: Write to disk, expand, reboot                   │
└─────────────────────────────────────────────────────┘
                    │
                    ▼
TIME: 5 min (Ready)
┌─────────────────────────────────────────────────────┐
│ VM: Working Ubuntu system                           │
│ ssh ubuntu@<vm-ip>                                  │
└─────────────────────────────────────────────────────┘

════════════════════════════════════════════════════════

TIME: 5 min (Deploy VMs #2-100)
┌─────────────────────────────────────────────────────┐
│ All subsequent VMs: Same 2-5 minute process         │
│ No rebuild needed - reuse same image                │
│ Can deploy 100s simultaneously                      │
└─────────────────────────────────────────────────────┘
```

## Network Topology

```
                    ┌──────────────────────┐
                    │   Host Machine       │
                    │   (WSL2 / Linux)     │
                    └──────────────────────┘
                              │
        ┌─────────────────────┼─────────────────────┐
        │                     │                     │
        │              Bridge: br0                  │
        │           192.168.100.1/24                │
        │                     │                     │
        ├─────────────────────┼─────────────────────┤
        │                     │                     │
   ┌────▼────┐           ┌───▼────┐          ┌─────▼─────┐
   │  PXE    │           │  BMC   │          │    VMs    │
   │ Server  │           │ Server │          │           │
   │ (Docker)│           │(Docker)│          │  ubuntu01 │
   │         │           │        │          │  ubuntu02 │
   │ DHCP    │           │ IPMI   │          │  ubuntu03 │
   │ TFTP    │           │Redfish │          │    ...    │
   │ HTTP    │           │  SSH   │          │           │
   └─────────┘           └────────┘          └───────────┘
       │                                            │
       │                                            │
       └────────────── Serves Images ───────────────┘
                    (via HTTP)
```

## Component Interactions

```
┌────────────┐        ┌────────────┐        ┌────────────┐
│   User     │        │  Scripts   │        │   Packer   │
└─────┬──────┘        └─────┬──────┘        └─────┬──────┘
      │                     │                      │
      │ 1. Run setup        │                      │
      ├────────────────────>│                      │
      │                     │ 2. Download ISO      │
      │                     ├─────────────────────>│
      │                     │                      │
      │                     │ 3. Build image       │
      │                     ├─────────────────────>│
      │                     │ (20 min)             │
      │                     │<─────────────────────┤
      │                     │ Image ready          │
      │                     │                      │
      │                     │ 4. Setup PXE         │
      │                     ├──────────────────────┐
      │                     │ Copy to HTTP         │
      │                     │<─────────────────────┘
      │<────────────────────┤                      │
      │ Setup complete      │                      │
      │                     │                      │

┌────────────┐        ┌────────────┐        ┌────────────┐
│   User     │        │ VM Manager │        │     VM     │
└─────┬──────┘        └─────┬──────┘        └─────┬──────┘
      │                     │                      │
      │ 5. Start VM (PXE)   │                      │
      ├────────────────────>│ 6. Boot VM           │
      │                     ├─────────────────────>│
      │                     │                      │ 7. PXE boot
      │                     │                      ├────────┐
      │                     │                      │ DHCP   │
      │                     │                      │ TFTP   │
      │                     │                      │<───────┘
      │                     │                      │
      │                     │                      │ 8. Download image
      │                     │                      ├────────┐
      │                     │                      │ HTTP   │
      │                     │                      │ 700 MB │
      │                     │                      │<───────┘
      │                     │                      │
      │                     │                      │ 9. Write to disk
      │                     │                      ├────────┐
      │                     │                      │qemu-img│
      │                     │                      │<───────┘
      │                     │                      │
      │                     │                      │ 10. Reboot
      │                     │ VM ready             │
      │                     │<─────────────────────┤
      │<────────────────────┤                      │
      │ VM accessible       │                      │
```

---

**This architecture provides:**
- ✅ Complete air-gapped operation
- ✅ Fast, repeatable deployments
- ✅ Enterprise-grade automation
- ✅ Scalable to hundreds of VMs
- ✅ Consistent, tested images
