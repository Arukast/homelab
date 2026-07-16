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

# Load messages config
MSG_CONF="/etc/homelab_messages.conf"
if [ -f "$MSG_CONF" ]; then
    . "$MSG_CONF"
fi

# Parse port and protocol (e.g. 19132/udp -> PORT_NUM=19132, PROTO=udp)
PORT_NUM="${PORT_RAW%/*}"
PROTO=""
if [ "$PORT_NUM" != "$PORT_RAW" ]; then
    PROTO="${PORT_RAW#*/}"
fi
[ -z "$PROTO" ] && PROTO="tcp"

# Clean up netcat on signal
cleanup() {
    echo "Stopping game wake listener..."
    [ -n "$NC_PID" ] && kill "$NC_PID" 2>/dev/null
    exit 0
}
trap cleanup SIGTERM SIGINT

# Listen on game port in background
# nc will block until a player attempts a connection.
# We set a 2-second timeout (-w 2) to ensure the listener exits quickly after 
# the player hits the port, allowing the script to wake the host and monitor its boot.
if [ "$PROTO" = "udp" ]; then
    echo "Starting UDP listener on port $PORT_NUM..."
    nc -u -l -p "$PORT_NUM" -w 2 >/dev/null 2>&1 &
else
    echo "Starting TCP listener on port $PORT_NUM..."
    nc -l -p "$PORT_NUM" -w 2 >/dev/null 2>&1 &
fi
NC_PID=$!

# Wait for netcat to intercept a connection
wait "$NC_PID"

# Player connection detected!
echo "Player connection detected on port $PORT_RAW. Initiating host wake sequence..."

# 1. Dispatch Wake-on-LAN
etherwake -i br-lan "$HOST_MAC"

# 2. Dispatch notifications
MSG=$(eval echo "\"$MSG_WAKE_GAME_PLAYER\"")
/usr/bin/homelab_notify.sh "$MSG" &

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
