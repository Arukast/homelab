#!/bin/sh
# =============================================================================
# OpenWrt Guest Wake-on-Demand Listener
# File: /usr/bin/guest_wake_listener.sh
# Usage: /usr/bin/guest_wake_listener.sh <guest_ip> <port>[/udp|/tcp] <vmid>
# =============================================================================

GUEST_IP="$1"
PORT_RAW="$2"
VMID="$3"
CONF="/etc/homelab_power.conf"

if [ -z "$GUEST_IP" ] || [ -z "$PORT_RAW" ] || [ -z "$VMID" ]; then
    echo "Usage: $0 <guest_ip> <port>[/udp|/tcp] <vmid>" >&2
    exit 1
fi

if [ ! -f "$CONF" ]; then
    echo "ERROR: Configuration file $CONF not found." >&2
    exit 1
fi

. "$CONF"

# Load messages config
MSG_CONF="/etc/homelab_messages.conf"
if [ -f "$MSG_CONF" ]; then
    . "$MSG_CONF"
fi

# Parse port and protocol (e.g. 19132/udp -> PORT_NUM=19132, PROTO=udp)
PORT_NUM=$(echo "$PORT_RAW" | cut -d'/' -f1)
PROTO=$(echo "$PORT_RAW" | cut -d'/' -f2 -s)
[ -z "$PROTO" ] && PROTO="tcp"

SSH_CMD="ssh -i $SSH_KEY_PATH -y -K 3 root@$HOST_IP"

# 1. Bind Guest IP alias to Router interface so the router answers ARPs for it
echo "Binding IP alias $GUEST_IP/32 to br-lan..."
ip addr add "${GUEST_IP}/32" dev br-lan >/dev/null 2>&1 || true

# Clean up rule and netcat on signal
cleanup() {
    echo "Cleaning up IP alias $GUEST_IP/32 and port listeners..."
    [ -n "$NC_PID" ] && kill "$NC_PID" 2>/dev/null
    ip addr del "${GUEST_IP}/32" dev br-lan >/dev/null 2>&1 || true
    exit 0
}
trap cleanup SIGTERM SIGINT

# 2. Intercept incoming connection to the guest port in background
if [ "$PROTO" = "udp" ]; then
    echo "Listening on UDP ${GUEST_IP}:${PORT_NUM}..."
    nc -u -l -p "$PORT_NUM" -s "$GUEST_IP" -w 2 >/dev/null 2>&1 &
else
    echo "Listening on TCP ${GUEST_IP}:${PORT_NUM}..."
    nc -l -p "$PORT_NUM" -s "$GUEST_IP" -w 2 >/dev/null 2>&1 &
fi
NC_PID=$!

# Wait for netcat to intercept a packet or timeout
wait "$NC_PID"

# 3. Connection intercepted! Remove IP alias instantly to restore native routing
echo "Connection intercepted! Restoring native routing..."
ip addr del "${GUEST_IP}/32" dev br-lan >/dev/null 2>&1 || true

# 4. Trigger Wake-on-Demand Sequence
# Check if Proxmox host is awake. If not awake, wake the entire host first.
if ! ping -c 1 -W 1 "$HOST_IP" >/dev/null 2>&1; then
    echo "Proxmox Host ($HOST_IP) is offline. Dispatching Wake-on-LAN..."
    etherwake -i br-lan "$HOST_MAC"
    
    # Wait for Proxmox host to boot up
    echo "Waiting for Proxmox host to boot up..."
    while true; do
        if ping -c 1 -W 1 "$HOST_IP" >/dev/null 2>&1; then
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
if [ -n "$BOT_TOKEN" ] && [ "$BOT_TOKEN" != "YOUR_TELEGRAM_BOT_TOKEN" ]; then
    local target_chats="${NOTIFY_CHAT_ID}"
    [ -z "$target_chats" ] && target_chats=$(echo "$ALLOWED_USER_IDS" | cut -d',' -f1)
    
    for chat in $(echo "$target_chats" | tr ',' ' '); do
        # If notifications are disabled, only notify IDs in ALLOWED_USER_IDS (admin private chats)
        if [ "$DISABLE_NOTIFICATIONS" = "1" ]; then
            local is_allowed=0
            for allowed in $(echo "$ALLOWED_USER_IDS" | tr ',' ' '); do
                if [ "$chat" = "$allowed" ]; then
                    is_allowed=1
                    break
                fi
            done
            if [ "$is_allowed" -eq 0 ]; then
                continue
            fi
        fi
        
        curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
            --data-urlencode "chat_id=${chat}" \
            --data-urlencode "text=$MSG" \
            --data-urlencode "parse_mode=Markdown" >/dev/null &
    done
fi

# Exit cleanly
exit 0
