#!/bin/sh
# =============================================================================
# OpenWrt Game Wake-on-Demand Listener
# File: /usr/bin/game_wake_listener.sh
# Usage: /usr/bin/game_wake_listener.sh <port>
# =============================================================================

PORT_RAW="$1"
CONF="/etc/homelab_power.conf"

if [ -z "$PORT_RAW" ]; then
    echo "Usage: $0 <port>[/udp|/tcp]" >&2
    exit 1
fi

if [ ! -f "$CONF" ]; then
    echo "ERROR: Configuration file $CONF not found." >&2
    exit 1
fi

. "$CONF"

# Parse port and protocol (e.g. 19132/udp -> PORT_NUM=19132, PROTO=udp)
PORT_NUM=$(echo "$PORT_RAW" | cut -d'/' -f1)
PROTO=$(echo "$PORT_RAW" | cut -d'/' -f2 -s)
[ -z "$PROTO" ] && PROTO="tcp"

# Listen on game port
# nc will block until a player attempts a connection.
# We set a 2-second timeout (-w 2) to ensure the listener exits quickly after 
# the player hits the port, allowing the script to wake the host and monitor its boot.
if [ "$PROTO" = "udp" ]; then
    echo "Starting UDP listener on port $PORT_NUM..."
    nc -u -l -p "$PORT_NUM" -w 2 >/dev/null 2>&1
else
    echo "Starting TCP listener on port $PORT_NUM..."
    nc -l -p "$PORT_NUM" -w 2 >/dev/null 2>&1
fi

# Player connection detected!
echo "Player connection detected on port $PORT_RAW. Initiating host wake sequence..."

# 1. Dispatch Wake-on-LAN
etherwake -i br-lan "$HOST_MAC"

# 2. Dispatch notifications
MSG="🎮 *Game Player Connection:* Player detected on port $PORT_RAW! Sending Wake-on-LAN to Proxmox ($HOST_MAC)..."
if [ -n "$BOT_TOKEN" ] && [ "$BOT_TOKEN" != "YOUR_TELEGRAM_BOT_TOKEN" ]; then
    local target_chat="${NOTIFY_CHAT_ID}"
    [ -z "$target_chat" ] && target_chat=$(echo "$ALLOWED_USER_IDS" | cut -d',' -f1)
    
    if [ -n "$target_chat" ]; then
        curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
            --data-urlencode "chat_id=${target_chat}" \
            --data-urlencode "text=$MSG" \
            --data-urlencode "parse_mode=Markdown" >/dev/null &
    fi
fi

# 3. Wait for the real host service to boot up
# We check if the host is pingable, and if it's TCP, we also verify if the specific port responds.
while true; do
    if ping -c 1 -W 1 "$HOST_IP" >/dev/null 2>&1; then
        if [ "$PROTO" = "tcp" ]; then
            if nc -w 1 -z "$HOST_IP" "$PORT_NUM" >/dev/null 2>&1; then
                echo "Real game server on $HOST_IP:$PORT_NUM (TCP) is now ONLINE."
                break
            fi
        else
            echo "Real host $HOST_IP is now awake and pingable. UDP service on port $PORT_NUM is active."
            break
        fi
    fi
    sleep 2
done

# The real server is now online! We exit.
# The parent power_proxy_daemon will remove NAT rules and clean up this listener process.
exit 0
