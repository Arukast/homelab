#!/bin/bash

vmstart_command() {
    if [ -z "$arg1" ]; then
        send_message "$chat_id" "[Usage] /vmstart <vmid>"
        return
    fi

    if ! echo "$arg1" | grep -qE "^[0-9]+$"; then
        send_message "$chat_id" "Error: VMID must be numeric."
        return
    fi

    (
        if ! is_host_alive; then
            send_message "$chat_id" "Host is Offline: Dispatching Wake-on-LAN magic packet to wake Proxmox first..."
            etherwake -i "${LAN_INTERFACE:-br-lan}" "$HOST_MAC"

            send_message "$chat_id" "Waiting for Proxmox host to boot and respond to SSH (typically 30-45 seconds)..."

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
                send_message "$chat_id" "Timeout: Proxmox host did not respond to SSH in time. Please check physical status."
                return
            fi

            send_message "$chat_id" "Host Online: Proxmox host is awake! Proceeding to boot Virtual Machine..."
        fi

        send_message "$chat_id" "$(expand_msg "$MSG_BOT_CT_START_STARTING")"
        if ! $SSH_CMD "qm status $arg1" >/dev/null 2>&1; then
            send_message "$chat_id" "[Error] Virtual Machine ID $arg1 not found on Proxmox. (If this is an LXC, use /ctstart $arg1)"
            return
        fi

        local start_out
        start_out=$($SSH_CMD "qm start $arg1" 2>&1)
        local ret=$?
        local clean_out=$(echo "$start_out" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
        if [ $ret -ne 0 ]; then
            send_message "$chat_id" "[Error] Failed to start VM ID $arg1:
\`\`\`
${clean_out:-Command failed with exit code $ret}
\`\`\`"
        else
            local display_out=$(echo "$clean_out" | grep -vE "failed to reset PCI device|error writing '1' to '/sys/bus/pci/devices/.*reset'|swtpm_setup:" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
            send_message "$chat_id" "[Success] VM $arg1 start response:
\`\`\`
${display_out:-Started successfully}
\`\`\`"
        fi
    ) >/dev/null 2>&1 </dev/null &
}