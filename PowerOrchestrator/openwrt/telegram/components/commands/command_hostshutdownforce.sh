#!/bin/bash

hostshutdownforce_command() {
    if ! is_host_alive; then
        send_message "$chat_id" "$MSG_BOT_SHUTDOWN_ALREADY_OFFLINE"
        return
    fi
    send_message "$chat_id" "$MSG_BOT_SHUTDOWN_FORCE_SENDING"
    echo "SHUTDOWN" > /tmp/homelab_target_state
    # Run the idle monitor script on Proxmox in background with --shutdown --force (bypasses checks, suspends/stops guests cleanly)
    $SSH_CMD "nohup /usr/local/bin/proxmox_idle_monitor.sh --shutdown --force >/dev/null 2>&1 &" 2>/dev/null
    send_message "$chat_id" "$MSG_BOT_SHUTDOWN_EXECUTED"
}
