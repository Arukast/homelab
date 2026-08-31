#!/bin/bash

sleep_command() {
    if ! is_host_alive; then
        send_message "$chat_id" "$MSG_BOT_SLEEP_ALREADY_OFFLINE"
        return
    fi

    send_message "$chat_id" "$MSG_BOT_SLEEP_TRIGGERED"
    echo "SLEEP" > /tmp/homelab_target_state
    # Run the idle monitor script on Proxmox in background WITHOUT --force (evaluates idle criteria)
    $SSH_CMD "nohup /usr/local/bin/proxmox_idle_monitor.sh >/dev/null 2>&1 &" 2>/dev/null
    send_message "$chat_id" "$MSG_BOT_SLEEP_EXECUTED"
}
