#!/bin/bash

node_command() {
    local chat_id="$1"
    local message_id="$2"
    local operation="$3"
    local type="$4"
    local vmid="$5"

    if [ -z "$vmid" ] || ! echo "$vmid" | grep -q '^[0-9]\+$'; then
        send_message "$chat_id" "$MSG_BOT_MAINT_ERR_NUMERIC" "" "$message_id"
        return
    fi

    if ! is_host_alive; then
        send_message "$chat_id" "$MSG_HOST_OFFLINE" "" "$message_id"
        return
    fi

    # Validate operation
    if ! echo "$operation" | grep -q '^\(start\|stop\|restart\)$'; then
        export arg1="$operation"; send_message "$chat_id" "$MSG_BOT_NODE_ERR_INVALID_OP" "" "$message_id"
        return
    fi

    export arg1="$operation"; export arg2="$type"; export arg3="$vmid"; send_message "$chat_id" "$MSG_BOT_NODE_ACTION_WAITING" "" "$message_id"

    local cmd="pct"
    [ "$type" == "vm" ] && cmd="qm"

    local out
    out=$($SSH_CMD "$cmd $operation $vmid" 2>&1)
    local ret=$?
    local clean_out=$(echo "$out" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')

    if [ $ret -ne 0 ]; then
        export arg1="$operation"; export arg2="$type"; export arg3="$vmid"; export arg4="${clean_out:-Command failed with exit code $ret}"; send_message "$chat_id" "$MSG_BOT_NODE_FAILED" "" "$message_id"
    else
        export arg1="$operation"; export arg2="$type"; export arg3="$vmid"; export arg4="${clean_out:-Success}"; send_message "$chat_id" "$MSG_BOT_NODE_SUCCESS" "" "$message_id"
    fi
}
