#!/bin/sh
# =============================================================================
# Host Liveness Monitoring Component
# File: /usr/bin/telegram_components/liveness_monitor.sh
# =============================================================================

monitor_host_liveness() {
    # Ensure only one instance of the monitor runs
    local LIVENESS_PIDFILE="/var/run/telegram_liveness_monitor.pid"
    init_daemon_pid "$LIVENESS_PIDFILE" "Host Liveness Monitor"

    echo "Starting Host Liveness Monitor..."
    
    # Initial state
    local current_state
    if is_host_alive; then
        current_state="online"
    else
        current_state="offline"
    fi
    
    # Use the first authorized user as default notification target
    local notify_chat_id="${NOTIFY_CHAT_ID:-$(echo "$ALLOWED_USER_IDS" | cut -d',' -f1)}"
    
    if [ -z "$notify_chat_id" ]; then
        echo "Liveness Monitor: No notification chat ID configured. Monitoring only."
        # We can still monitor, but we can't notify
    fi

    while true; do
        local next_state
        if is_host_alive; then
            next_state="online"
        else
            next_state="offline"
        fi

        if [ "$current_state" != "$next_state" ]; then
            echo "Liveness Monitor: State transition detected: $current_state -> $next_state"
            
            if [ -n "$notify_chat_id" ]; then
                if [ "$next_state" = "online" ]; then
                    # Host came back online
                    send_message "$notify_chat_id" "$(expand_msg "${MSG_BOT_HOST_ONLINE:-Host is now ONLINE and reachable.}")" ""
                else
                    # Host went offline
                    send_message "$notify_chat_id" "$(expand_msg "${MSG_BOT_HOST_OFFLINE:-Host is now OFFLINE or suspended.}")" ""
                fi
            fi
            current_state="$next_state"
        fi
        
        # Poll every 60 seconds to balance responsiveness and load
        sleep 60
    done
}
