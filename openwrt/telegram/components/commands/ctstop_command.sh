#!/bin/bash

ctstop_command() {
    local chat_id="$1"
    local message_id="$2"
    local vmid="$3"
    local command_str="/ctstop $vmid"

    if [ -z "$vmid" ]; then
        send_message "$chat_id" "$MSG_BOT_CT_STOP_USAGE" "" "$message_id"
        return
    fi

    if ! validate_numeric_arg "$chat_id" "$vmid" "VMID" "$message_id"; then return; fi
    if ! cmd_check_maintenance_active "$chat_id" "$message_id" "$command_str"; then return; fi

    if ! is_host_alive; then
        send_message "$chat_id" "$MSG_HOST_OFFLINE" "" "$message_id"
        return
    fi

    send_message "$chat_id" "$MSG_BOT_CT_STOP_STOPPING" "" "$message_id"
    if ! $SSH_CMD "pct status $vmid" >/dev/null 2>&1; then
        export arg1="$vmid"; send_message "$chat_id" "$MSG_BOT_CT_STOP_NOT_FOUND" "" "$message_id"
        return
    fi

    local stop_out
    stop_out=$($SSH_CMD "pct stop $vmid" 2>&1)
    local ret=$?
    local clean_stop=$(echo "$stop_out" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    if [ $ret -ne 0 ]; then
        export arg1="$vmid"; export arg2="${clean_stop:-Command failed with exit code $ret}"; send_message "$chat_id" "$MSG_BOT_CT_STOP_FAILED" "" "$message_id"
    else
        send_message "$chat_id" "$(expand_msg "$MSG_BOT_CT_STOP_SUCCESS")
\`\`\`
${clean_stop:-Stop signal dispatched}
\`\`\`" "" "$message_id"
    fi
}
