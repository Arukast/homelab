#!/bin/bash

vmrestart_command() {
    local vmid="$arg1"

    validate_numeric_arg "$chat_id" "$vmid" "VMID" || return

    if ! is_host_alive; then
        send_message "$chat_id" "$MSG_HOST_OFFLINE"
        return
    fi

    send_message "$chat_id" "[Restart] Sending reboot signal to Virtual Machine $vmid..."
    if ! "$SSH_CMD" "qm status $vmid" >/dev/null 2>&1; then
        send_message "$chat_id" "[Error] Virtual Machine ID $vmid not found on Proxmox. (If this is an LXC, use /ctrestart $vmid)"
        return
    fi

    local res_out
    res_out=$("$SSH_CMD" "qm reboot $vmid" 2>&1)
    local ret=$?
    local clean_res=$(echo "$res_out" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    if [ $ret -ne 0 ]; then
        send_message "$chat_id" "[Error] Failed to restart VM ID $vmid:
\`\`\`
${clean_res:-Command failed with exit code $ret}
\`\`\`"
    else
        send_message "$chat_id" "[Success] VM $vmid restart response:
\`\`\`
${clean_res:-Reboot signal dispatched}
\`\`\`"
    fi
}