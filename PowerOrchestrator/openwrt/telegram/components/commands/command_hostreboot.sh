#!/bin/bash

hostreboot_command() {
    if ! is_host_alive; then
        send_message "$chat_id" "$MSG_BOT_REBOOT_ALREADY_OFFLINE"
        return
    fi

    # Safe check: block if there are running VMs or containers (excluding exempt guests)
    local running_guests=$($SSH_CMD "pct list | awk 'NR>1 && \$2==\"running\" {print \$1}'; qm list | awk 'NR>1 && \$3==\"running\" {print \$1}'" 2>/dev/null)
    local blocking_guests=""

    for vmid in $running_guests; do
        local is_exempt=0
        for exempt in $(echo "$EXEMPT_SHUTDOWN_GUESTS" | tr ',' ' '); do
            if [ "$vmid" = "$exempt" ]; then
                is_exempt=1
                break
            fi
        done
        if [ "$is_exempt" -eq 0 ]; then
            blocking_guests="$blocking_guests $vmid"
        fi
    done

    if [ -n "$blocking_guests" ]; then
        local clean_blocking=$(echo "$blocking_guests" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
        send_message "$chat_id" "*Reboot Blocked:* Core power actions are blocked because active non-exempt guest(s) are running: *${clean_blocking}*.

Please stop them first, or use \`/hostrebootforce\`."
        return
    fi

    send_message "$chat_id" "$MSG_BOT_REBOOT_SENDING"
    echo "REBOOT" > /tmp/homelab_target_state
    # Run the idle monitor script on Proxmox in background with --reboot (respects other idle checks)
    $SSH_CMD "nohup /usr/local/bin/proxmox_idle_monitor.sh --reboot >/dev/null 2>&1 &" 2>/dev/null
    send_message "$chat_id" "$MSG_BOT_REBOOT_EXECUTED"
}
