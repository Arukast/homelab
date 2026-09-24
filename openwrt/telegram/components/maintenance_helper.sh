#!/bin/sh
# =============================================================================
# Maintenance State Helper
# Provides read/write helpers for the /etc/homelab_maintenance flag directory.
# Sourced by telegram_bot_daemon.sh — do not execute directly.
# File: /usr/bin/telegram_components/maintenance_helper.sh
# =============================================================================

MAINT_DIR="${MAINT_DIR:-/etc/homelab_maintenance}"

# ---------------------------------------------------------------------------
# maintenance_status
# Prints a Markdown-formatted status string covering system-wide and
# per-service maintenance flags.
# ---------------------------------------------------------------------------
maintenance_status() {
    mkdir -p "$MAINT_DIR"

    local status_msg
    if [ -f "${MAINT_DIR}/system" ]; then
        local reason
        reason=$(cat "${MAINT_DIR}/system")
        status_msg="System Maintenance is ACTIVE
Reason: _${reason:-No message specified}_"
    else
        status_msg="System Maintenance is INACTIVE"
    fi

    status_msg="${status_msg}

*Service Maintenance Status:*"

    local files
    files=$(ls "${MAINT_DIR}"/service_* 2>/dev/null)
    if [ -n "$files" ]; then
        for f in $files; do
            local vmid
            vmid=$(basename "$f" | cut -d'_' -f2)
            local msg
            msg=$(cat "$f")
            status_msg="${status_msg}
• VMID *${vmid}*: _${msg:-Under maintenance}_"
        done
    else
        status_msg="${status_msg}
No individual services under maintenance."
    fi

    printf '%s' "$status_msg"
}

# ---------------------------------------------------------------------------
# maintenance_set_system <on|off> [reason]
# Enables or disables system-wide maintenance.
# Prints a Markdown confirmation string.
# ---------------------------------------------------------------------------
maintenance_set_system() {
    local op="$1"
    local reason="$2"
    mkdir -p "$MAINT_DIR"

    if [ "$op" = "off" ]; then
        if [ -f "${MAINT_DIR}/system" ]; then
            rm -f "${MAINT_DIR}/system"
            printf 'System Maintenance cleared. All operations restored.'
        else
            printf 'System maintenance was not active.'
        fi
    else
        printf '%s' "${reason:-Maintenance}" > "${MAINT_DIR}/system"
        printf 'System Maintenance ENABLED.\nReason: _%s_' "$reason"
    fi
}

# ---------------------------------------------------------------------------
# maintenance_set_service <vmid> <on|off> [reason]
# Enables or disables maintenance for a specific guest (by VMID).
# Prints a Markdown confirmation string.
# ---------------------------------------------------------------------------
maintenance_set_service() {
    local vmid="$1"
    local op="$2"
    local reason="$3"
    mkdir -p "$MAINT_DIR"

    if [ "$op" = "off" ]; then
        if [ -f "${MAINT_DIR}/service_${vmid}" ]; then
            rm -f "${MAINT_DIR}/service_${vmid}"
            printf 'Service Maintenance cleared for VMID %s.' "$vmid"
        else
            printf 'Service %s was not under maintenance.' "$vmid"
        fi
    else
        printf '%s' "${reason:-Maintenance}" > "${MAINT_DIR}/service_${vmid}"
        printf 'Service Maintenance ENABLED for VMID %s.\nReason: _%s_' "$vmid" "$reason"
    fi
}

# ---------------------------------------------------------------------------
# maintenance_clear_all
# Removes all system and service maintenance flags at once.
# Prints a Markdown confirmation string.
# ---------------------------------------------------------------------------
maintenance_clear_all() {
    mkdir -p "$MAINT_DIR"
    local cleared=0

    if [ -f "${MAINT_DIR}/system" ]; then
        rm -f "${MAINT_DIR}/system"
        cleared=1
    fi

    local files
    files=$(ls "${MAINT_DIR}"/service_* 2>/dev/null)
    if [ -n "$files" ]; then
        rm -f $files
        cleared=1
    fi

    if [ "$cleared" -eq 1 ]; then
        printf 'All maintenance settings cleared. Homelab is fully operational.'
    else
        printf 'No active maintenance settings to clear.'
    fi
}
