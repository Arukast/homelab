#!/bin/sh

main() {
    # Loop
    while true; do
        if is_host_alive; then
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
                rm -f /tmp/waking_host
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
}
