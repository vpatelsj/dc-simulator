.PHONY: help setup start stop test clean install list-vms cleanup clean-services clean-all

help:
	@echo "DC Simulator - Available Commands"
	@echo "======================================"
	@echo ""
	@echo "Setup:"
	@echo "  make install       - Install all dependencies (creates venv)"
	@echo "  make setup         - Run initial setup (downloads netboot)"
	@echo "  make setup-pxe     - Alternative PXE setup (if netboot fails)"
	@echo "  make test          - Test system readiness"
	@echo "  make status        - Show current system status"
	@echo ""
	@echo "Services:"
	@echo "  make start         - Run setup and start OpenBMC and PXE server"
	@echo "  make stop          - Stop all services"
	@echo "  make restart       - Restart all services"
	@echo "  make logs          - View service logs"
	@echo ""
	@echo "VMs:"
	@echo "  make vm-start      - Create and start a new VM (auto, no prompts)"
	@echo "  make vm-stop       - Stop a VM (interactive)"
	@echo "  make list-vms      - List all VMs"
	@echo ""
	@echo "Cleanup:"
	@echo "  make clean         - Complete cleanup (venv, netboot, VMs, everything)"
	@echo "  make clean-all     - Clean without removing netboot files"
	@echo "  make clean-services - Stop services and remove VM disks only"
	@echo "  make cleanup       - Legacy cleanup (VMs, containers, network)"
	@echo ""

install:
	@echo "Installing dependencies..."
	sudo apt-get update
	sudo apt-get install -y qemu-system-x86 qemu-utils qemu-kvm python3-venv python3-pip
	@echo ""
	@echo "Creating Python virtual environment..."
	python3 -m venv venv
	@echo ""
	@echo "Installing Python packages in venv..."
	./venv/bin/pip install --upgrade pip
	./venv/bin/pip install -r requirements.txt
	@echo ""
	@echo "✓ Dependencies installed"
	@echo ""
	@echo "IMPORTANT: Activate the virtual environment before running scripts:"
	@echo "  source venv/bin/activate"
	@echo ""
	@echo "Or use the convenience commands:"
	@echo "  make setup, make start, etc. (they auto-activate venv)"
	@echo ""
	@echo "IMPORTANT: You need to log out and back in to WSL for KVM access"
	@echo "From PowerShell run: wsl --shutdown"
	@echo "Then restart WSL"

setup:
	@if [ -d venv ]; then \
		. venv/bin/activate && ./setup.sh; \
	else \
		./setup.sh; \
	fi

setup-pxe:
	@./pxe_alternative.sh

status:
	@./status.sh

start: setup
	@./start.sh

stop:
	@./stop.sh

restart: stop start

test:
	@./test.sh

logs:
	@echo "OpenBMC logs:"
	@docker logs --tail 50 bmc-openbmc 2>/dev/null || echo "OpenBMC container not running"
	@echo ""
	@echo "PXE Server logs:"
	@docker logs --tail 50 bmc-pxe 2>/dev/null || echo "PXE container not running"

list-vms:
	@if [ -d venv ]; then \
		./venv/bin/python src/vm_manager.py list; \
	else \
		python3 src/vm_manager.py list; \
	fi

cleanup:
	@./cleanup.sh

clean-services:
	@./stop.sh
	@echo "Removing VM disk images..."
	@rm -rf images/vms/*.qcow2 images/vms/*.pid
	@echo "Removing logs..."
	@sudo rm -rf logs/*.log
	@echo "✓ Services cleanup complete"

clean-all: clean-services
	@echo "Removing virtual environment..."
	@rm -rf venv
	@echo "✓ Full cleanup complete (netboot files preserved)"

clean: clean-all
	@echo "Removing Ubuntu netboot files..."
	@rm -rf images/ubuntu/*
	@echo "Removing VM configuration..."
	@rm -f config/vms.yaml
	@echo "✓ Complete cleanup finished (everything removed)"
	@echo "Note: Run 'make start' to setup and start from scratch"

# Quick actions
vm-start:
	@PYTHON_CMD=""; \
	if [ -d venv ]; then \
		PYTHON_CMD="./venv/bin/python"; \
	else \
		PYTHON_CMD="python3"; \
	fi; \
	name="vm-$$(date +%s)-$$$$"; \
	echo "Creating new VM with name: $$name"; \
	$$PYTHON_CMD src/vm_manager.py create --name $$name --memory 2048 --cpus 2 --disk 20 && \
	echo "Starting VM..."; \
	output=$$($$PYTHON_CMD src/vm_manager.py start --name $$name --boot pxe 2>&1); \
	echo "$$output"; \
	vnc_port=$$(echo "$$output" | grep -oP 'VNC: localhost:\K[0-9]+'); \
	if [ -n "$$vnc_port" ] && command -v vncviewer >/dev/null 2>&1; then \
		echo "Opening TigerVNC..."; \
		vncviewer localhost:$$vnc_port >/dev/null 2>&1 & \
	fi

vm-stop:
	@read -p "VM Name: " name; \
	if [ -d venv ]; then \
		./venv/bin/python src/vm_manager.py stop --name $$name; \
	else \
		python3 src/vm_manager.py stop --name $$name; \
	fi

# BMC commands
bmc-status:
	@curl -k -s https://localhost:8443/redfish/v1/Systems/1 | python3 -m json.tool

bmc-power-on:
	@curl -k -X POST https://localhost:8443/redfish/v1/Systems/1/Actions/ComputerSystem.Reset \
		-H "Content-Type: application/json" \
		-d '{"ResetType": "On"}' | python3 -m json.tool

bmc-power-off:
	@curl -k -X POST https://localhost:8443/redfish/v1/Systems/1/Actions/ComputerSystem.Reset \
		-H "Content-Type: application/json" \
		-d '{"ResetType": "ForceOff"}' | python3 -m json.tool

bmc-set-pxe:
	@curl -k -X PATCH https://localhost:8443/redfish/v1/Systems/1 \
		-H "Content-Type: application/json" \
		-d '{"Boot": {"BootSourceOverrideTarget": "Pxe", "BootSourceOverrideEnabled": "Once"}}' \
		| python3 -m json.tool
