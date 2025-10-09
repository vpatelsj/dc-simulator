#!/bin/sh
# Machine Discovery Script
# Collects hardware information and registers with provisioning service

PROVISIONING_URL="http://192.168.100.1:5100/api/discover"

echo "=========================================="
echo "  Machine Discovery"
echo "=========================================="
echo ""

# Get network configuration
echo "Waiting for network configuration..."
sleep 3

# Load common network drivers
if command -v depmod >/dev/null 2>&1; then
    depmod -a 2>/dev/null || true
fi

load_module() {
    mod="$1"
    if command -v modprobe >/dev/null 2>&1 && modprobe -n "$mod" >/dev/null 2>&1; then
        if modprobe "$mod" >/dev/null 2>&1; then
            echo "Loaded module via modprobe: $mod"
            return 0
        fi
    fi
    if command -v find >/dev/null 2>&1; then
        for path in $(find /lib/modules -type f -name "${mod}.ko" -o -name "${mod}.ko.gz" 2>/dev/null); do
            if printf '%s' "$path" | grep -q '\.gz$'; then
                tmp="/tmp/${mod}.ko"
                gzip -dc "$path" > "$tmp" 2>/dev/null || continue
                insmod "$tmp" >/dev/null 2>&1 && {
                    echo "Loaded module via insmod: $mod";
                    rm -f "$tmp"
                    return 0
                }
                rm -f "$tmp"
            else
                insmod "$path" >/dev/null 2>&1 && {
                    echo "Loaded module via insmod: $mod";
                    return 0
                }
            fi
        done
    fi
    return 1
}

for module in mii mdio virtio_net virtio_pci virtio_ring e1000 e1000e 8139cp 8139too; do
    load_module "$module" || true
done

# Determine primary network interface
if [ -n "$DISCOVERY_IF" ] && [ -d "/sys/class/net/$DISCOVERY_IF" ]; then
    PRIMARY_IF="$DISCOVERY_IF"
fi

if [ -z "$PRIMARY_IF" ]; then
    for attempt in 1 2 3 4 5 6 7 8 9 10; do
        for iface_path in /sys/class/net/*; do
            [ -e "$iface_path" ] || continue
            iface="$(basename "$iface_path")"
            case "$iface" in
                lo|dummy*|sit*|tun*|tap*|virbr*|veth*|vmnet*|vbox*|br*|docker*|zt*|wg*)
                    continue
                    ;;
            esac
            PRIMARY_IF="$iface"
            break
        done
        [ -n "$PRIMARY_IF" ] && break
        sleep 1
    done
fi

if [ -z "$PRIMARY_IF" ]; then
    echo "ERROR: No network interface found!"
    ls /sys/class/net
    if command -v ip >/dev/null 2>&1; then
        ip link show
    fi
    exit 1
fi

echo "Primary interface: $PRIMARY_IF"
ip link set "$PRIMARY_IF" up 2>/dev/null || ifconfig "$PRIMARY_IF" up 2>/dev/null
sleep 1

# Get MAC address
if command -v ip >/dev/null 2>&1; then
    MAC_ADDR=$(ip link show "$PRIMARY_IF" | awk '/link\/ether/ {print $2; exit}')
else
    MAC_ADDR=$(ifconfig "$PRIMARY_IF" 2>/dev/null | awk '/HWaddr/ {print $5; exit}')
    if [ -z "$MAC_ADDR" ]; then
        MAC_ADDR=$(ifconfig "$PRIMARY_IF" 2>/dev/null | awk '/ether/ {print $2; exit}')
    fi
fi
echo "MAC Address: $MAC_ADDR"

# Get IP address
get_ip_address() {
    if command -v ip >/dev/null 2>&1; then
        ip -4 addr show "$PRIMARY_IF" | awk '/inet / {print $2; exit}' | cut -d/ -f1
    else
        ip_val=$(ifconfig "$PRIMARY_IF" 2>/dev/null | awk '/inet addr:/ {sub("addr:", "", $2); print $2; exit}')
        if [ -z "$ip_val" ]; then
            ip_val=$(ifconfig "$PRIMARY_IF" 2>/dev/null | awk '/inet / {print $2; exit}')
        fi
        echo "$ip_val"
    fi
}

IP_ADDR=$(get_ip_address)

if [ -z "$IP_ADDR" ] && command -v udhcpc >/dev/null 2>&1; then
    echo "Requesting DHCP lease on $PRIMARY_IF..."
    udhcpc -i "$PRIMARY_IF" -q -n || true
    sleep 1
    IP_ADDR=$(get_ip_address)
fi

echo "IP Address: $IP_ADDR"

# Get hostname
HOSTNAME=$(hostname)
echo "Hostname: $HOSTNAME"

# Get CPU information
CPU_COUNT=$(grep -c ^processor /proc/cpuinfo)
CPU_MODEL=$(grep 'model name' /proc/cpuinfo | head -n1 | cut -d: -f2 | sed 's/^ *//')
echo "CPU: $CPU_COUNT cores - $CPU_MODEL"

# Get memory information
MEM_TOTAL=$(free -m | grep Mem: | awk '{print $2}')
echo "Memory: ${MEM_TOTAL}MB"

# Get disk information
DISKS=""
for disk in /sys/block/sd* /sys/block/vd* /sys/block/nvme*; do
    if [ -e "$disk" ]; then
        DISK_NAME=$(basename "$disk")
        DISK_SIZE=$(cat "$disk/size" 2>/dev/null || echo "0")
        # Convert sectors to GB (512 bytes per sector)
        DISK_SIZE_GB=$((DISK_SIZE * 512 / 1000000000))
        if [ "$DISK_SIZE_GB" -gt 0 ]; then
            if [ -z "$DISKS" ]; then
                DISKS="$DISK_NAME:${DISK_SIZE_GB}GB"
            else
                DISKS="$DISKS,$DISK_NAME:${DISK_SIZE_GB}GB"
            fi
            echo "Disk: $DISK_NAME (${DISK_SIZE_GB}GB)"
        fi
    fi
done

echo ""
echo "Registering with provisioning service..."

# Build JSON payload
JSON_DATA=$(cat <<EOF
{
  "mac_address": "$MAC_ADDR",
  "hostname": "$HOSTNAME",
  "ip_address": "$IP_ADDR",
  "cpu_count": $CPU_COUNT,
  "cpu_model": "$CPU_MODEL",
  "memory_mb": $MEM_TOTAL,
  "disks": "$DISKS",
  "interfaces": "$PRIMARY_IF:$MAC_ADDR:$IP_ADDR"
}
EOF
)

# Register with provisioning service
RESPONSE=$(wget -q -O- --post-data="$JSON_DATA" \
    --header="Content-Type: application/json" \
    "$PROVISIONING_URL" 2>&1)

if [ $? -eq 0 ]; then
    echo "✓ Successfully registered with provisioning service"
    echo ""
    echo "Response: $RESPONSE"
else
    echo "✗ Failed to register with provisioning service"
    echo "Error: $RESPONSE"
fi

echo ""
echo "=========================================="
echo "  Discovery Complete"
echo "=========================================="
echo ""
echo "Machine is now registered and awaiting deployment."
echo "You can deploy an OS image using the provisioning API."
echo ""
echo "Press Enter to get a shell prompt..."
read dummy

# Drop to shell
exec /bin/sh
