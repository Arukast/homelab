#!/bin/sh
# =============================================================================
# OpenWrt Homelab Power Proxy and Redirection Daemon
# File: /usr/bin/power_proxy_daemon.sh
# =============================================================================

CONF="/etc/homelab_power.conf"
if [ ! -f "$CONF" ]; then
    echo "ERROR: Configuration file $CONF not found." >&2
    exit 1
fi

# Load config
. "$CONF"

# Load messages config
MSG_CONF="/etc/homelab_messages.conf"
if [ -f "$MSG_CONF" ]; then
    . "$MSG_CONF"
fi

# State variables
CURRENT_STATE="UNKNOWN"
FAILED_PINGS=0
GAME_PIDS=""

# Helper to send notifications
notify() {
    local msg="$1"
    echo "[Power Proxy] $msg"
    
    # Telegram dispatch
    if [ -n "$BOT_TOKEN" ] && [ "$BOT_TOKEN" != "YOUR_TELEGRAM_BOT_TOKEN" ]; then
        local target_chat="${NOTIFY_CHAT_ID}"
        [ -z "$target_chat" ] && target_chat=$(echo "$ALLOWED_USER_IDS" | cut -d',' -f1)
        
        if [ -n "$target_chat" ]; then
            curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
                --data-urlencode "chat_id=${target_chat}" \
                --data-urlencode "text=🔔 *Power Monitor:* $msg" \
                --data-urlencode "parse_mode=Markdown" >/dev/null &
        fi
    fi

    # Discord Webhook dispatch
    if [ -n "$DISCORD_WEBHOOK_URL" ]; then
        local color=3899126 # Default Cyber Blue
        if echo "$msg" | grep -iqE "awake|online|restored"; then
            color=1095905 # Green
        elif echo "$msg" | grep -iqE "sleep|S3|offline|down|shutdown"; then
            color=15680580 # Red/Amber
        elif echo "$msg" | grep -iqE "reboot|rebooting"; then
            color=9133302 # Purple/Indigo
        fi
        
        # Clean text for json
        local clean_msg=$(echo "$msg" | sed 's/"/\\"/g')
        local payload="{\"embeds\":[{\"title\":\"🔔 Power Monitor Notification\",\"description\":\"${clean_msg}\",\"color\":${color},\"footer\":{\"text\":\"Arukast Homelab Portal\"}}]}"
        
        curl -s -H "Content-Type: application/json" -X POST -d "$payload" "$DISCORD_WEBHOOK_URL" >/dev/null &
    fi
}

# Apply Static ARP to prevent IP drops while sleeping
apply_static_arp() {
    echo "Applying permanent static ARP: $HOST_IP -> $HOST_MAC on br-lan..."
    ip neigh replace "$HOST_IP" lladdr "$HOST_MAC" dev br-lan nud permanent
}

# Apply Nat Redirect rules dynamically
apply_redirects() {
    echo "Host is offline. Activating dynamic HTTP/HTTPS proxy redirects..."
    
    if command -v nft >/dev/null 2>&1; then
        # Modern OpenWrt (nftables)
        # We create a dedicated nat table 'homelab_power_nat' which can be instantly deleted
        nft delete table inet homelab_power_nat 2>/dev/null
        nft create table inet homelab_power_nat
        nft add chain inet homelab_power_nat dstnat "{ type nat hook prerouting priority dstnat - 5 ; policy accept ; }"
        
        # Add HTTP Redirects (to port 8080)
        for port in $(echo "$HTTP_REDIRECT_PORTS" | tr ',' ' '); do
            nft add rule inet homelab_power_nat dstnat ip daddr "$HOST_IP" tcp dport "$port" redirect to :8080
        done
        
        # Add HTTPS Redirects (to port 8443)
        for port in $(echo "$HTTPS_REDIRECT_PORTS" | tr ',' ' '); do
            nft add rule inet homelab_power_nat dstnat ip daddr "$HOST_IP" tcp dport "$port" redirect to :8443
        done
    else
        # Older OpenWrt (iptables)
        # Flush any existing rules first to prevent duplicates
        remove_redirects
        
        for port in $(echo "$HTTP_REDIRECT_PORTS" | tr ',' ' '); do
            iptables -t nat -I PREROUTING -p tcp -d "$HOST_IP" --dport "$port" -j REDIRECT --to-ports 8080
        done
        for port in $(echo "$HTTPS_REDIRECT_PORTS" | tr ',' ' '); do
            iptables -t nat -I PREROUTING -p tcp -d "$HOST_IP" --dport "$port" -j REDIRECT --to-ports 8443
        done
    fi
}

