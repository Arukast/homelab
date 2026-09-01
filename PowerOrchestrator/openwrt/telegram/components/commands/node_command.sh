#!/bin/bash

# Node Management Command Handler
# Handles start, stop, restart for VMs and Containers
# File: /usr/bin/telegram_components/commands/node_command.sh

node_command() {
    local chat_id="$1"
    local msg_id="$2"
    local type="$3"      # 'vm' or 'ct'
    local vmid="$4"
    local operation="$5" # 'start', 'stop', 'restart'

    # Validate VMID
    if ! echo "$vmid" | grep -qE "^[0-9]+$"; then
        send_message "$chat_id" "Error: Node ID must be numeric." "$msg_id"
        return
    fi

    # Enforce Maintenance Mode
    if ! cmd_check_maintenance "$chat_id" "$type" "$vmid"; then
        # Maintenance check already sent its own message
        return
    fi

    if ! is_host_alive; then
        send_message "$chat_id" "$MSG_HOST_OFFLINE" "$msg_id"
        return
    fi

    # Determine the actual command to run on Proxmox
    local proxmox_cmd=""
    case "$type" in
        vm)
            case "$operation" in
                start)   proxmox_cmd="qm start $vmid" ;;
                stop)    proxmox_cmd="qm shutdown $vmid" ;;
                restart) proxmox_cmd="qm reboot $vmid" ;;
            esac
            ;;
        ct)
            case "$operation" in
                start)   proxmox_cmd="pct start $vmid" ;;
                stop)    proxmox_cmd="pct stop $vmid" ;;
                restart) proxmox_cmd="pct reboot $vmid" ;;
            esac
            ;;
    esac

    if [ -z "$proxmox_cmd" ]; then
        send_message "$chat_id" "Invalid operation: $operation" "$msg_id"
        return
    fi

    # Execute in background to prevent bot hanging
    (
        send_message "$chat_id" "[Action] $operation on $type $vmid... Please wait." "$msg_id"

        local out
        out=$($SSH_CMD "$proxmox_cmd" 2>&1)
        local ret=$?

        if [ $ret -eq 0 ]; then
            local clean_out=$(echo "$out" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
            send_message "$chat_id" "[Success] $type $vmid $operation:
\`\`\`
${clean_out:-Completed}
\`\`\`" "$msg_id"
        else
            send_message "$chat_id" "[Error] Failed $operation on $type $vmid:
\`\`\`
${out:-Unknown error}
\`\`\`" "$msg_id"
        fi
    ) >/dev/null 2>&1 &
}