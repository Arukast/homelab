#!/bin/sh

# Start Game Listeners in the background
start_game_listeners() {
    if [ "$ENABLE_PORT_WAKE_LISTENERS" = "0" ]; then
        echo "Port wake listeners are disabled, bypassing raw game wake listeners."
        return
    fi
    echo "Starting Game Wake-on-Demand listeners..."
    GAME_PIDS=""

    for port in $(echo "$GAME_REDIRECT_PORTS" | tr ',' ' '); do
        if [ -n "$port" ]; then
            /usr/bin/game_wake_listener.sh "$port" &
            GAME_PIDS="$GAME_PIDS $!"
        fi
    done
}

# Stop Game Listeners
stop_game_listeners() {
    echo "Stopping Game Wake-on-Demand listeners..."

    # Clean up background listeners by PID
    if [ -n "$GAME_PIDS" ]; then
        for pid in $GAME_PIDS; do
            kill "$pid" 2>/dev/null
        done
        GAME_PIDS=""
    fi

    # Also grep kill to ensure no orphaned listeners remain
    pkill -f "game_wake_listener.sh" 2>/dev/null
}

# Start Guest Listeners for any suspended guests
manage_guest_listeners() {
    [ -z "$GUEST_ORCHESTRATION_MAP" ] && return
    if [ "$ENABLE_PORT_WAKE_LISTENERS" = "0" ]; then
        return
    fi

    for entry in $(echo "$GUEST_ORCHESTRATION_MAP" | tr ',' ' '); do
        VMID=$(echo "$entry" | cut -d':' -f1)
        GUEST_IP=$(echo "$entry" | cut -d':' -f2)
        PORT_RAW=$(echo "$entry" | cut -d':' -f3)

        # Skip Wake-on-Demand listeners if no port is defined
        if [ -z "$PORT_RAW" ]; then
            continue
        fi

        if ping -c 1 -W 1 "$GUEST_IP" >/dev/null 2>&1; then
            if pgrep -f "guest_wake_listener.sh $GUEST_IP " >/dev/null 2>&1; then
                echo "Guest [$VMID] ($GUEST_IP) came online. Terminating listener..."
                pkill -f "guest_wake_listener.sh $GUEST_IP "
                ip addr del "${GUEST_IP}/32" dev "$IFACE" >/dev/null 2>&1 || true
            fi
        else
            for sub_port in $(echo "$PORT_RAW" | tr '+' ' '); do
                if ! pgrep -f "guest_wake_listener.sh $GUEST_IP $sub_port " >/dev/null 2>&1; then
                    echo "Guest [$VMID] ($GUEST_IP) is offline. Starting Wake-on-Demand listener on $sub_port..."
                    /usr/bin/guest_wake_listener.sh "$GUEST_IP" "$sub_port" "$VMID" &
                fi
            done
        fi
    done
}

# Stop all individual guest listeners
stop_guest_listeners() {
    echo "Stopping all individual guest Wake-on-Demand listeners..."
    pkill -f "guest_wake_listener.sh" 2>/dev/null

    if [ -n "$GUEST_ORCHESTRATION_MAP" ]; then
        for entry in $(echo "$GUEST_ORCHESTRATION_MAP" | tr ',' ' '); do
            GUEST_IP=$(echo "$entry" | cut -d':' -f2)
            ip addr del "${GUEST_IP}/32" dev "$IFACE" >/dev/null 2>&1 || true
        done
    fi
}

listen_game() {
    if [ "$PROTO" = "udp" ]; then
        echo "Starting UDP listener on port $PORT_NUM..."
        nc -u -l -p "$PORT_NUM" -w 2 >/dev/null 2>&1 &
    else
        echo "Starting TCP listener on port $PORT_NUM..."
        nc -l -p "$PORT_NUM" -w 2 >/dev/null 2>&1 &
    fi
    NC_PID=$!
}

listen_guest() {
    if [ "$PROTO" = "udp" ]; then
        echo "Listening on UDP ${GUEST_IP}:${PORT_NUM}..."
        nc -u -l -p "$PORT_NUM" -s "$GUEST_IP" -w 2 >/dev/null 2>&1 &
    else
        echo "Listening on TCP ${GUEST_IP}:${PORT_NUM}..."
        nc -l -p "$PORT_NUM" -s "$GUEST_IP" -w 2 >/dev/null 2>&1 &
    fi
    NC_PID=$!
}