# Remove Nat Redirect rules dynamically
remove_redirects() {
    echo "Host is online. Deactivating HTTP/HTTPS proxy redirects..."
    
    if command -v nft >/dev/null 2>&1; then
        # Modern OpenWrt (nftables)
        nft delete table inet homelab_power_nat 2>/dev/null
    else
        # Older OpenWrt (iptables)
        for port in $(echo "$HTTP_REDIRECT_PORTS" | tr ',' ' '); do
            while iptables -t nat -D PREROUTING -p tcp -d "$HOST_IP" --dport "$port" -j REDIRECT --to-ports 8080 2>/dev/null; do :; done
        done
        for port in $(echo "$HTTPS_REDIRECT_PORTS" | tr ',' ' '); do
            while iptables -t nat -D PREROUTING -p tcp -d "$HOST_IP" --dport "$port" -j REDIRECT --to-ports 8443 2>/dev/null; do :; done
        done
    fi
}

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
                ip addr del "${GUEST_IP}/32" dev br-lan >/dev/null 2>&1 || true
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
            ip addr del "${GUEST_IP}/32" dev br-lan >/dev/null 2>&1 || true
        done
    fi
}

# Clean up rules and listeners on exit (SIGTERM/SIGINT)
cleanup() {
    echo "Terminating power proxy. Restoring network defaults..."
    remove_redirects
    stop_game_listeners
    stop_guest_listeners
    # Remove permanent static ARP (return to dynamic ARP)
    ip neigh del "$HOST_IP" dev br-lan 2>/dev/null
    exit 0
}

trap cleanup SIGTERM SIGINT

# Initialize ARP binding
apply_static_arp


# Loop
while true; do
    if ping -c 1 -W 1 "$HOST_IP" >/dev/null 2>&1; then
        # Host is ONLINE
        FAILED_PINGS=0
        if [ "$CURRENT_STATE" != "UP" ]; then
            remove_redirects
            stop_game_listeners
            
            if [ "$CURRENT_STATE" != "UNKNOWN" ]; then
                if [ "$CURRENT_STATE" = "DOWN_REBOOT" ]; then
                    notify "$MSG_DAEMON_REBOOT_AWAKE"
                elif [ "$CURRENT_STATE" = "DOWN_SHUTDOWN" ]; then
                    notify "$MSG_DAEMON_SHUTDOWN_AWAKE"
                else
                    notify "$MSG_DAEMON_AWAKE"
                fi
            fi
            rm -f /tmp/homelab_target_state
            CURRENT_STATE="UP"
        fi
        
        # Manage individual guest listeners when host is online
        manage_guest_listeners
    else
        # Host is OFFLINE / SLEEPING
        FAILED_PINGS=$((FAILED_PINGS + 1))
        
        if [ "$FAILED_PINGS" -ge "$PING_RETRIES" ] && [ "$CURRENT_STATE" != "DOWN" ] && [ "$CURRENT_STATE" != "DOWN_SHUTDOWN" ] && [ "$CURRENT_STATE" != "DOWN_REBOOT" ]; then
            # Stop any guest listeners because the entire host is sleeping/offline
            stop_guest_listeners
            
            # Read intended target state
            TARGET_STATE=$(cat /tmp/homelab_target_state 2>/dev/null)
            [ -z "$TARGET_STATE" ] && TARGET_STATE="SLEEP"
            
            if [ "$TARGET_STATE" = "SHUTDOWN" ]; then
                if [ "$CURRENT_STATE" != "UNKNOWN" ]; then
                    notify "$MSG_DAEMON_SHUTDOWN"
                fi
                CURRENT_STATE="DOWN_SHUTDOWN"
            elif [ "$TARGET_STATE" = "REBOOT" ]; then
                if [ "$CURRENT_STATE" != "UNKNOWN" ]; then
                    notify "$MSG_DAEMON_REBOOT"
                fi
                CURRENT_STATE="DOWN_REBOOT"
            else
                # Default S3 Sleep
                apply_redirects
                start_game_listeners
                
                if [ "$CURRENT_STATE" != "UNKNOWN" ]; then
                    notify "$MSG_DAEMON_SLEEP"
                fi
                CURRENT_STATE="DOWN"
            fi
        fi
    fi
    
    # Re-apply static ARP periodically in case of table flushes
    apply_static_arp
    
    sleep "$CHECK_INTERVAL"
done
