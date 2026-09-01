#!/bin/bash

vmstop_command() {
    local vmid="$arg1"
    local message_id="$3"
    local command_str="/vmstop $vmid"

    validate_numeric_arg "$chat_id" "$vmid" "VMID" "$message_id" || return
    if ! cmd_check_host_alive "$chat_id" "$message_id"; then return; fi
    if ! cmd_check_maintenance_active "$chat_id" "$message_id" "$command_str"; then return; fi

    send_message "$chat_id" "[Stop] Sending ACPI shutdown signal to Virtual Machine $vmid..." "" "$message_id"
    if ! "$SSH_CMD" "qm status $vmid" >/dev/null 2>&1; then
        send_message "$chat_id" "[Error] Virtual Machine ID $vmid not found on Proxmox. (If this is an LXC, use /ctstop $vmid)" "" "$message_id"
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
\`\`\`" "" "$message_id"
    else
        send_message "$chat_id" "[Success] VM $vmid stop response:
\`\`\`
${clean_stop:-Shutdown signal dispatched}
\`\`\`" "" "$message_id"
    fi
}
