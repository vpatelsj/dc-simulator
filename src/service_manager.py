#!/usr/bin/env python3
"""
Service Manager - Native Services (No Docker)
Manages dnsmasq, nginx, and BMC simulator services
"""

import subprocess
import os
import sys
from pathlib import Path
import time
import signal

class ServiceManager:
    def __init__(self, base_dir=None):
        if base_dir:
            self.base_dir = Path(base_dir).resolve()
        else:
            self.base_dir = Path(__file__).parent.parent.resolve()
        
        self.pxe_tftp_dir = self.base_dir / 'pxe-data' / 'tftp'
        self.pxe_http_dir = self.base_dir / 'pxe-data' / 'http'
        self.logs_dir = self.base_dir / 'logs'
        self.run_dir = self.base_dir / 'run'
        
        # Create directories
        self.pxe_tftp_dir.mkdir(parents=True, exist_ok=True)
        self.pxe_http_dir.mkdir(parents=True, exist_ok=True)
        self.logs_dir.mkdir(parents=True, exist_ok=True)
        self.run_dir.mkdir(parents=True, exist_ok=True)
    
    def is_service_running(self, service_name):
        """Check if a systemd service is running"""
        try:
            result = subprocess.run(
                ['systemctl', 'is-active', service_name],
                capture_output=True,
                text=True
            )
            return result.returncode == 0
        except Exception:
            return False
    
    def is_process_running(self, pid_file):
        """Check if a process is running based on PID file"""
        pid_path = Path(pid_file)
        if not pid_path.exists():
            return False
        
        try:
            with open(pid_path, 'r') as f:
                pid = int(f.read().strip())
            
            # Check if process exists
            os.kill(pid, 0)
            return True
        except (ValueError, ProcessLookupError, PermissionError):
            return False
    
    def check_dependencies(self):
        """Check if required packages are installed"""
        print("Checking dependencies...")
        missing = []
        
        packages = {
            'dnsmasq': 'dnsmasq',
            'nginx': 'nginx',
            'python3': 'python3'
        }
        
        for cmd, pkg in packages.items():
            try:
                subprocess.run(['which', cmd], capture_output=True, check=True)
                print(f"  ✓ {pkg}")
            except subprocess.CalledProcessError:
                print(f"  ✗ {pkg} - NOT INSTALLED")
                missing.append(pkg)
        
        if missing:
            print(f"\nMissing packages: {', '.join(missing)}")
            print("\nInstall with:")
            print(f"  sudo apt-get install -y {' '.join(missing)}")
            return False
        
        print("All dependencies installed ✓")
        return True
    
    def configure_dnsmasq(self):
        """Configure dnsmasq for PXE boot"""
        print("\nConfiguring dnsmasq...")
        
        config_content = f"""# Apollo Simulator PXE Configuration
interface=br0
bind-interfaces

# DHCP configuration
dhcp-range=192.168.100.100,192.168.100.200,12h
dhcp-option=3,192.168.100.1    # Gateway
dhcp-option=6,8.8.8.8          # DNS

# TFTP configuration
enable-tftp
tftp-root={self.pxe_tftp_dir}

# PXE boot
dhcp-boot=pxelinux.0

# Disable DNS (port 0 = don't run DNS)
port=0

# Logging
log-dhcp
log-queries
"""
        
        config_file = Path('/etc/dnsmasq.d/apollo-simulator.conf')
        
        try:
            # Write config using sudo
            subprocess.run(
                ['sudo', 'tee', str(config_file)],
                input=config_content.encode(),
                capture_output=True,
                check=True
            )
            print(f"  ✓ Configuration written to {config_file}")
            
            # Create systemd service file for apollo-dnsmasq
            self._create_dnsmasq_service()
            
            return True
        except subprocess.CalledProcessError as e:
            print(f"  ✗ Failed to write config: {e}")
            return False
    
    def _create_dnsmasq_service(self):
        """Create a dedicated systemd service for Apollo dnsmasq"""
        service_content = f"""[Unit]
Description=Apollo Simulator - dnsmasq (DHCP/TFTP)
After=network.target

[Service]
Type=simple
ExecStart=/usr/sbin/dnsmasq --no-daemon --conf-file=/etc/dnsmasq.d/apollo-simulator.conf
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
"""
        
        try:
            subprocess.run(
                ['sudo', 'tee', '/etc/systemd/system/apollo-dnsmasq.service'],
                input=service_content.encode(),
                capture_output=True,
                check=True
            )
            subprocess.run(['sudo', 'systemctl', 'daemon-reload'], check=True)
            print("  ✓ Systemd service created: apollo-dnsmasq.service")
        except Exception as e:
            print(f"  ⚠ Could not create systemd service: {e}")
    
    def configure_nginx(self):
        """Configure nginx for HTTP image serving"""
        print("\nConfiguring nginx...")
        
        config_content = f"""server {{
    listen 8080;
    server_name _;
    
    root {self.pxe_http_dir};
    
    location / {{
        autoindex on;
        autoindex_exact_size off;
        autoindex_localtime on;
    }}
    
    location /images/ {{
        alias {self.pxe_http_dir}/images/;
        autoindex on;
    }}
}}
"""
        
        config_file = Path('/etc/nginx/sites-available/apollo-simulator')
        enabled_link = Path('/etc/nginx/sites-enabled/apollo-simulator')
        
        try:
            # Write config
            subprocess.run(
                ['sudo', 'tee', str(config_file)],
                input=config_content.encode(),
                capture_output=True,
                check=True
            )
            
            # Enable site
            if not enabled_link.exists():
                subprocess.run(
                    ['sudo', 'ln', '-sf', str(config_file), str(enabled_link)],
                    check=True
                )
            
            # Test config
            subprocess.run(['sudo', 'nginx', '-t'], check=True, capture_output=True)
            
            print(f"  ✓ Configuration written and tested")
            return True
        except subprocess.CalledProcessError as e:
            print(f"  ✗ Failed to configure nginx: {e}")
            return False
    
    def _create_bmc_service(self):
        """Create systemd service for BMC Redfish API"""
        service_content = f"""[Unit]
Description=Apollo Simulator - BMC Redfish API
After=network.target

[Service]
Type=simple
User={os.getenv('USER', 'vapa')}
WorkingDirectory={self.base_dir}
ExecStart=/usr/bin/python3 {self.base_dir}/containers/openbmc/scripts/redfish_api.py
StandardOutput=append:{self.logs_dir}/redfish.log
StandardError=append:{self.logs_dir}/redfish_error.log
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
"""
        
        try:
            subprocess.run(
                ['sudo', 'tee', '/etc/systemd/system/apollo-bmc.service'],
                input=service_content.encode(),
                capture_output=True,
                check=True
            )
            subprocess.run(['sudo', 'systemctl', 'daemon-reload'], check=True)
            print("  ✓ Systemd service created: apollo-bmc.service")
        except Exception as e:
            print(f"  ⚠ Could not create systemd service: {e}")
    
    def start_dnsmasq(self):
        """Start dnsmasq service"""
        print("\nStarting dnsmasq...")
        
        try:
            # Stop the default system dnsmasq if running
            subprocess.run(['sudo', 'systemctl', 'stop', 'dnsmasq'], 
                         capture_output=True, check=False)
            
            # Start our custom apollo-dnsmasq service
            subprocess.run(['sudo', 'systemctl', 'start', 'apollo-dnsmasq'], 
                         check=True, capture_output=True)
            time.sleep(1)
            
            if self.is_service_running('apollo-dnsmasq'):
                print("  ✓ apollo-dnsmasq started")
                return True
            else:
                print("  ✗ apollo-dnsmasq failed to start")
                subprocess.run(['sudo', 'journalctl', '-u', 'apollo-dnsmasq', '-n', '10', '--no-pager'])
                return False
        except subprocess.CalledProcessError as e:
            print(f"  ✗ Failed to start apollo-dnsmasq: {e}")
            return False
    
    def start_nginx(self):
        """Start nginx service"""
        print("\nStarting nginx...")
        
        try:
            # Just reload nginx to pick up our config
            subprocess.run(['sudo', 'systemctl', 'reload', 'nginx'], 
                         check=True, capture_output=True)
            time.sleep(1)
            
            if self.is_service_running('nginx'):
                print("  ✓ nginx config loaded")
                return True
            else:
                # Try to start if not running
                subprocess.run(['sudo', 'systemctl', 'start', 'nginx'], 
                             check=True, capture_output=True)
                time.sleep(1)
                if self.is_service_running('nginx'):
                    print("  ✓ nginx started")
                    return True
                else:
                    print("  ✗ nginx failed to start")
                    return False
        except subprocess.CalledProcessError as e:
            print(f"  ✗ Failed to start/reload nginx: {e}")
            return False
    
    def start_bmc_simulators(self):
        """Start BMC simulator services (IPMI/Redfish)"""
        print("\nStarting BMC simulators...")
        
        # Create service if it doesn't exist
        if not Path('/etc/systemd/system/apollo-bmc.service').exists():
            self._create_bmc_service()
        
        try:
            subprocess.run(['sudo', 'systemctl', 'start', 'apollo-bmc'], 
                         check=True, capture_output=True)
            time.sleep(1)
            
            if self.is_service_running('apollo-bmc'):
                print("  ✓ Redfish API started via systemd")
                print("    Access: http://localhost:5000/redfish/v1/")
                return True
            else:
                print("  ✗ Redfish API failed to start")
                subprocess.run(['sudo', 'journalctl', '-u', 'apollo-bmc', '-n', '10', '--no-pager'])
                return False
            
        except Exception as e:
            print(f"  ✗ Failed to start Redfish API: {e}")
            return False
    
    def stop_services(self):
        """Stop all services"""
        print("\nStopping services...")
        
        # Stop apollo-dnsmasq
        try:
            subprocess.run(['sudo', 'systemctl', 'stop', 'apollo-dnsmasq'], 
                         capture_output=True, check=False)
            print("  ✓ apollo-dnsmasq stopped")
        except Exception as e:
            print(f"  ⚠ Could not stop apollo-dnsmasq: {e}")
        
        # Stop apollo-bmc
        try:
            subprocess.run(['sudo', 'systemctl', 'stop', 'apollo-bmc'], 
                         capture_output=True, check=False)
            print("  ✓ apollo-bmc stopped")
        except Exception as e:
            print(f"  ⚠ Could not stop apollo-bmc: {e}")
        
        print("  ℹ nginx is left running (system service)")
    
    def status(self):
        """Show status of all services"""
        print("\n" + "="*50)
        print("  Apollo Simulator - Service Status")
        print("="*50 + "\n")
        
        # Check apollo-dnsmasq
        if self.is_service_running('apollo-dnsmasq'):
            print("✓ apollo-dnsmasq  - RUNNING")
            print("  DHCP/TFTP:      192.168.100.1 (br0)")
        else:
            print("✗ apollo-dnsmasq  - STOPPED")
        
        # Check nginx
        if self.is_service_running('nginx'):
            print("✓ nginx           - RUNNING")
            print("  HTTP:           http://localhost:8080")
        else:
            print("✗ nginx           - STOPPED")
        
        # Check apollo-bmc
        if self.is_service_running('apollo-bmc'):
            print("✓ apollo-bmc      - RUNNING")
            print("  Redfish API:    http://localhost:5000/redfish/v1/")
        else:
            print("✗ apollo-bmc      - STOPPED")
        
        print()

