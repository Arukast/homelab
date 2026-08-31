#!/bin/bash

ctrestart_command() {
    if [ -z "$arg1" ]; then
        send_message "$chat_id" "$MSG_BOT_CT_RESTART_USAGE"
        return
    fi

    if ! echo "$arg1" | grep -qE "^[0-9]+$"; then
        send_message "$chat_id" "Error: VMID must be numeric."
        return
    fi

    if ! is_host_alive; then
        send_message "$chat_id" "$MSG_BOT_CT_RESTART_HOST_OFFLINE"
        return
    fi

    send_message "$chat_id" "$(expand_msg "$MSG_BOT_CT_RESTART_RESTARTING")"
    if ! $SSH_CMD "pct status $arg1" >/dev/null 2>&1; then
        send_message "$chat_id" "[Error] LXC container ID $arg1 not found on Proxmox. (If this is a VM, use /vmrestart $arg1)"
        return
    fi

    local res_out
    res_out=$($SSH_CMD "pct reboot $arg1" 2>&1)
    local ret=$?
    local clean_res=$(echo "$res_out" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    if [ $ret -ne 0 ]; then
        send_message "$chat_id" "[Error] Failed to restart LXC ID $arg1:
\`\`\`
${clean_res:-Command failed with exit code $ret}
\`\`\`"
    else
        send_message "$chat_id" "$(expand_msg "$MSG_BOT_CT_RESTART_SUCCESS")
\`\`\`
${clean_res:-Restart signal dispatched}
\`\`\`"
    fi
}
