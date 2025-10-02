#!/usr/bin/env python3
"""
BMC Bridge
Bridges BMC commands to QEMU VM lifecycle operations
"""

import requests
import json
import subprocess
from pathlib import Path

class BMCBridge:
    def __init__(self, bmc_url='http://192.168.100.10'):
        self.bmc_url = bmc_url
        self.vm_manager = None  # Import VMManager if needed
    
    def get_bmc_state(self, system_id='1'):
        """Get BMC system state via Redfish API"""
        try:
            url = f"{self.bmc_url}/redfish/v1/Systems/{system_id}"
            response = requests.get(url, verify=False, timeout=5)
            return response.json()
        except Exception as e:
            print(f"Error getting BMC state: {e}")
            return None
    
    def set_boot_device(self, system_id, boot_device='Pxe', enabled='Once'):
        """Set boot device via BMC"""
        try:
            url = f"{self.bmc_url}/redfish/v1/Systems/{system_id}"
            data = {
                'Boot': {
                    'BootSourceOverrideTarget': boot_device,
                    'BootSourceOverrideEnabled': enabled
                }
            }
            response = requests.patch(url, json=data, verify=False, timeout=5)
            return response.status_code == 200
        except Exception as e:
            print(f"Error setting boot device: {e}")
            return False
    
    def power_on(self, system_id):
        """Power on system via BMC"""
        try:
            url = f"{self.bmc_url}/redfish/v1/Systems/{system_id}/Actions/ComputerSystem.Reset"
            data = {'ResetType': 'On'}
            response = requests.post(url, json=data, verify=False, timeout=5)
            return response.status_code == 200
        except Exception as e:
            print(f"Error powering on: {e}")
            return False
    
    def power_off(self, system_id):
        """Power off system via BMC"""
        try:
            url = f"{self.bmc_url}/redfish/v1/Systems/{system_id}/Actions/ComputerSystem.Reset"
            data = {'ResetType': 'ForceOff'}
            response = requests.post(url, json=data, verify=False, timeout=5)
            return response.status_code == 200
        except Exception as e:
            print(f"Error powering off: {e}")
            return False
    
    def pxe_boot_vm(self, vm_name):
        """Orchestrate PXE boot via BMC and start VM"""
        print(f"Initiating PXE boot for VM: {vm_name}")
        
        # 1. Set BMC boot device to PXE
        print("Setting boot device to PXE...")
        if not self.set_boot_device('1', 'Pxe', 'Once'):
            print("Failed to set boot device")
            return False
        
        # 2. Start VM with PXE boot
        print("Starting VM with PXE boot...")
        cmd = ['python3', 'src/vm_manager.py', 'start', '--name', vm_name, '--boot', 'pxe']
        result = subprocess.run(cmd, capture_output=True, text=True)
        
        if result.returncode == 0:
            print("VM started successfully with PXE boot")
            return True
        else:
            print(f"Failed to start VM: {result.stderr}")
            return False


if __name__ == '__main__':
    import sys
    
    if len(sys.argv) < 3:
        print("Usage: python3 bmc_bridge.py <command> <vm_name>")
        print("Commands: pxe-boot, power-on, power-off, status")
        sys.exit(1)
    
    command = sys.argv[1]
    vm_name = sys.argv[2]
    
    bridge = BMCBridge()
    
    if command == 'pxe-boot':
        bridge.pxe_boot_vm(vm_name)
    elif command == 'power-on':
        bridge.power_on('1')
    elif command == 'power-off':
        bridge.power_off('1')
    elif command == 'status':
        state = bridge.get_bmc_state('1')
        if state:
            print(json.dumps(state, indent=2))
    else:
        print(f"Unknown command: {command}")
