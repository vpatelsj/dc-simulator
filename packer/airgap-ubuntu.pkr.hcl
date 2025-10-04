packer {
  required_version = ">= 1.9.0"
  
  required_plugins {
    qemu = {
      version = ">= 1.0.0"
      source  = "github.com/hashicorp/qemu"
    }
  }
}

variable "cloud_image_url" {
  type    = string
  default = "https://cloud-images.ubuntu.com/releases/22.04/release/ubuntu-22.04-server-cloudimg-amd64.img"
  description = "URL to Ubuntu cloud image"
}

variable "cloud_image_checksum" {
  type    = string
  default = "file:https://cloud-images.ubuntu.com/releases/22.04/release/SHA256SUMS"
  description = "Checksum URL for the cloud image"
}

variable "output_directory" {
  type    = string
  default = "output-ubuntu-airgap"
  description = "Directory to store the built image"
}

variable "vm_name" {
  type    = string
  default = "ubuntu-server-airgap"
  description = "Name of the output VM image"
}

variable "disk_size" {
  type    = string
  default = "20G"
  description = "Disk size (default: 20GB)"
}

variable "memory" {
  type    = string
  default = "2048"
  description = "Memory size in MB"
}

variable "cpus" {
  type    = string
  default = "2"
  description = "Number of CPUs"
}

source "qemu" "ubuntu-airgap" {
  # Cloud image settings
  iso_url           = var.cloud_image_url
  iso_checksum      = var.cloud_image_checksum
  disk_image        = true
  
  # Output settings
  output_directory  = var.output_directory
  vm_name           = var.vm_name
  
  # Disk settings
  disk_size         = var.disk_size
  disk_interface    = "virtio"
  disk_compression  = true
  format            = "qcow2"
  
  # Hardware settings
  memory            = var.memory
  cpus              = var.cpus
  
  # Accelerator (use KVM if available)
  accelerator       = "kvm"
  
  # Networking
  net_device        = "virtio-net"
  
  # Display (headless for automation)
  headless          = true
  
  # SSH settings for provisioning (cloud images use ubuntu user with no password by default)
  ssh_username      = "ubuntu"
  ssh_password      = "ubuntu"
  ssh_timeout       = "5m"
  
  # Cloud-init wait
  ssh_handshake_attempts = 500
  
  # Shutdown command
  shutdown_command  = "echo 'ubuntu' | sudo -S shutdown -P now"
  
  # QEMU arguments for cloud-init
  qemuargs = [
    ["-smbios", "type=1,serial=ds=nocloud-net;s=http://{{.HTTPIP}}:{{.HTTPPort}}/"]
  ]
  
  # HTTP server for cloud-init configs
  http_directory = "http"
  http_port_min  = 8100
  http_port_max  = 8100
}

build {
  name = "ubuntu-airgap-server"
  sources = ["source.qemu.ubuntu-airgap"]
  
  # Wait for cloud-init to complete
  provisioner "shell" {
    inline = [
      "echo '>>> Waiting for cloud-init to complete...'",
      "cloud-init status --wait",
      "echo '>>> Cloud-init completed'"
    ]
  }
  
  # Verify system is ready
  provisioner "shell" {
    inline = [
      "echo '>>> System Information:'",
      "uname -a",
      "cat /etc/os-release | grep PRETTY_NAME",
      "df -h /",
      "free -h",
      "echo '>>> System ready'"
    ]
  }
  
  # Configure system for datacenter deployment
  provisioner "shell" {
    inline = [
      "echo '>>> Configuring system for bare-metal deployment'",
      # Enable serial console for PXE/IPMI access
      "sudo systemctl enable serial-getty@ttyS0.service",
      # Configure GRUB for serial console
      "sudo sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT=\".*\"/GRUB_CMDLINE_LINUX_DEFAULT=\"console=tty0 console=ttyS0,115200n8\"/' /etc/default/grub || true",
      "sudo update-grub || true",
      "echo '>>> System configured'"
    ]
  }
  
  # Clean up and prepare for cloning
  provisioner "shell" {
    inline = [
      "echo '>>> Cleaning up system for deployment'",
      # Clean cloud-init (so it runs again on first boot)
      "sudo cloud-init clean --logs --seed",
      # Clean package cache
      "sudo apt-get clean",
      # Clean temporary files
      "sudo rm -rf /tmp/* /var/tmp/*",
      # Truncate logs
      "sudo find /var/log -type f -exec truncate -s 0 {} \\; || true",
      # Remove SSH host keys (regenerated on first boot)
      "sudo rm -f /etc/ssh/ssh_host_*",
      # Clean bash history
      "cat /dev/null > ~/.bash_history || true",
      "echo '>>> Cleanup completed'"
    ]
  }
  
  # Final sync
  provisioner "shell" {
    inline = [
      "echo '>>> Syncing filesystem'",
      "sync",
      "echo '>>> Image ready for deployment!'"
    ]
  }
}
