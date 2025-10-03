#!/usr/bin/env python3
"""
VM Manager
Manages QEMU VMs with KVM acceleration and PXE boot support
"""

import argparse
import subprocess
import json
import os
import sys
import yaml
from pathlib import Path

class VMManager:
    def __init__(self, config_path='config/vms.yaml'):
        self.config_path = config_path
        self.load_config()
        self.vm_dir = Path('images/vms')
        self.vm_dir.mkdir(parents=True, exist_ok=True)
    
    def load_config(self):
        """Load VM configuration"""
        try:
            with open(self.config_path, 'r') as f:
                self.config = yaml.safe_load(f)
        except FileNotFoundError:
            # Try to copy from template
            template_path = Path(self.config_path).parent / 'vms.yaml.template'
            if template_path.exists():
                import shutil
                shutil.copy(template_path, self.config_path)
                with open(self.config_path, 'r') as f:
                    self.config = yaml.safe_load(f)
                print(f"Created {self.config_path} from template")
            else:
                # Fallback to empty config
                self.config = {'defaults': {}, 'vms': {}}
    
    def save_config(self):
        """Save VM configuration"""
        with open(self.config_path, 'w') as f:
            yaml.dump(self.config, f, default_flow_style=False)
    
    def create_disk(self, name, size_gb=20):
        """Create a VM disk image"""
        disk_path = self.vm_dir / f'{name}.qcow2'
        
        if disk_path.exists():
            print(f"Disk already exists: {disk_path}")
            return str(disk_path)
        
        cmd = [
            'qemu-img', 'create',
            '-f', 'qcow2',
            str(disk_path),
            f'{size_gb}G'
        ]
        
        print(f"Creating disk: {disk_path} ({size_gb}GB)")
        subprocess.run(cmd, check=True)
        
        return str(disk_path)
    
    def create_vm(self, name, memory=2048, cpus=2, disk_size=20):
        """Create a new VM configuration"""
        
        if name in self.config['vms']:
            print(f"VM '{name}' already exists")
            return False
        
        # Create disk
        disk_path = self.create_disk(name, disk_size)
        
        # Create VM configuration
        vm_config = {
            'name': name,
            'memory': memory,
            'cpus': cpus,
            'disk': disk_path,
            'network': 'br0',
            'mac': self.generate_mac(),
            'vnc_port': self.get_next_vnc_port(),
            'serial_port': self.get_next_serial_port(),
            'state': 'stopped'
        }
        
        self.config['vms'][name] = vm_config
        self.save_config()
        
        print(f"VM '{name}' created successfully")
        print(f"  Memory: {memory}MB")
        print(f"  CPUs: {cpus}")
        print(f"  Disk: {disk_path}")
        print(f"  MAC: {vm_config['mac']}")
        print(f"  VNC: :{vm_config['vnc_port']}")
        
        return True
    
    def build_qemu_command(self, vm_config, boot_mode='disk'):
        """Build QEMU command line"""
        
        cmd = [
            'qemu-system-x86_64',
            '-name', vm_config['name'],
            '-m', str(vm_config['memory']),
            '-smp', str(vm_config['cpus']),
            '-drive', f"file={vm_config['disk']},if=virtio,format=qcow2",
            '-netdev', f"bridge,id=net0,br={vm_config['network']}",
            '-device', f"virtio-net-pci,netdev=net0,mac={vm_config['mac']}",
            '-vnc', f":{vm_config['vnc_port']}",
            '-serial', f"telnet::{vm_config['serial_port']},server,nowait",
            '-daemonize',
            '-pidfile', str(self.vm_dir / f"{vm_config['name']}.pid")
        ]
        
        # Add KVM acceleration if available
        if os.path.exists('/dev/kvm'):
            cmd.extend(['-enable-kvm', '-cpu', 'host'])
        else:
            print("Warning: KVM not available, using software emulation")
        
        # Boot order
        if boot_mode == 'pxe':
            cmd.extend(['-boot', 'order=nc'])  # Network, then disk
            print(f"VM will attempt PXE boot first")
        elif boot_mode == 'disk':
            cmd.extend(['-boot', 'order=c'])  # Disk only
        elif boot_mode == 'pxe-only':
            cmd.extend(['-boot', 'order=n'])  # Network only
        
        return cmd
    
    def start_vm(self, name, boot_mode='disk'):
        """Start a VM"""
        
        if name not in self.config['vms']:
            print(f"VM '{name}' not found")
            return False
        
        vm_config = self.config['vms'][name]
        
        # Check if already running
        pid_file = self.vm_dir / f"{name}.pid"
        if pid_file.exists():
            try:
                with open(pid_file, 'r') as f:
                    pid = int(f.read().strip())
                if os.path.exists(f'/proc/{pid}'):
                    print(f"VM '{name}' is already running (PID: {pid})")
                    return False
            except:
                pass
        
        # Build and run QEMU command
        cmd = self.build_qemu_command(vm_config, boot_mode)
        
        print(f"Starting VM '{name}'...")
        print(f"Command: {' '.join(cmd)}")
        
        try:
            subprocess.run(cmd, check=True)
            vm_config['state'] = 'running'
            self.save_config()
            
            print(f"VM '{name}' started successfully")
            print(f"  VNC: localhost:{5900 + vm_config['vnc_port']}")
            print(f"  Serial: telnet localhost {vm_config['serial_port']}")
            
            return True
        except subprocess.CalledProcessError as e:
            print(f"Failed to start VM: {e}")
            return False
    
    def stop_vm(self, name):
        """Stop a VM"""
        
        if name not in self.config['vms']:
            print(f"VM '{name}' not found")
            return False
        
        pid_file = self.vm_dir / f"{name}.pid"
        
        if not pid_file.exists():
            print(f"VM '{name}' is not running")
            return False
        
        try:
            with open(pid_file, 'r') as f:
                pid = int(f.read().strip())
            
            print(f"Stopping VM '{name}' (PID: {pid})...")
            os.kill(pid, 15)  # SIGTERM
            
            pid_file.unlink()
            
            vm_config = self.config['vms'][name]
            vm_config['state'] = 'stopped'
            self.save_config()
            
            print(f"VM '{name}' stopped")
            return True
        except Exception as e:
            print(f"Failed to stop VM: {e}")
            return False
    
    def list_vms(self):
        """List all VMs"""
        
        if not self.config['vms']:
            print("No VMs configured")
            return
        
        print("\nConfigured VMs:")
        print("-" * 80)
        print(f"{'Name':<15} {'State':<10} {'Memory':<10} {'CPUs':<6} {'MAC Address':<18}")
        print("-" * 80)
        
        for name, vm in self.config['vms'].items():
            # Check actual running state
            pid_file = self.vm_dir / f"{name}.pid"
            state = 'running' if pid_file.exists() else 'stopped'
            
            print(f"{name:<15} {state:<10} {vm['memory']:<10} {vm['cpus']:<6} {vm['mac']:<18}")
    
    def delete_vm(self, name, force=False):
        """Delete a VM and its disk"""
        if name not in self.config['vms']:
            print(f"VM '{name}' not found")
            return False
        
        # Check if running
        pid_file = self.vm_dir / f"{name}.pid"
        if pid_file.exists():
            if not force:
                print(f"VM '{name}' is running. Stop it first or use --force")
                return False
            else:
                print(f"Force stopping VM '{name}'...")
                self.stop_vm(name)
        
        # Remove disk image
        disk_path = self.vm_dir / f"{name}.qcow2"
        if disk_path.exists():
            print(f"Deleting disk: {disk_path}")
            disk_path.unlink()
        
        # Remove from config
        del self.config['vms'][name]
        self.save_config()
        
        print(f"VM '{name}' deleted successfully")
        return True
    
    def generate_mac(self):
        """Generate a MAC address"""
        import random
        mac = [0x52, 0x54, 0x00,
               random.randint(0x00, 0xff),
               random.randint(0x00, 0xff),
               random.randint(0x00, 0xff)]
        return ':'.join(f'{b:02x}' for b in mac)
    
    def get_next_vnc_port(self):
        """Get next available VNC port"""
        used_ports = [vm.get('vnc_port', 0) for vm in self.config['vms'].values()]
        return max(used_ports, default=0) + 1
    
    def get_next_serial_port(self):
        """Get next available serial port"""
        used_ports = [vm.get('serial_port', 5000) for vm in self.config['vms'].values()]
        return max(used_ports, default=5000) + 1


