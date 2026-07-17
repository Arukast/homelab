#!/bin/sh
# =============================================================================
# OpenWrt Homelab Power Orchestrator Maintenance Control Utility
# File: /usr/bin/homelab_maintenance
# =============================================================================

MAINT_DIR="/etc/homelab_maintenance"
mkdir -p "$MAINT_DIR"

notify() {
    /usr/bin/homelab_notify.sh "$1"
}

show_status() {
    local active=0
    local status_msg=""
    
    if [ -f "${MAINT_DIR}/system" ]; then
        local msg=$(cat "${MAINT_DIR}/system")
        status_msg="⚠️ *System Maintenance is ACTIVE*
Reason: _${msg:-No message specified}_"
        active=1
    else
        status_msg="✅ *System Maintenance is INACTIVE*"
    fi
    
    status_msg="${status_msg}

*Service Maintenance Status:*"
    
    local files=$(ls ${MAINT_DIR}/service_* 2>/dev/null)
    if [ -n "$files" ]; then
        for f in $files; do
            local vmid=$(basename "$f" | cut -d'_' -f2)
            local msg=$(cat "$f")
            status_msg="${status_msg}
• VMID *${vmid}*: _${msg:-Under maintenance}_"
            active=1
        done
    else
        status_msg="${status_msg}
No individual services under maintenance."
    fi
    
    echo "$status_msg"
}

action="$1"

case "$action" in
    system)
        msg="$2"
        if [ -z "$msg" ]; then
            echo "Usage: homelab_maintenance system \"<reason>\" | off"
            exit 1
        fi
        
        if [ "$msg" = "off" ]; then
            if [ -f "${MAINT_DIR}/system" ]; then
                rm -f "${MAINT_DIR}/system"
                notify "🔧 *System Maintenance cleared.* All operations restored."
                echo "System maintenance cleared."
            else
                echo "System maintenance was not active."
            fi
        else
            echo "$msg" > "${MAINT_DIR}/system"
            notify "🔧 *System Maintenance ENABLED.*\nReason: ${msg}"
            echo "System maintenance enabled: $msg"
        fi
        ;;
        
    service)
        vmid="$2"
        msg="$3"
        if [ -z "$vmid" ] || [ -z "$msg" ]; then
            echo "Usage: homelab_maintenance service <vmid> \"<reason>\" | off"
            exit 1
        fi
        
        if ! echo "$vmid" | grep -qE "^[0-9]+$"; then
            echo "Error: VMID must be numeric."
            exit 1
        fi
        
        if [ "$msg" = "off" ]; then
            if [ -f "${MAINT_DIR}/service_${vmid}" ]; then
                rm -f "${MAINT_DIR}/service_${vmid}"
                notify "🔧 *Service Maintenance cleared* for VMID ${vmid}."
                echo "Service $vmid maintenance cleared."
            else
                echo "Service $vmid was not under maintenance."
            fi
        else
            echo "$msg" > "${MAINT_DIR}/service_${vmid}"
            notify "🔧 *Service Maintenance ENABLED* for VMID ${vmid}.\nReason: ${msg}"
            echo "Service $vmid maintenance enabled: $msg"
        fi
        ;;
        
    off)
        cleared=0
        if [ -f "${MAINT_DIR}/system" ]; then
            rm -f "${MAINT_DIR}/system"
            cleared=1
        fi
        
        # Check if there are any service maintenance files to clear
        local files=$(ls ${MAINT_DIR}/service_* 2>/dev/null)
        if [ -n "$files" ]; then
            for f in $files; do
                if [ -f "$f" ]; then
                    rm -f "$f"
                    cleared=1
                fi
            done
        fi
        
        if [ "$cleared" -eq 1 ]; then
            notify "🔧 *All maintenance settings cleared.* Homelab is fully operational."
            echo "All maintenance settings cleared."
        else
            echo "No active maintenance settings to clear."
        fi
        ;;
        
    status|"")
        show_status
        ;;
        
    *)
        echo "Usage: homelab_maintenance {system|service|off|status}"
        exit 1
        ;;
esac
