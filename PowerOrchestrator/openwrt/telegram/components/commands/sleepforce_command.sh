#!/bin/bash

sleepforce_command() {
    local message_id="$3"
    local command_str="/sleepforce"

    if ! cmd_check_host_alive "$chat_id" "$message_id"; then return; fi
    if ! cmd_check_maintenance_active "$chat_id" "$message_id" "$command_str"; then return; fi

    send_message "$chat_id" "$MSG_BOT_SLEEP_FORCE_TRIGGERED" "" "$message_id"
    echo "SLEEP" > /tmp/homelab_target_state
    $SSH_CMD "nohup /usr/local/bin/proxmox_idle_monitor.sh --force >/dev/null 2>&1 &" 2>/dev/null
    send_message "$chat_id" "$MSG_BOT_SLEEP_EXECUTED" "" "$message_id"
}