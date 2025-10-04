.PHONY: help setup start stop status test clean install list-vms vm-create vm-start vm-stop vm-delete bmc-status

help:
	@echo "╔══════════════════════════════════════════════════════════╗"
	@echo "║     Apollo Simulator - Docker-Free Edition              ║"
	@echo "╚══════════════════════════════════════════════════════════╝"
	@echo ""
	@echo "🔧 Setup:"
	@echo "  make install       - Install system dependencies"
	@echo "  make setup         - Setup native services (dnsmasq, nginx, BMC)"
	@echo "  make test          - Test system readiness"
	@echo ""
	@echo "🚀 Services:"
	@echo "  make start         - Start all native services"
	@echo "  make stop          - Stop all services"
	@echo "  make status        - Show service status"
	@echo ""
	@echo "🖥️  Virtual Machines:"
	@echo "  make vm-create     - Create and start a new VM with PXE boot"
	@echo "  make vm-stop       - Stop a VM"
	@echo "  make vm-delete     - Delete a VM"
	@echo "  make list-vms      - List all VMs"
	@echo ""
	@echo "🔍 Monitoring:"
	@echo "  make bmc-status    - Check BMC Redfish API"
	@echo ""
	@echo "🧹 Cleanup:"
	@echo "  make clean         - Clean VM disks and logs"
	@echo "  make clean-all     - Complete cleanup (including venv)"
	@echo ""

install:
	@echo "Installing system dependencies..."
	@sudo apt-get update
	@sudo apt-get install -y \
		qemu-system-x86 qemu-utils qemu-kvm \
		dnsmasq nginx \
		python3 python3-pip python3-flask python3-yaml \
		bridge-utils tcpdump
	@echo ""
	@echo "✓ System dependencies installed"
	@echo ""
	@echo "Next step: make setup"

setup:
	@python3 src/service_manager.py setup

start:
	@python3 src/service_manager.py start

stop:
	@python3 src/service_manager.py stop

status:
	@python3 src/service_manager.py status

test:
	@./test.sh

list-vms:
	@python3 src/vm_manager.py list

# VM management targets
vm-create:
	@name="vm-$$(date +%s)"; \
	echo "Creating VM: $$name"; \
	python3 src/vm_manager.py create --name $$name --memory 2048 --cpus 2 --disk 20 && \
	echo "Starting VM with PXE boot..."; \
	output=$$(python3 src/vm_manager.py start --name $$name --boot pxe 2>&1); \
	echo "$$output"; \
	vnc_port=$$(echo "$$output" | grep -oP 'VNC: localhost:\K[0-9]+'); \
	if [ -n "$$vnc_port" ] && command -v vncviewer >/dev/null 2>&1; then \
		echo "Opening VNC viewer..."; \
		vncviewer localhost:$$vnc_port >/dev/null 2>&1 & \
	fi

vm-stop:
	@read -p "VM Name: " name; \
	python3 src/vm_manager.py stop --name $$name

vm-delete:
	@read -p "VM Name: " name; \
	python3 src/vm_manager.py delete --name $$name

vm-pxe-test:
	@name="pxe-test-$$(date +%s)"; \
	echo "Creating test VM: $$name"; \
	python3 src/vm_manager.py create --name $$name --memory 2048 --cpus 2 --disk 20 && \
	echo "Starting VM with PXE boot..."; \
	output=$$(python3 src/vm_manager.py start --name $$name --boot pxe 2>&1); \
	echo "$$output"; \
	vnc_port=$$(echo "$$output" | grep -oP 'VNC: localhost:\K[0-9]+'); \
	if [ -n "$$vnc_port" ] && command -v vncviewer >/dev/null 2>&1; then \
		echo "Opening TigerVNC..."; \
		vncviewer localhost:$$vnc_port >/dev/null 2>&1 & \
	fi

# Cleanup targets
clean-vms:
	@echo "Removing all VMs..."
	@rm -rf images/vms/*.qcow2
	@rm -rf images/vms/*.pid
	@echo "✓ VMs removed"

clean-logs:
	@echo "Cleaning logs..."
	@rm -rf logs/*.log
	@rm -rf run/*.pid
	@echo "✓ Logs cleaned"

clean-services:
	@echo "Stopping and removing systemd services..."
	@python3 src/service_manager.py stop
	@sudo rm -f /etc/systemd/system/apollo-dnsmasq.service
	@sudo rm -f /etc/systemd/system/apollo-bmc.service
	@sudo rm -f /etc/dnsmasq.d/apollo-simulator.conf
	@sudo rm -f /etc/nginx/sites-enabled/apollo-simulator
	@sudo rm -f /etc/nginx/sites-available/apollo-simulator
	@sudo systemctl daemon-reload
	@echo "✓ Services cleaned up"

clean: clean-vms clean-logs
	@echo "✓ Cleaned"

clean-all: clean-services clean
	@echo "✓ Complete cleanup done"

# BMC Redfish API commands
bmc-status:
	@curl -s http://localhost:5000/redfish/v1/Systems/apollo-bmc-1 | python3 -m json.tool

bmc-power-on:
	@curl -X POST http://localhost:5000/redfish/v1/Systems/apollo-bmc-1/Actions/ComputerSystem.Reset \
		-H "Content-Type: application/json" \
		-d '{"ResetType": "On"}' | python3 -m json.tool

bmc-power-off:
	@curl -X POST http://localhost:5000/redfish/v1/Systems/apollo-bmc-1/Actions/ComputerSystem.Reset \
		-H "Content-Type: application/json" \
		-d '{"ResetType": "ForceOff"}' | python3 -m json.tool

bmc-set-pxe:
	@curl -X PATCH http://localhost:5000/redfish/v1/Systems/apollo-bmc-1 \
		-H "Content-Type: application/json" \
		-d '{"Boot": {"BootSourceOverrideTarget": "Pxe", "BootSourceOverrideEnabled": "Once"}}' \
		| python3 -m json.tool

.PHONY: help install setup start stop status test list-vms vm-create vm-stop vm-delete vm-pxe-test clean-vms clean-logs clean-services clean clean-all bmc-status bmc-power-on bmc-power-off bmc-set-pxe
