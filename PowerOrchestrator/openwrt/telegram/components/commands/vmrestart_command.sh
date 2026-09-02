#!/bin/bash

vmrestart_command() {
    local chat_id="$1"
    local message_id="$2"
    local vmid="$3"
    local command_str="/vmrestart $vmid"

    if [ -z "$vmid" ]; then
        send_message "$chat_id" "[Usage] /vmrestart <vmid>" "" "$message_id"
        return
    fi

    if ! validate_numeric_arg "$chat_id" "$vmid" "VMID" "$message_id"; then return; fi
    if ! cmd_check_maintenance_active "$chat_id" "$message_id" "$command_str"; then return; fi

    if ! is_host_alive; then
        send_message "$chat_id" "$MSG_HOST_OFFLINE" "" "$message_id"
        return
    fi

    send_message "$chat_id" "[Restart] Sending reboot signal to Virtual Machine $vmid..." "" "$message_id"
    if ! $SSH_CMD "qm status $vmid" >/dev/null 2>&1; then
        send_message "$chat_id" "[Error] Virtual Machine ID $vmid not found on Proxmox. (If this is an LXC, use /ctrestart $vmid)" "" "$message_id"
        return
    fi

    local res_out
    res_out=$($SSH_CMD "qm reboot $vmid" 2>&1)
    local ret=$?
    local clean_res=$(echo "$res_out" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    if [ $ret -ne 0 ]; then
        send_message "$chat_id" "[Error] Failed to restart VM ID $vmid:
\`\`\`
${clean_res:-Command failed with exit code $ret}
\`\`\`" "" "$message_id"
    else
        send_message "$chat_id" "[Success] VM $vmid restart response:
\`\`\`
${clean_res:-Reboot signal dispatched}
\`\`\`" "" "$message_id"
    fi
}