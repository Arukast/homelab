#!/bin/bash

hostshutdown_command() {
    cmd_check_host_alive "$chat_id" || return

    cmd_blocking_guests_check "$chat_id" || return

    send_message "$chat_id" "$MSG_BOT_SHUTDOWN_SENDING"
    echo "SHUTDOWN" > /tmp/homelab_target_state
    $SSH_CMD "nohup /usr/local/bin/proxmox_idle_monitor.sh --shutdown >/dev/null 2>&1 &" 2>/dev/null
    send_message "$chat_id" "$MSG_BOT_SHUTDOWN_EXECUTED"
}