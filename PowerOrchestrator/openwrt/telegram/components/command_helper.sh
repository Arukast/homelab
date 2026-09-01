#!/bin/bash
# =============================================================================
# OpenWrt Telegram Bot Command Helper
# Shared utilities for Telegram command handlers
# File: /usr/bin/telegram_components/command_helper.sh
# =============================================================================

# Common: check host aliveness and send appropriate offline message
cmd_check_host_alive() {
    local chat_id="$1"
    if ! is_host_alive; then
        send_message "$chat_id" "$MSG_HOST_OFFLINE"
        return 1
    fi
    return 0
}

# Common: check for blocking guests (VMs/containers) during shutdown/reboot
# Sets blocking_guests variable if guests found; returns 1 if blocking, 0 otherwise
cmd_blocking_guests_check() {
    local chat_id="$1"
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

Please stop them first, or use \`/hostshutdownforce\`."
        return 1
    fi
    return 0
}

# Helper to validate that an argument is a numeric VMID/CTID
validate_numeric_arg() {
    local chat_id="$1"
    local val="$2"
    local label="$3"

    if ! echo "$val" | grep -qE "^[0-9]+$"; then
        send_message "$chat_id" "Error: $label must be numeric."
        return 1
    fi
    return 0
}