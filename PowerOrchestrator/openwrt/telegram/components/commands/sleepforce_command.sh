#!/bin/bash

sleepforce_command() {
    if ! is_host_alive; then
        send_message "$chat_id" "$MSG_BOT_SLEEP_ALREADY_OFFLINE"
        return
    fi

    send_message "$chat_id" "$MSG_BOT_SLEEP_FORCE_TRIGGERED"
    echo "SLEEP" > /tmp/homelab_target_state
    # Run the idle monitor script on Proxmox in background WITH --force so it suspends immediately
    $SSH_CMD "nohup /usr/local/bin/proxmox_idle_monitor.sh --force >/dev/null 2>&1 &" 2>/dev/null
    send_message "$chat_id" "$MSG_BOT_SLEEP_EXECUTED"
}
