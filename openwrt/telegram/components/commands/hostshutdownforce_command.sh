#!/bin/bash

hostshutdownforce_command() {
    local message_id="$3"
    local command_str="/hostshutdownforce"

    if ! is_host_alive; then 
        send_message "$chat_id" "$MSG_HOST_OFFLINE" "" "$message_id"
        return 
    fi

    send_message "$chat_id" "$MSG_BOT_SHUTDOWN_FORCE_SENDING" "" "$message_id"
    echo "SHUTDOWN" > /tmp/homelab_target_state
    $SSH_CMD "nohup /usr/local/bin/proxmox_idle_monitor.sh --shutdown --force >/dev/null 2>&1 &" 2>/dev/null
    send_message "$chat_id" "$MSG_BOT_SHUTDOWN_EXECUTED" "" "$message_id"
}
