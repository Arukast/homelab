#!/bin/bash

ctstop_command() {
    local vmid="$arg1" # Use arg1 which is already parsed

    validate_numeric_arg "$chat_id" "$vmid" "VMID" || return

    if ! is_host_alive; then
        send_message "$chat_id" "$MSG_HOST_OFFLINE"
        return
    fi

    send_message "$chat_id" "$(expand_msg "$MSG_BOT_CT_STOP_STOPPING")"
    if ! "$SSH_CMD" "pct status $vmid" >/dev/null 2>&1; then
        send_message "$chat_id" "[Error] LXC container ID $vmid not found on Proxmox. (If this is a VM, use /vmstop $vmid)"
        return
    fi

    local stop_out
    stop_out=$("$SSH_CMD" "pct stop $vmid" 2>&1)
    local ret=$?
    local clean_stop=$(echo "$stop_out" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    if [ $ret -ne 0 ]; then
        send_message "$chat_id" "[Error] Failed to stop LXC ID $vmid:
\`\`\`
${clean_stop:-Command failed with exit code $ret}
\`\`\`"
    else
        send_message "$chat_id" "$(expand_msg "$MSG_BOT_CT_STOP_SUCCESS")
\`\`\`
${clean_stop:-Stop signal dispatched}
\`\`\`"
    fi
}
