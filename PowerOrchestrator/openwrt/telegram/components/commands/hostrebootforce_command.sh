#!/bin/bash

hostrebootforce_command() {
    if ! is_host_alive; then
        send_message "$chat_id" "$MSG_HOST_OFFLINE" "" "$message_id"
        return
    fi
    cmd_check_maintenance_active "$chat_id" "" "/hostrebootforce" || return

    send_message "$chat_id" "$MSG_BOT_REBOOT_FORCE_SENDING" "" "$message_id"
    echo "REBOOT" > /tmp/homelab_target_state
    $SSH_CMD "nohup /usr/local/bin/proxmox_idle_monitor.sh --reboot --force >/dev/null 2>&1 &" 2>/dev/null
    send_message "$chat_id" "$MSG_BOT_REBOOT_EXECUTED" "" "$message_id"
}