#!/bin/bash

sleep_command() {
    cmd_check_host_alive "$chat_id" || return

    send_message "$chat_id" "$MSG_BOT_SLEEP_TRIGGERED"
    echo "SLEEP" > /tmp/homelab_target_state
    $SSH_CMD "nohup /usr/local/bin/proxmox_idle_monitor.sh >/dev/null 2>&1 &" 2>/dev/null
    send_message "$chat_id" "$MSG_BOT_SLEEP_EXECUTED"
}