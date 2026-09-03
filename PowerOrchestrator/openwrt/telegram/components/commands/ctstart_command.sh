#!/bin/bash

ctstart_command() {
    local chat_id="$1"
    local message_id="$2"
    local vmid="$3"
    local command_str="/ctstart $vmid"

    if [ -z "$vmid" ]; then
        send_message "$chat_id" "$MSG_BOT_CT_START_USAGE" "" "$message_id"
        return
    fi

    if ! validate_numeric_arg "$chat_id" "$vmid" "VMID" "$message_id"; then return; fi
    if ! cmd_check_maintenance_active "$chat_id" "$message_id" "$command_str"; then return; fi

    (
        # Re-establish scope for the subshell
        chat_id="$chat_id"
        message_id="$message_id"

        if ! is_host_alive; then
            send_message "$chat_id" "$MSG_BOT_CT_START_HOST_WAKING" "" "$message_id"
            etherwake -i "${LAN_INTERFACE:-br-lan}" "$HOST_MAC"

            send_message "$chat_id" "$MSG_BOT_CT_START_WAITING" "" "$message_id"

            local success=0
            local attempt=1
            while [ $attempt -le 25 ]; do
                if is_host_alive; then
                    if $SSH_CMD "echo OK" >/dev/null 2>&1; then
                        success=1
                        break
                    fi
                fi
                sleep 3
                attempt=$((attempt + 1))
            done

            if [ $success -eq 0 ]; then
                send_message "$chat_id" "$MSG_BOT_CT_START_TIMEOUT" "" "$message_id"
                return
            fi

            send_message "$chat_id" "$MSG_BOT_CT_START_HOST_ONLINE" "" "$message_id"
        fi

        send_message "$chat_id" "$MSG_BOT_CT_START_STARTING" "" "$message_id"
        if ! $SSH_CMD "pct status $vmid" >/dev/null 2>&1; then
            export arg1="$vmid"; send_message "$chat_id" "$MSG_BOT_CT_START_NOT_FOUND" "" "$message_id"
            return
        fi

        local start_out
        start_out=$($SSH_CMD "pct start $vmid" 2>&1)
        local ret=$?
        local clean_out=$(echo "$start_out" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
        if [ $ret -ne 0 ]; then
            export arg1="$vmid"; export arg2="${clean_out:-Command failed with exit code $ret}"; send_message "$chat_id" "$MSG_BOT_CT_START_FAILED" "" "$message_id"
        else
            local display_out=$(echo "$clean_out" | grep -vE "failed to reset PCI device|error writing '1' to '/sys/bus/pci/devices/.*reset'|swtpm_setup:" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
            send_message "$chat_id" "$(expand_msg "$MSG_BOT_CT_START_SUCCESS")
\`\`\`
${display_out:-Started successfully}
\`\`\`" "" "$message_id"
        fi
    ) >/dev/null 2>&1 </dev/null &
}
