#!/bin/bash

vmstop_command() {
    local vmid="$arg1" # Use arg1 which is already parsed

    validate_numeric_arg "$chat_id" "$vmid" "VMID" || return

    if ! is_host_alive; then
        send_message "$chat_id" "$MSG_HOST_OFFLINE"
        return
    fi

    send_message "$chat_id" "[Stop] Sending ACPI shutdown signal to Virtual Machine $vmid..."
    if ! "$SSH_CMD" "qm status $vmid" >/dev/null 2>&1; then
        send_message "$chat_id" "[Error] Virtual Machine ID $vmid not found on Proxmox. (If this is an LXC, use /ctstop $vmid)"
        return
    fi

    local stop_out
    stop_out=$("$SSH_CMD" "qm shutdown $vmid" 2>&1)
    local ret=$?
    local clean_stop=$(echo "$stop_out" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    if [ $ret -ne 0 ]; then
        send_message "$chat_id" "[Error] Failed to stop VM ID $vmid:
\`\`\`
${clean_stop:-Command failed with exit code $ret}
\`\`\`"
    else
        send_message "$chat_id" "[Success] VM $vmid stop response:
\`\`\`
${clean_stop:-Shutdown signal dispatched}
\`\`\`"
    fi
}
