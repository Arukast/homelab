#!/bin/bash

hostreboot_command() {
    local message_id="$3"
    local command_str="/hostreboot"

    if ! cmd_check_host_alive "$chat_id" "$message_id"; then return; fi
    if ! cmd_check_maintenance_active "$chat_id" "$message_id" "$command_str"; then return; fi
    if ! cmd_blocking_guests_check "$chat_id" "$message_id"; then return; fi

    send_message "$chat_id" "$(expand_msg "$MSG_BOT_REBOOT_SENDING")" "" "$message_id"
    echo "REBOOT" > /tmp/homelab_target_state
    $SSH_CMD "nohup /usr/local/bin/proxmox_idle_monitor.sh --reboot >/dev/null 2>&1 &" 2>/dev/null
    send_message "$chat_id" "$(expand_msg "$MSG_BOT_REBOOT_EXECUTED")" "" "$message_id"
}