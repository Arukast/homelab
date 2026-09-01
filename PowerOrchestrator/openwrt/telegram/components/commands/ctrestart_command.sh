#!/bin/bash

ctrestart_command() {
    local vmid="$arg1"
    local message_id="$3"
    local command_str="/ctrestart $vmid"

    validate_numeric_arg "$chat_id" "$vmid" "VMID" "$message_id" || return
    if ! cmd_check_host_alive "$chat_id" "$message_id"; then return; fi
    if ! cmd_check_maintenance_active "$chat_id" "$message_id" "$command_str"; then return; fi

    send_message "$chat_id" "$(expand_msg "$MSG_BOT_CT_RESTART_RESTARTING")" "" "$message_id"
    if ! "$SSH_CMD" "pct status $vmid" >/dev/null 2>&1; then
        send_message "$chat_id" "[Error] LXC container ID $vmid not found on Proxmox. (If this is a VM, use /vmrestart $vmid)" "" "$message_id"
        return
    fi

    local res_out
    res_out=$("$SSH_CMD" "pct reboot $vmid" 2>&1)
    local ret=$?
    local clean_res=$(echo "$res_out" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    if [ $ret -ne 0 ]; then
        send_message "$chat_id" "[Error] Failed to restart LXC ID $vmid:
\`\`\`
${clean_res:-Command failed with exit code $ret}
\`\`\`" "" "$message_id"
    else
        send_message "$chat_id" "$(expand_msg "$MSG_BOT_CT_RESTART_SUCCESS")
\`\`\`
${clean_res:-Restart signal dispatched}
\`\`\`" "" "$message_id"
    fi
}