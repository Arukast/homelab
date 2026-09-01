#!/bin/bash

vmstart_command() {
    local vmid="$arg1"
    local message_id="$3"
    local command_str="/vmstart $vmid"

    if [ -z "$vmid" ]; then
        send_message "$chat_id" "[Usage] /vmstart <vmid>" "" "$message_id"
        return
    fi

    if ! validate_numeric_arg "$chat_id" "$vmid" "VMID" "$message_id"; then return; fi
    if ! cmd_check_maintenance_active "$chat_id" "$message_id" "$command_str"; then return; fi

    (
        if ! is_host_alive; then
            send_message "$chat_id" "Host is Offline: Dispatching Wake-on-LAN magic packet to wake Proxmox first..." "" "$message_id"
            etherwake -i "${LAN_INTERFACE:-br-lan}" "$HOST_MAC"

            send_message "$chat_id" "Waiting for Proxmox host to boot and respond to SSH (typically 30-45 seconds)..." "" "$message_id"

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
                send_message "$chat_id" "Timeout: Proxmox host did not respond to SSH in time. Please check physical status." "" "$message_id"
                return
            fi

            send_message "$chat_id" "Host Online: Proxmox host is awake! Proceeding to boot Virtual Machine..." "" "$message_id"
        fi

        send_message "$chat_id" "$(expand_msg "$MSG_BOT_CT_START_STARTING")" "" "$message_id"
        if ! $SSH_CMD "qm status $vmid" >/dev/null 2>&1; then
            send_message "$chat_id" "[Error] Virtual Machine ID $vmid not found on Proxmox. (If this is an LXC, use /ctstart $vmid)" "" "$message_id"
            return
        fi

        local start_out
        start_out=$($SSH_CMD "qm start $vmid" 2>&1)
        local ret=$?
        local clean_out=$(echo "$start_out" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
        if [ $ret -ne 0 ]; then
            send_message "$chat_id" "[Error] Failed to start VM ID $vmid:
\`\`\`
${clean_out:-Command failed with exit code $ret}
\`\`\`" "" "$message_id"
        else
            local display_out=$(echo "$clean_out" | grep -vE "failed to reset PCI device|error writing '1' to '/sys/bus/pci/devices/.*reset'|swtpm_setup:" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
            send_message "$chat_id" "[Success] VM $vmid start response:
\`\`\`
${display_out:-Started successfully}
\`\`\`" "" "$message_id"
        fi
    ) >/dev/null 2>&1 </dev/null &
}