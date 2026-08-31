#!/bin/sh
# =============================================================================
# OpenWrt Guest Wake-on-Demand Listener
# File: /usr/bin/guest_wake_listener.sh
# Usage: /usr/bin/guest_wake_listener.sh <guest_ip> <port>[/udp|/tcp] <vmid>
# =============================================================================

# Load common initialization (paths, config, SSH vars)
. /usr/bin/components/common_init.sh

# Load power_proxy-specific components
. "$PP_COMP"/cleanup_helper.sh
. "$PP_COMP"/network_helper.sh
. "$PP_COMP"/listener_helper.sh

# Read Config
init_common_config

# Initialize SSH connection parameters
init_ssh_vars

GUEST_IP="$1"
PORT_RAW="$2"
VMID="$3"
IFACE="${LAN_INTERFACE:-br-lan}"

if [ -z "$GUEST_IP" ] || [ -z "$PORT_RAW" ] || [ -z "$VMID" ]; then
    echo "Usage: $0 <guest_ip> <port>[/udp|/tcp] <vmid>" >&2
    exit 1
fi

# Parse port and protocol (e.g. 19132/udp -> PORT_NUM=19132, PROTO=udp)
parse_port

# 1. Bind Guest IP alias to Router interface so the router answers ARPs for it
bind_ip

# Clean up rule and netcat on signal
cleanup_guest
trap cleanup_guest SIGTERM SIGINT

# 2. Intercept incoming connection to the guest port in background
listen_guest

# Wait for netcat to intercept a packet or timeout
wait "$NC_PID"

# 3. Connection intercepted! Remove IP alias instantly to restore native routing
echo "Connection intercepted! Restoring native routing..."
ip addr del "${GUEST_IP}/32" dev "$IFACE" >/dev/null 2>&1 || true

# 4. Trigger Wake-on-Demand Sequence
# Check if Proxmox host is awake. If not awake, wake the entire host first.
is_host_alive

if ! is_host_alive; then
    echo "Proxmox Host ($HOST_IP) is offline. Dispatching Wake-on-LAN..."
    etherwake -i "$IFACE" "$HOST_MAC"

    # Wait for Proxmox host to boot up
    echo "Waiting for Proxmox host to boot up..."
    while true; do
        if is_host_alive; then
            break
        fi
        sleep 2
    done
fi

# Host is awake. Trigger VMID resume or start on Proxmox
echo "Waking Guest VM/LXC ID $VMID on Proxmox..."
$SSH_CMD "if pct config $VMID >/dev/null 2>&1; then
            pct resume $VMID >/dev/null 2>&1 || pct start $VMID >/dev/null 2>&1
          elif qm config $VMID >/dev/null 2>&1; then
            qm resume $VMID >/dev/null 2>&1 || qm start $VMID >/dev/null 2>&1
          fi" >/dev/null 2>&1

# Send Notification
MSG=$(eval echo "\"$MSG_WAKE_GUEST_DEMAND\"")
/usr/bin/homelab_notify.sh "$MSG" &

# Exit cleanly
exit 0
