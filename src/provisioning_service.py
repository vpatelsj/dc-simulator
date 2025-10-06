#!/usr/bin/env python3
"""
Provisioning Service - MAAS-like Machine Discovery and Deployment
Handles machine discovery, inventory, and automated deployment
"""

import json
import time
from pathlib import Path
from datetime import datetime
from flask import Flask, request, jsonify

app = Flask(__name__)

# Data directory
DATA_DIR = Path(__file__).parent.parent / 'data'
DATA_DIR.mkdir(exist_ok=True)
INVENTORY_FILE = DATA_DIR / 'machine_inventory.json'

class MachineInventory:
    """Manages discovered machines"""
    
    def __init__(self):
        self.inventory_file = INVENTORY_FILE
        self.machines = self.load_inventory()
    
    def load_inventory(self):
        """Load machine inventory from disk"""
        if self.inventory_file.exists():
            with open(self.inventory_file, 'r') as f:
                return json.load(f)
        return {}
    
    def save_inventory(self):
        """Save machine inventory to disk"""
        with open(self.inventory_file, 'w') as f:
            json.dump(self.machines, f, indent=2)
    
    def register_machine(self, discovery_data):
        """Register a newly discovered machine"""
        mac = discovery_data.get('mac_address')
        if not mac:
            return None
        
        # Generate machine ID
        machine_id = f"machine-{mac.replace(':', '')}"
        
        # Check if already exists
        if machine_id in self.machines:
            # Update discovery time
            self.machines[machine_id]['last_seen'] = datetime.now().isoformat()
            self.machines[machine_id]['discovery_count'] = self.machines[machine_id].get('discovery_count', 0) + 1
        else:
            # New machine
            self.machines[machine_id] = {
                'id': machine_id,
                'mac_address': mac,
                'hostname': discovery_data.get('hostname', f'unknown-{mac[-8:].replace(":", "")}'),
                'cpu_count': discovery_data.get('cpu_count', 0),
                'memory_mb': discovery_data.get('memory_mb', 0),
                'disks': discovery_data.get('disks', []),
                'network_interfaces': discovery_data.get('network_interfaces', []),
                'status': 'discovered',
                'discovered_at': datetime.now().isoformat(),
                'last_seen': datetime.now().isoformat(),
                'discovery_count': 1,
                'deployed_image': None,
                'deployment_status': None,
                'deployment_time': None
            }
        
        self.save_inventory()
        return self.machines[machine_id]
    
    def get_machine(self, machine_id):
        """Get machine by ID"""
        return self.machines.get(machine_id)
    
    def get_machine_by_mac(self, mac):
        """Get machine by MAC address"""
        for machine in self.machines.values():
            if machine['mac_address'].lower() == mac.lower():
                return machine
        return None
    
    def list_machines(self, status=None):
        """List all machines, optionally filtered by status"""
        if status:
            return [m for m in self.machines.values() if m['status'] == status]
        return list(self.machines.values())
    
    def update_deployment_status(self, machine_id, status, image=None):
        """Update machine deployment status"""
        if machine_id in self.machines:
            self.machines[machine_id]['deployment_status'] = status
            self.machines[machine_id]['status'] = status
            if image:
                self.machines[machine_id]['deployed_image'] = image
            if status == 'deployed':
                self.machines[machine_id]['deployment_time'] = datetime.now().isoformat()
            self.save_inventory()
            return True
        return False

# Global inventory
inventory = MachineInventory()

# API Routes

@app.route('/api/discover', methods=['POST'])
def discover_machine():
    """
    Machine discovery endpoint
    Called by discovery kernel running on PXE-booted machines
    """
    try:
        data = request.json
        print(f"\n[DISCOVERY] New machine contacting provisioning service")
        print(f"  MAC: {data.get('mac_address')}")
        print(f"  CPUs: {data.get('cpu_count')}")
        print(f"  Memory: {data.get('memory_mb')} MB")
        print(f"  Disks: {len(data.get('disks', []))}")
        
        machine = inventory.register_machine(data)
        
        if machine:
            print(f"  Registered as: {machine['id']}")
            
            # Check if machine is already scheduled for deployment
            if machine.get('status') == 'deploying' and machine.get('deployed_image'):
                print(f"  Deploying: {machine['deployed_image']}")
                # Use .img extension for raw images
                image_name = machine['deployed_image'].replace('.qcow2', '.img')
                return jsonify({
                    'status': 'registered',
                    'machine_id': machine['id'],
                    'action': 'deploy',
                    'image': image_name,
                    'image_url': f"http://192.168.100.1:8080/images/{image_name}"
                })
            
            # Check if auto-deployment is enabled
            auto_deploy = data.get('auto_deploy', False)
            if auto_deploy:
                # Trigger automatic deployment
                machine['status'] = 'deploying'
                inventory.save_inventory()
                
                return jsonify({
                    'status': 'registered',
                    'machine_id': machine['id'],
                    'action': 'deploy',
                    'image': 'ubuntu-server-airgap.qcow2',
                    'image_url': 'http://192.168.100.1:8080/images/ubuntu-server-airgap.qcow2'
                })
            else:
                return jsonify({
                    'status': 'registered',
                    'machine_id': machine['id'],
                    'action': 'wait',
                    'message': 'Machine registered. Awaiting deployment instructions.'
                })
        else:
            return jsonify({'status': 'error', 'message': 'Failed to register machine'}), 400
    
    except Exception as e:
        print(f"[ERROR] Discovery failed: {e}")
        return jsonify({'status': 'error', 'message': str(e)}), 500

