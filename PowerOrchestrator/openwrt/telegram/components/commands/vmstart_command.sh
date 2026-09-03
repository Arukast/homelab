#!/bin/bash

vmstart_command() {
    local chat_id="$1"
    local message_id="$2"
    local vmid="$3"
    local command_str="/vmstart $vmid"

    if [ -z "$vmid" ]; then
        send_message "$chat_id" "$MSG_BOT_VM_START_USAGE" "" "$message_id"
        return
    fi

    if ! validate_numeric_arg "$chat_id" "$vmid" "VMID" "$message_id"; then return; fi
    if ! cmd_check_maintenance_active "$chat_id" "$message_id" "$command_str"; then return; fi

    # Send starting notification in foreground to ensure it's delivered immediately
    send_message "$chat_id" "$MSG_BOT_VM_START_STARTING" "" "$message_id"

    (
        # Re-establish scope for the subshell
        chat_id="$chat_id"
        message_id="$message_id"
        if ! $SSH_CMD "qm status $vmid" >/dev/null 2>&1; then
            export arg1="$vmid"; send_message "$chat_id" "$MSG_BOT_VM_START_NOT_FOUND" "" "$message_id"
            return
        fi

        local start_out
        start_out=$($SSH_CMD "qm start $vmid" 2>&1)
        local ret=$?
        local clean_out=$(echo "$start_out" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
        if [ $ret -ne 0 ]; then
            export arg1="$vmid"; export arg2="${clean_out:-Command failed with exit code $ret}"; send_message "$chat_id" "$MSG_BOT_VM_START_FAILED" "" "$message_id"
        else
            local display_out=$(echo "$clean_out" | grep -vE "failed to reset PCI device|error writing '1' to '/sys/bus/pci/devices/.*reset'|swtpm_setup:" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
            export arg1="$vmid"; export arg2="${display_out:-Started successfully}"; send_message "$chat_id" "$MSG_BOT_VM_START_SUCCESS" "" "$message_id"
        fi
    ) >/dev/null 2>&1 </dev/null &
}
