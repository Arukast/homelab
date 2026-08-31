#!/bin/bash

hostrebootforce_command() {
    if ! is_host_alive; then
        send_message "$chat_id" "$MSG_BOT_REBOOT_ALREADY_OFFLINE"
        return
    fi
    send_message "$chat_id" "$MSG_BOT_REBOOT_FORCE_SENDING"
    echo "REBOOT" > /tmp/homelab_target_state
    # Run the idle monitor script on Proxmox in background with --reboot --force (bypasses checks, suspends/stops guests cleanly)
    $SSH_CMD "nohup /usr/local/bin/proxmox_idle_monitor.sh --reboot --force >/dev/null 2>&1 &" 2>/dev/null
    send_message "$chat_id" "$MSG_BOT_REBOOT_EXECUTED"
}
