#!/bin/bash

hostrebootforce_command() {
    cmd_check_host_alive "$chat_id" || return
    cmd_check_maintenance "$chat_id" "system" || return

    send_message "$chat_id" "$MSG_BOT_REBOOT_FORCE_SENDING"
    echo "REBOOT" > /tmp/homelab_target_state
    $SSH_CMD "nohup /usr/local/bin/proxmox_idle_monitor.sh --reboot --force >/dev/null 2>&1 &" 2>/dev/null
    send_message "$chat_id" "$MSG_BOT_REBOOT_EXECUTED"
}