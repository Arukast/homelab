#!/bin/bash

maintenance_command() {
    # Check if command is run inside openwrt or local mock environment
    local maint_cmd="homelab_maintenance"
    if [ -f "/usr/bin/homelab_maintenance" ]; then
        maint_cmd="/usr/bin/homelab_maintenance"
    elif [ -f "$(dirname "$0")/homelab_maintenance.sh" ]; then
        maint_cmd="$(dirname "$0")/homelab_maintenance.sh"
    fi

    if [ -z "$arg1" ]; then
        local maint_out=$($maint_cmd status)
        send_message "$chat_id" "$maint_out"
        return
    fi

    case "$arg1" in
        system)
            local msg=$(echo "$cmd" | cut -d' ' -f3-)
            if [ -z "$msg" ] || [ "$msg" = "$cmd" ] || [ "$msg" = "$arg1" ]; then
                send_message "$chat_id" "Usage: \`/maintenance system <reason>\` or \`/maintenance system off\`"
                return
            fi
            local maint_out=$($maint_cmd system "$msg")
            send_message "$chat_id" "$maint_out"
            ;;
        service)
            local args=$(echo "$cmd" | cut -d' ' -f3-)
            local vmid=$(echo "$args" | awk '{print $1}')
            local msg=$(echo "$args" | cut -d' ' -f2-)
            if [ -z "$vmid" ] || [ -z "$msg" ] || [ "$vmid" = "$args" ]; then
                send_message "$chat_id" "Usage: \`/maintenance service <vmid> <reason>\` or \`/maintenance service <vmid> off\`"
                return
            fi
            if ! echo "$vmid" | grep -qE "^[0-9]+$"; then
                send_message "$chat_id" "Error: VMID must be numeric."
                return
            fi
            local maint_out=$($maint_cmd service "$vmid" "$msg")
            send_message "$chat_id" "$maint_out"
            ;;
        off)
            local maint_out=$($maint_cmd off)
            send_message "$chat_id" "$maint_out"
            ;;
        status)
            local maint_out=$($maint_cmd status)
            send_message "$chat_id" "$maint_out"
            ;;
        *)
            send_message "$chat_id" "Unknown subcommand. Use: system, service, off, status"
            ;;
    esac
}