def main():
    parser = argparse.ArgumentParser(description='VM Manager for BMC Emulator')
    subparsers = parser.add_subparsers(dest='command', help='Commands')
    
    # Create VM
    create_parser = subparsers.add_parser('create', help='Create a new VM')
    create_parser.add_argument('--name', required=True, help='VM name')
    create_parser.add_argument('--memory', type=int, default=2048, help='Memory in MB')
    create_parser.add_argument('--cpus', type=int, default=2, help='Number of CPUs')
    create_parser.add_argument('--disk', type=int, default=20, help='Disk size in GB')
    
    # Start VM
    start_parser = subparsers.add_parser('start', help='Start a VM')
    start_parser.add_argument('--name', required=True, help='VM name')
    start_parser.add_argument('--boot', choices=['disk', 'pxe', 'pxe-only'], 
                             default='disk', help='Boot mode')
    
    # Stop VM
    stop_parser = subparsers.add_parser('stop', help='Stop a VM')
    stop_parser.add_argument('--name', required=True, help='VM name')
    
    # List VMs
    list_parser = subparsers.add_parser('list', help='List all VMs')
    
    # Delete VM
    delete_parser = subparsers.add_parser('delete', help='Delete a VM')
    delete_parser.add_argument('--name', required=True, help='VM name')
    delete_parser.add_argument('--force', action='store_true', help='Force delete even if running')
    
    args = parser.parse_args()
    
    manager = VMManager()
    
    if args.command == 'create':
        manager.create_vm(args.name, args.memory, args.cpus, args.disk)
    elif args.command == 'start':
        manager.start_vm(args.name, args.boot)
    elif args.command == 'stop':
        manager.stop_vm(args.name)
    elif args.command == 'list':
        manager.list_vms()
    elif args.command == 'delete':
        manager.delete_vm(args.name, args.force)
    else:
        parser.print_help()


if __name__ == '__main__':
    main()