def main():
    import argparse
    
    parser = argparse.ArgumentParser(description='Manage Apollo Simulator services')
    parser.add_argument('action', choices=['setup', 'start', 'stop', 'status', 'check'],
                       help='Action to perform')
    
    args = parser.parse_args()
    manager = ServiceManager()
    
    if args.action == 'check':
        if not manager.check_dependencies():
            sys.exit(1)
    
    elif args.action == 'setup':
        if not manager.check_dependencies():
            sys.exit(1)
        
        print("\n" + "="*50)
        print("  Setting up native services")
        print("="*50)
        
        if not manager.configure_dnsmasq():
            sys.exit(1)
        
        if not manager.configure_nginx():
            sys.exit(1)
        
        print("\nCreating systemd services...")
        manager._create_bmc_service()
        
        print("\n✓ Setup complete!")
        print("\nRun 'make start-native' to start services")
    
    elif args.action == 'start':
        print("\n" + "="*50)
        print("  Starting Apollo Simulator")
        print("="*50)
        
        if not manager.start_dnsmasq():
            sys.exit(1)
        
        if not manager.start_nginx():
            sys.exit(1)
        
        if not manager.start_bmc_simulators():
            sys.exit(1)
        
        print("\n✓ All services started!")
        manager.status()
    
    elif args.action == 'stop':
        manager.stop_services()
        print("\n✓ Services stopped")
    
    elif args.action == 'status':
        manager.status()

if __name__ == '__main__':
    main()
