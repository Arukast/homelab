#!/bin/bash

vmrestart_command() {
    if [ -z "$arg1" ]; then
        send_message "$chat_id" "[Usage] /vmrestart <vmid>"
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

    send_message "$chat_id" "[Restart] Sending reboot signal to Virtual Machine $arg1..."
    if ! $SSH_CMD "qm status $arg1" >/dev/null 2>&1; then
        send_message "$chat_id" "[Error] Virtual Machine ID $arg1 not found on Proxmox. (If this is an LXC, use /ctrestart $arg1)"
        return
    fi

    local res_out
    res_out=$($SSH_CMD "qm reboot $arg1" 2>&1)
    local ret=$?
    local clean_res=$(echo "$res_out" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    if [ $ret -ne 0 ]; then
        send_message "$chat_id" "[Error] Failed to restart VM ID $arg1:
\`\`\`
${clean_res:-Command failed with exit code $ret}
\`\`\`"
    else
        send_message "$chat_id" "[Success] VM $arg1 restart response:
\`\`\`
${clean_res:-Reboot signal dispatched}
\`\`\`"
    fi
}
