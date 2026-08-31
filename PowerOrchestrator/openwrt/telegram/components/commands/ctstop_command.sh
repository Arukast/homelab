#!/bin/bash

ctstop_command() {
    if [ -z "$arg1" ]; then
        send_message "$chat_id" "$MSG_BOT_CT_STOP_USAGE"
        return
    fi

    if ! echo "$arg1" | grep -qE "^[0-9]+$"; then
        send_message "$chat_id" "Error: VMID must be numeric."
        return
    fi

    if ! is_host_alive; then
        send_message "$chat_id" "$MSG_BOT_CT_STOP_HOST_OFFLINE"
        return
    fi

    send_message "$chat_id" "$(expand_msg "$MSG_BOT_CT_STOP_STOPPING")"
    if ! $SSH_CMD "pct status $arg1" >/dev/null 2>&1; then
        send_message "$chat_id" "[Error] LXC container ID $arg1 not found on Proxmox. (If this is a VM, use /vmstop $arg1)"
        return
    fi

    local stop_out
    stop_out=$($SSH_CMD "pct stop $arg1" 2>&1)
    local ret=$?
    local clean_stop=$(echo "$stop_out" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    if [ $ret -ne 0 ]; then
        send_message "$chat_id" "[Error] Failed to stop LXC ID $arg1:
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
