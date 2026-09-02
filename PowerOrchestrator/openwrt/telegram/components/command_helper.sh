#!/bin/bash
# =============================================================================
# OpenWrt Telegram Bot Command Helper
# Shared utilities for Telegram command handlers
# File: /usr/bin/telegram_components/command_helper.sh
# =============================================================================

# Common: check host aliveness and send appropriate offline message
cmd_check_host_alive() {
    local chat_id="$1"
    local message_id="$2"
    if ! is_host_alive; then
        send_message "$chat_id" "$MSG_HOST_OFFLINE" "" "$message_id"
        return 1
    fi
    return 0
}

# Common: check for blocking guests (VMs/containers) during shutdown/reboot
# Sets blocking_guests variable if guests found; returns 1 if blocking, 0 otherwise
cmd_blocking_guests_check() {
    local chat_id="$1"
    local message_id="$2"
    local running_guests="$($SSH_CMD "pct list | awk 'NR>1 && \$2==\"running\" {print \$1}'; qm list | awk 'NR>1 && \$3==\"running\" {print \$1}'" 2>/dev/null)"
    local blocking_guests=""

    if [ -n "$running_guests" ]; then
        for vmid in $running_guests; do
            local is_exempt=0
            for exempt in $(echo "$EXEMPT_SHUTDOWN_GUESTS" | tr ',' ' '); do
                if [ "$vmid" = "$exempt" ]; then
                    is_exempt=1
                    break
                fi
            done
            if [ "$is_exempt" -eq 0 ]; then
                blocking_guests="$blocking_guests $vmid"
            fi
        done
    fi

    if [ -n "$blocking_guests" ]; then
        local clean_blocking=$(echo "$blocking_guests" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
        send_message "$chat_id" "*Shutdown Blocked:* Core power actions are blocked because active non-exempt guest(s) are running: *${clean_blocking}*.

Please stop them first, or use \`/hostshutdownforce\`." "" "$message_id"
        return 1
    fi
    return 0
}

# Check if system or specific service is under maintenance
cmd_check_maintenance_active() {
    local chat_id="$1"
    local message_id="$2"
    local cmd_str="$3"
    local target_id="$4"

    # Check System Maintenance
    if [ -f "/etc/homelab_maintenance/system" ]; then
        local reason=$(cat "/etc/homelab_maintenance/system")
        send_message "$chat_id" "⚠️ *Action Blocked:* System-wide maintenance is ACTIVE.
Reason: _${reason}_
Command \`$cmd_str\` is prohibited." "" "$message_id"
        return 1
    fi

    # Check Service Maintenance
    if [ -n "$target_id" ]; then
        if [ -f "/etc/homelab_maintenance/service_${target_id}" ]; then
            local reason=$(cat "/etc/homelab_maintenance/service_${target_id}")
            send_message "$chat_id" "⚠️ *Action Blocked:* Service *${target_id}* is under maintenance.
Reason: _${reason}_
Command \`$cmd_str\` is prohibited." "" "$message_id"
            return 1
        fi
    fi

    return 0
}

# Ensure system is UNDER maintenance before allowing an action
cmd_require_maintenance() {
    local chat_id="$1"
    local message_id="$2"
    local cmd_str="$3"

    if [ ! -f "/etc/homelab_maintenance/system" ]; then
        send_message "$chat_id" "⚠️ *Action Blocked:* The host is currently in its *Active Window*.
Core power actions are prohibited to prevent accidental downtime.

Please enable maintenance mode first, or use the \`force\` version of this command (e.g., \`$cmd_str'force\`)." "" "$message_id"
        return 1
    fi
    return 0
}
validate_numeric_arg() {
    local chat_id="$1"
    local val="$2"
    local label="$3"
    local message_id="$4"

    if ! echo "$val" | grep -qE "^[0-9]+$"; then
        send_message "$chat_id" "Error: $label must be numeric." "" "$message_id"
        return 1
    fi
    return 0
}