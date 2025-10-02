#!/usr/bin/env python3
"""
Redfish API Server
Provides RESTful API for BMC management
"""

from flask import Flask, jsonify, request
import json
import logging

app = Flask(__name__)

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger('redfish-api')

# State management
STATE_FILE = '/var/lib/openbmc/state.json'

def load_state():
    try:
        with open(STATE_FILE, 'r') as f:
            return json.load(f)
    except:
        return {
            'power_state': 'Off',
            'boot_device': 'Hdd',
            'boot_override': 'Disabled'
        }

def save_state(state):
    with open(STATE_FILE, 'w') as f:
        json.dump(state, f, indent=2)

@app.route('/redfish/v1/')
def service_root():
    return jsonify({
        "@odata.type": "#ServiceRoot.v1_0_0.ServiceRoot",
        "@odata.id": "/redfish/v1/",
        "Id": "RootService",
        "Name": "DC Simulator Redfish Service",
        "RedfishVersion": "1.0.0",
        "UUID": "12345678-1234-1234-1234-123456789012",
        "Systems": {
            "@odata.id": "/redfish/v1/Systems"
        },
        "Chassis": {
            "@odata.id": "/redfish/v1/Chassis"
        },
        "Managers": {
            "@odata.id": "/redfish/v1/Managers"
        }
    })

@app.route('/redfish/v1/Systems')
def systems_collection():
    return jsonify({
        "@odata.type": "#ComputerSystemCollection.ComputerSystemCollection",
        "@odata.id": "/redfish/v1/Systems",
        "Name": "Computer System Collection",
        "Members@odata.count": 1,
        "Members": [
            {"@odata.id": "/redfish/v1/Systems/1"}
        ]
    })

@app.route('/redfish/v1/Systems/1', methods=['GET', 'PATCH'])
def system_1():
    state = load_state()
    
    if request.method == 'GET':
        return jsonify({
            "@odata.type": "#ComputerSystem.v1_0_0.ComputerSystem",
            "@odata.id": "/redfish/v1/Systems/1",
            "Id": "1",
            "Name": "Server Node 1",
            "SystemType": "Physical",
            "PowerState": state.get('power_state', 'Off'),
            "Boot": {
                "BootSourceOverrideEnabled": state.get('boot_override', 'Disabled'),
                "BootSourceOverrideTarget": state.get('boot_device', 'Hdd'),
                "BootSourceOverrideTarget@Redfish.AllowableValues": [
                    "None", "Pxe", "Hdd", "Cd", "BiosSetup"
                ]
            },
            "ProcessorSummary": {
                "Count": 2,
                "Model": "Intel Xeon E5-2620"
            },
            "MemorySummary": {
                "TotalSystemMemoryGiB": 16
            },
            "Actions": {
                "#ComputerSystem.Reset": {
                    "target": "/redfish/v1/Systems/1/Actions/ComputerSystem.Reset",
                    "ResetType@Redfish.AllowableValues": [
                        "On", "ForceOff", "GracefulShutdown", "GracefulRestart", "ForceRestart"
                    ]
                }
            }
        })
    
    elif request.method == 'PATCH':
        data = request.get_json()
        
        if 'Boot' in data:
            boot_config = data['Boot']
            if 'BootSourceOverrideTarget' in boot_config:
                state['boot_device'] = boot_config['BootSourceOverrideTarget']
            if 'BootSourceOverrideEnabled' in boot_config:
                state['boot_override'] = boot_config['BootSourceOverrideEnabled']
            save_state(state)
            logger.info(f"Boot configuration updated: {boot_config}")
        
        return jsonify({'status': 'success'}), 200

@app.route('/redfish/v1/Systems/1/Actions/ComputerSystem.Reset', methods=['POST'])
def system_reset():
    data = request.get_json()
    reset_type = data.get('ResetType', 'On')
    
    state = load_state()
    
    if reset_type == 'On':
        state['power_state'] = 'On'
    elif reset_type in ['ForceOff', 'GracefulShutdown']:
        state['power_state'] = 'Off'
    elif reset_type in ['GracefulRestart', 'ForceRestart']:
        state['power_state'] = 'On'  # Simulate restart
    
    save_state(state)
    logger.info(f"System reset requested: {reset_type}")
    
    return jsonify({'status': 'success', 'message': f'Reset {reset_type} executed'}), 200

if __name__ == '__main__':
    logger.info("Starting Redfish API server on port 5000")
    # Run on port 5000 internally, exposed as 443 by container
    app.run(host='0.0.0.0', port=5000, debug=False, threaded=True)
