.PHONY: help setup start stop test clean install create-vm list-vms cleanup

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
	@echo "  make start         - Start OpenBMC and PXE server"
	@echo "  make stop          - Stop all services"
	@echo "  make restart       - Restart all services"
	@echo "  make logs          - View service logs"
	@echo ""
	@echo "VMs:"
	@echo "  make create-vm     - Create a new VM (interactive)"
	@echo "  make create-pxe-vm - Create VM from Packer image (fast deploy)"
	@echo "  make list-vms      - List all VMs"
	@echo "  make vm-start      - Start a VM (interactive)"
	@echo "  make vm-stop       - Stop a VM (interactive)"
	@echo ""
	@echo "Cleanup:"
	@echo "  make cleanup       - Complete cleanup (VMs, containers, network)"
	@echo "  make clean         - Stop services and remove VM disks"
	@echo "  make clean-all     - Full cleanup (includes venv)"
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

start:
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

create-vm:
	@echo "Create New VM"
	@echo "============="
	@read -p "VM Name: " name; \
	read -p "Memory (MB) [2048]: " memory; \
	memory=$${memory:-2048}; \
	read -p "CPUs [2]: " cpus; \
	cpus=$${cpus:-2}; \
	read -p "Disk Size (GB) [20]: " disk; \
	disk=$${disk:-20}; \
	read -p "Use Packer base image? (y/n) [n]: " use_packer; \
	if [ "$$use_packer" = "y" ] || [ "$$use_packer" = "Y" ]; then \
		base_image="packer/output-ubuntu-airgap/ubuntu-server-airgap"; \
		if [ ! -f "$$base_image" ]; then \
			echo "Error: Packer base image not found at $$base_image"; \
			echo "Build it first with: cd packer && packer build airgap-ubuntu.pkr.hcl"; \
			exit 1; \
		fi; \
		if [ -d venv ]; then \
			./venv/bin/python src/vm_manager.py create --name $$name --memory $$memory --cpus $$cpus --disk $$disk --base-image $$base_image; \
		else \
			python3 src/vm_manager.py create --name $$name --memory $$memory --cpus $$cpus --disk $$disk --base-image $$base_image; \
		fi; \
	else \
		if [ -d venv ]; then \
			./venv/bin/python src/vm_manager.py create --name $$name --memory $$memory --cpus $$cpus --disk $$disk; \
		else \
			python3 src/vm_manager.py create --name $$name --memory $$memory --cpus $$cpus --disk $$disk; \
		fi; \
	fi

create-pxe-vm:
	@echo "Create VM from Packer Image"
	@echo "============================"
	@base_image="packer/output-ubuntu-airgap/ubuntu-server-airgap"; \
	if [ ! -f "$$base_image" ]; then \
		echo "❌ Packer base image not found at $$base_image"; \
		echo ""; \
		echo "Build it first with:"; \
		echo "  cd packer && packer build airgap-ubuntu.pkr.hcl"; \
		echo ""; \
		echo "This will take ~3 minutes and create a pre-installed Ubuntu image."; \
		exit 1; \
	fi; \
	echo "✓ Found Packer base image"; \
	echo ""; \
	read -p "VM Name [ubuntu-pxe-01]: " name; \
	name=$${name:-ubuntu-pxe-01}; \
	read -p "Memory (MB) [2048]: " memory; \
	memory=$${memory:-2048}; \
	read -p "CPUs [2]: " cpus; \
	cpus=$${cpus:-2}; \
	read -p "Disk Size (GB) [20]: " disk; \
	disk=$${disk:-20}; \
	echo ""; \
	echo "Creating VM from Packer image..."; \
	if [ -d venv ]; then \
		./venv/bin/python src/vm_manager.py create --name $$name --memory $$memory --cpus $$cpus --disk $$disk --base-image $$base_image; \
	else \
		python3 src/vm_manager.py create --name $$name --memory $$memory --cpus $$cpus --disk $$disk --base-image $$base_image; \
	fi; \
	echo ""; \
	echo "✓ VM created! Start it with:"; \
	echo "  make vm-start   (or directly: python3 src/vm_manager.py start --name $$name --boot pxe)"

list-vms:
	@if [ -d venv ]; then \
		./venv/bin/python src/vm_manager.py list; \
	else \
		python3 src/vm_manager.py list; \
	fi

cleanup:
	@./cleanup.sh

clean:
	@./stop.sh
	@echo "Removing VM disk images..."
	@rm -rf images/vms/*.qcow2 images/vms/*.pid
	@echo "Removing logs..."
	@rm -rf logs/*.log
	@echo "✓ Cleanup complete"

clean-all: clean
	@echo "Removing virtual environment..."
	@rm -rf venv
	@echo "✓ Full cleanup complete"

# Quick actions
vm-start:
	@read -p "VM Name: " name; \
	read -p "Boot mode (disk/pxe) [pxe]: " boot; \
	boot=$${boot:-pxe}; \
	if [ -d venv ]; then \
		./venv/bin/python src/vm_manager.py start --name $$name --boot $$boot; \
	else \
		python3 src/vm_manager.py start --name $$name --boot $$boot; \
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
