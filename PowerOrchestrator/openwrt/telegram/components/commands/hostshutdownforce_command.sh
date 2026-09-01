#!/bin/bash

hostshutdownforce_command() {
    cmd_check_host_alive "$chat_id" || return

    send_message "$chat_id" "$MSG_BOT_SHUTDOWN_FORCE_SENDING"
    echo "SHUTDOWN" > /tmp/homelab_target_state
    $SSH_CMD "nohup /usr/local/bin/proxmox_idle_monitor.sh --shutdown --force >/dev/null 2>&1 &" 2>/dev/null
    send_message "$chat_id" "$MSG_BOT_SHUTDOWN_EXECUTED"
}