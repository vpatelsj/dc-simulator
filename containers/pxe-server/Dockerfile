FROM ubuntu:22.04

# Install PXE boot services
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
    dnsmasq \
    nginx \
    inetutils-telnet \
    curl \
    wget \
    iproute2 \
    iputils-ping \
    && rm -rf /var/lib/apt/lists/*

# Create directories
RUN mkdir -p /tftp /var/www/html/ubuntu /etc/dnsmasq.d

# Copy configuration files
COPY config/dnsmasq.conf /etc/dnsmasq.conf
COPY config/nginx.conf /etc/nginx/sites-available/default

# Expose ports
# 67/udp - DHCP
# 69/udp - TFTP
# 80/tcp - HTTP
EXPOSE 67/udp 69/udp 80/tcp

# Start script
COPY start.sh /start.sh
RUN chmod +x /start.sh

CMD ["/start.sh"]
