#!/bin/bash

ctrestart_command() {
    local chat_id="$1"
    local message_id="$2"
    local vmid="$3"
    local command_str="/ctrestart $vmid"

    if [ -z "$vmid" ]; then
        send_message "$chat_id" "$MSG_BOT_CT_RESTART_USAGE" "" "$message_id"
        return
    fi

    if ! validate_numeric_arg "$chat_id" "$vmid" "VMID" "$message_id"; then return; fi
    if ! cmd_check_maintenance_active "$chat_id" "$message_id" "$command_str"; then return; fi

    if ! is_host_alive; then
        send_message "$chat_id" "$MSG_HOST_OFFLINE" "" "$message_id"
        return
    fi

    send_message "$chat_id" "$MSG_BOT_CT_RESTART_RESTARTING" "" "$message_id"
    if ! $SSH_CMD "pct status $vmid" >/dev/null 2>&1; then
        export arg1="$vmid"; send_message "$chat_id" "$MSG_BOT_CT_RESTART_NOT_FOUND" "" "$message_id"
        return
    fi

    local res_out
    res_out=$($SSH_CMD "pct reboot $vmid" 2>&1)
    local ret=$?
    local clean_res=$(echo "$res_out" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    if [ $ret -ne 0 ]; then
        export arg1="$vmid"; export arg2="${clean_res:-Command failed with exit code $ret}"; send_message "$chat_id" "$MSG_BOT_CT_RESTART_FAILED" "" "$message_id"
    else
        send_message "$chat_id" "$(expand_msg "$MSG_BOT_CT_RESTART_SUCCESS")
\`\`\`
${clean_res:-Restart signal dispatched}
\`\`\`" "" "$message_id"
    fi
}
