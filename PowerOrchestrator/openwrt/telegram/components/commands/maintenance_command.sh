#!/bin/sh
# =============================================================================
# /maintenance Bot Command Handler
# State helpers live in maintenance_helper.sh (sourced by the daemon).
# File: /usr/bin/telegram_components/commands/maintenance_command.sh
# =============================================================================

# Usage strings kept here so they stay close to the command logic
_MAINT_USAGE_SYSTEM="Usage: /maintenance system \`<on|off>\` \`[reason]\`"
_MAINT_USAGE_SERVICE="Usage: /maintenance service \`<vmid>\` \`<on|off>\` \`[reason]\`"

# ---------------------------------------------------------------------------
# _maint_reply <chat_id> <message_id> <text>
# Thin wrapper: reply to the current interaction and return 0.
# ---------------------------------------------------------------------------
_maint_reply() {
    send_message "$1" "$3" "" "$2"
}

# ---------------------------------------------------------------------------
# _maint_system_cmd <chat_id> <message_id> <on_or_off> [reason]
# ---------------------------------------------------------------------------
_maint_system_cmd() {
    local chat_id="$1"
    local message_id="$2"
    local op="$3"
    local reason="$4"

    local out
    if [ "$op" = "off" ]; then
        out=$(maintenance_set_system off)
    else
        if [ -z "$reason" ]; then
            _maint_reply "$chat_id" "$message_id" "$_MAINT_USAGE_SYSTEM"
            return
        fi
        out=$(maintenance_set_system on "$reason")
    fi

    _maint_reply "$chat_id" "$message_id" "$out"
}

# ---------------------------------------------------------------------------
# _maint_service_cmd <chat_id> <message_id> <vmid> <on_or_off> [reason]
# ---------------------------------------------------------------------------
_maint_service_cmd() {
    local chat_id="$1"
    local message_id="$2"
    local vmid="$3"
    local op="$4"
    local reason="$5"

    if ! echo "$vmid" | grep -qE '^[0-9]+$'; then
        _maint_reply "$chat_id" "$message_id" "VMID must be a number."
        return
    fi

    local out
    if [ "$op" = "off" ]; then
        out=$(maintenance_set_service "$vmid" off)
    else
        if [ -z "$reason" ]; then
            _maint_reply "$chat_id" "$message_id" "$_MAINT_USAGE_SERVICE"
            return
        fi
        out=$(maintenance_set_service "$vmid" on "$reason")
    fi

    _maint_reply "$chat_id" "$message_id" "$out"
}

# ---------------------------------------------------------------------------
# maintenance_command <chat_id> <message_id> [sub_cmd] [arg...]
#
# Sub-commands:
#   status                        — show current maintenance state
#   system <on|off> [reason]      — toggle system-wide maintenance
#   service <vmid> <on|off> [r]   — toggle per-service maintenance
#   off                           — clear ALL maintenance flags at once
# ---------------------------------------------------------------------------
maintenance_command() {
    local chat_id="$1"
    local message_id="$2"
    local sub_cmd="$3"
    local arg1="$4"
    local arg2="$5"
    local arg3="$6"

    # No sub-command → show help menu
    if [ -z "$sub_cmd" ]; then
        local markup
        markup=$(get_markup "maintenance")
        send_message "$chat_id" "$MSG_BOT_MAINT_HELP" "$markup" "$message_id"
        return
    fi

    case "$sub_cmd" in
        status)
            _maint_reply "$chat_id" "$message_id" "$(maintenance_status)"
            ;;

        system)
            # /maintenance system on [reason]
            # /maintenance system off
            if [ -z "$arg1" ]; then
                _maint_reply "$chat_id" "$message_id" "$_MAINT_USAGE_SYSTEM"
                return
            fi
            _maint_system_cmd "$chat_id" "$message_id" "$arg1" "$arg2"
            ;;

        service)
            # /maintenance service <vmid> on [reason]
            # /maintenance service <vmid> off
            if [ -z "$arg1" ] || [ -z "$arg2" ]; then
                _maint_reply "$chat_id" "$message_id" "$_MAINT_USAGE_SERVICE"
                return
            fi
            _maint_service_cmd "$chat_id" "$message_id" "$arg1" "$arg2" "$arg3"
            ;;

        off)
            # Clear all maintenance flags in one shot
            _maint_reply "$chat_id" "$message_id" "$(maintenance_clear_all)"
            ;;

        *)
            _maint_reply "$chat_id" "$message_id" \
                "Unknown sub-command \`$sub_cmd\`. Available: \`status\` · \`system\` · \`service\` · \`off\`"
            ;;
    esac
}
