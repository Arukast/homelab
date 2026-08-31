#!/bin/bash

vmstop_command() {
    if [ -z "$arg1" ]; then
        send_message "$chat_id" "[Usage] /vmstop <vmid>"
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

    send_message "$chat_id" "[Stop] Sending ACPI shutdown signal to Virtual Machine $arg1..."
    if ! $SSH_CMD "qm status $arg1" >/dev/null 2>&1; then
        send_message "$chat_id" "[Error] Virtual Machine ID $arg1 not found on Proxmox. (If this is an LXC, use /ctstop $arg1)"
        return
    fi

    local stop_out
    stop_out=$($SSH_CMD "qm shutdown $arg1" 2>&1)
    local ret=$?
    local clean_stop=$(echo "$stop_out" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    if [ $ret -ne 0 ]; then
        send_message "$chat_id" "[Error] Failed to stop VM ID $arg1:
\`\`\`
${clean_stop:-Command failed with exit code $ret}
\`\`\`"
    else
        send_message "$chat_id" "[Success] VM $arg1 stop response:
\`\`\`
${clean_stop:-Shutdown signal dispatched}
\`\`\`"
    fi
}