@app.route('/api/machines', methods=['GET'])
def list_machines():
    """List all discovered machines"""
    status_filter = request.args.get('status')
    machines = inventory.list_machines(status=status_filter)
    return jsonify({
        'count': len(machines),
        'machines': machines
    })

@app.route('/api/machines/<machine_id>', methods=['GET'])
def get_machine(machine_id):
    """Get specific machine details"""
    machine = inventory.get_machine(machine_id)
    if machine:
        return jsonify(machine)
    return jsonify({'error': 'Machine not found'}), 404

@app.route('/api/deploy', methods=['POST'])
def deploy_machine():
    """
    Deploy Ubuntu image to a machine
    Request body: {
        "machine_id": "machine-525400123456",
        "image": "ubuntu-server-airgap.qcow2"
    }
    """
    try:
        data = request.json
        machine_id = data.get('machine_id')
        image = data.get('image', 'ubuntu-server-airgap.qcow2')
        
        machine = inventory.get_machine(machine_id)
        if not machine:
            return jsonify({'error': 'Machine not found'}), 404
        
        # Update status
        inventory.update_deployment_status(machine_id, 'deploying', image)
        
        print(f"\n[DEPLOYMENT] Deploying {image} to {machine_id}")
        print(f"  MAC: {machine['mac_address']}")
        print(f"  Hostname: {machine['hostname']}")
        
        # Return deployment instructions for the machine
        return jsonify({
            'status': 'deploying',
            'machine_id': machine_id,
            'image': image,
            'image_url': f'http://192.168.100.1:8080/images/{image}',
            'instructions': 'PXE boot and select deployment option'
        })
    
    except Exception as e:
        print(f"[ERROR] Deployment failed: {e}")
        return jsonify({'status': 'error', 'message': str(e)}), 500

@app.route('/api/deployment/status', methods=['POST'])
def update_deployment_status():
    """
    Update deployment status from deploying machine
    Request body: {
        "mac_address": "52:54:00:12:34:56",
        "status": "downloading|writing|complete|failed",
        "progress": 50
    }
    """
    try:
        data = request.json
        mac = data.get('mac_address')
        status = data.get('status')
        
        machine = inventory.get_machine_by_mac(mac)
        if not machine:
            return jsonify({'error': 'Machine not found'}), 404
        
        if status == 'complete':
            inventory.update_deployment_status(machine['id'], 'deployed')
            print(f"[DEPLOYMENT] {machine['id']} deployment completed successfully")
        elif status == 'failed':
            inventory.update_deployment_status(machine['id'], 'failed')
            print(f"[DEPLOYMENT] {machine['id']} deployment failed")
        
        return jsonify({'status': 'updated'})
    
    except Exception as e:
        print(f"[ERROR] Status update failed: {e}")
        return jsonify({'status': 'error', 'message': str(e)}), 500

@app.route('/health', methods=['GET'])
def health():
    """Health check endpoint"""
    return jsonify({
        'status': 'healthy',
        'service': 'provisioning',
        'machines': len(inventory.machines)
    })

if __name__ == '__main__':
    print("="*60)
    print("  Apollo Simulator - Provisioning Service")
    print("="*60)
    print()
    print("Starting provisioning service on port 5001...")
    print("Endpoints:")
    print("  POST /api/discover        - Machine discovery")
    print("  GET  /api/machines        - List machines")
    print("  POST /api/deploy          - Deploy image to machine")
    print("  POST /api/deployment/status - Update deployment status")
    print()
    
    app.run(host='0.0.0.0', port=5001, debug=True)
