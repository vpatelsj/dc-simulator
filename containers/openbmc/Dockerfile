# OpenBMC Container
# This runs OpenBMC services in a container

FROM ubuntu:22.04

# Install OpenBMC dependencies and IPMI tools
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
    ipmitool \
    python3 \
    python3-pip \
    python3-yaml \
    python3-requests \
    python3-flask \
    gunicorn \
    openssh-server \
    supervisor \
    curl \
    wget \
    && rm -rf /var/lib/apt/lists/*

# Install Python IPMI simulator (optional)
# RUN pip3 install pyghmi

# Create OpenBMC user
RUN useradd -m -s /bin/bash openbmc && \
    echo 'openbmc:0penBmc' | chpasswd

# Setup SSH
RUN mkdir /var/run/sshd && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config

# Create directories
RUN mkdir -p /var/lib/openbmc /etc/openbmc /var/log/openbmc

# Copy BMC emulator scripts
COPY scripts/ /opt/openbmc/
RUN chmod +x /opt/openbmc/*.py

# Supervisor configuration
COPY supervisord.conf /etc/supervisor/conf.d/openbmc.conf

# Expose ports
# 22 - SSH
# 623 - IPMI
# 5000 - Redfish API (exposed as 443)
# 5900 - VNC (for KVM)
EXPOSE 22 623 5000 5900

CMD ["/usr/bin/supervisord", "-n", "-c", "/etc/supervisor/supervisord.conf"]
