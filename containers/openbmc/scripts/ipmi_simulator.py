#!/usr/bin/env python3
"""
BMC IPMI Simulator
Provides IPMI interface for managing VMs
"""

import socket
import json
import logging
from datetime import datetime

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger('ipmi-simulator')

class IPMISimulator:
    def __init__(self, host='0.0.0.0', port=623):
        self.host = host
        self.port = port
        self.state_file = '/var/lib/openbmc/state.json'
        self.load_state()
    
    def load_state(self):
        """Load BMC state from file"""
        try:
            with open(self.state_file, 'r') as f:
                self.state = json.load(f)
        except FileNotFoundError:
            self.state = {
                'power_state': 'off',
                'boot_device': 'hdd',
                'sensors': {
                    'cpu_temp': 45.0,
                    'system_temp': 28.0,
                    'fan1_speed': 2400
                }
            }
            self.save_state()
    
    def save_state(self):
        """Save BMC state to file"""
        with open(self.state_file, 'w') as f:
            json.dump(self.state, f, indent=2)
    
    def run(self):
        """Run IPMI simulator"""
        logger.info(f"Starting IPMI simulator on {self.host}:{self.port}")
        logger.info("IPMI interface ready")
        logger.info("Use: ipmitool -I lanplus -H <host> -U openbmc -P 0penBmc")
        
        # Keep running
        try:
            while True:
                import time
                time.sleep(10)
                logger.debug(f"Current state: {self.state}")
        except KeyboardInterrupt:
            logger.info("IPMI simulator stopped")

if __name__ == '__main__':
    simulator = IPMISimulator()
    simulator.run()
