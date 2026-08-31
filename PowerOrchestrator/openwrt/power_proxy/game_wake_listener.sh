#!/bin/sh
# =============================================================================
# OpenWrt Game Wake-on-Demand Listener
# File: /usr/bin/game_wake_listener.sh
# Usage: /usr/bin/game_wake_listener.sh <port>
# =============================================================================

# Load shared components from /usr/bin/components
SHARED_COMP="/usr/bin/components"
# Load power_proxy components from /usr/bin/power_proxy_components
PP_COMP="/usr/bin/power_proxy_components"

# Load Helper
. "$SHARED_COMP"/conf_helper.sh
. "$PP_COMP"/cleanup_helper.sh
. "$PP_COMP"/network_helper.sh
. "$PP_COMP"/listener_helper.sh

# Read Config
CONF="/etc/homelab_power.conf"
MSG_CONF="/etc/homelab_messages.conf"
read_conf "$CONF"
read_optional_conf "$MSG_CONF"

PORT_RAW="$1"

check_port

# Parse port and protocol (e.g. 19132/udp -> PORT_NUM=19132, PROTO=udp)
parse_port

trap cleanup_game SIGTERM SIGINT

# Listen on game port in background
# nc will block until a player attempts a connection.
# We set a 2-second timeout (-w 2) to ensure the listener exits quickly after
# the player hits the port, allowing the script to wake the host and monitor its boot.
listen_game

# Wait for netcat to intercept a connection
wait "$NC_PID"

# Player connection detected!
echo "Player connection detected on port $PORT_RAW. Initiating host wake sequence..."

# 1. Dispatch Wake-on-LAN
etherwake -i "${LAN_INTERFACE:-br-lan}" "$HOST_MAC"

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
