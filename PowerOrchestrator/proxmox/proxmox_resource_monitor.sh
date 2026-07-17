#!/bin/bash
# =============================================================================
# Proxmox VE Resource & Service Health Monitor
# File: /usr/local/bin/proxmox_resource_monitor.sh
# =============================================================================

CONF="/etc/homelab_power.conf"
MSG_CONF="/etc/homelab_messages.conf"

# Defaults
MONITOR_CPU_THRESHOLD_PCT=85
MONITOR_RAM_THRESHOLD_PCT=90
MONITOR_DISK_THRESHOLD_PCT=90
MONITOR_DISK_PATHS="/ /var/lib/vz"
MONITOR_SERVICES="pvedaemon pveproxy pvestatd"
MONITOR_ZFS_POOLS="rpool"
MONITOR_CRITICAL_GUESTS=""
MONITOR_COOLDOWN_SEC=14400
STATE_FILE="/tmp/proxmox_resource_monitor_states"
LOG_FILE="/var/log/proxmox_power.log"
ENABLE_SYSLOG=1

# Load configs
[ -f "$CONF" ] && source "$CONF"
[ -f "$MSG_CONF" ] && source "$MSG_CONF"

# Default fallback alert/ok messages if homelab_messages.conf is missing
MSG_MONITOR_CPU_ALERT=${MSG_MONITOR_CPU_ALERT:-'⚠️ *[Proxmox Warning]* CPU Load is high: *$VALUE%* (Threshold: $THRESHOLD%)'}
MSG_MONITOR_CPU_OK=${MSG_MONITOR_CPU_OK:-'✅ *[Proxmox Recovery]* CPU Load returned to normal: *$VALUE%*'}
MSG_MONITOR_RAM_ALERT=${MSG_MONITOR_RAM_ALERT:-'⚠️ *[Proxmox Warning]* RAM usage is high: *$VALUE%* (Threshold: $THRESHOLD%)'}
MSG_MONITOR_RAM_OK=${MSG_MONITOR_RAM_OK:-'✅ *[Proxmox Recovery]* RAM usage returned to normal: *$VALUE%*'}
MSG_MONITOR_DISK_ALERT=${MSG_MONITOR_DISK_ALERT:-'⚠️ *[Proxmox Warning]* Disk space on *$PATH* is high: *$VALUE%* (Threshold: $THRESHOLD%)'}
MSG_MONITOR_DISK_OK=${MSG_MONITOR_DISK_OK:-'✅ *[Proxmox Recovery]* Disk space on *$PATH* returned to normal: *$VALUE%*'}
MSG_MONITOR_SERVICE_ALERT=${MSG_MONITOR_SERVICE_ALERT:-'⚠️ *[Proxmox Warning]* Service *$SERVICE* is NOT running!'}
MSG_MONITOR_SERVICE_OK=${MSG_MONITOR_SERVICE_OK:-'✅ *[Proxmox Recovery]* Service *$SERVICE* is running again.'}
MSG_MONITOR_ZFS_ALERT=${MSG_MONITOR_ZFS_ALERT:-'🚨 *[Proxmox Alert]* ZFS pool status is unhealthy: *$VALUE*'}
MSG_MONITOR_ZFS_OK=${MSG_MONITOR_ZFS_OK:-'✅ *[Proxmox Recovery]* ZFS pools are healthy now.'}
MSG_MONITOR_GUEST_ALERT=${MSG_MONITOR_GUEST_ALERT:-'⚠️ *[Proxmox Warning]* Critical guest *$GUEST_NAME* (VMID $VMID) is NOT running!'}
MSG_MONITOR_GUEST_OK=${MSG_MONITOR_GUEST_OK:-'✅ *[Proxmox Recovery]* Critical guest *$GUEST_NAME* (VMID $VMID) is running again.'}

log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$msg" >> "$LOG_FILE"
    if [ "$ENABLE_SYSLOG" -eq 1 ]; then
        logger -t "proxmox-resource-monitor" "$1"
    fi
    echo "$msg"
}

notify() {
    local msg="$1"
    log "NOTIFICATION: $msg"
    if [ -n "$NOTIFICATION_URL" ]; then
        curl -s --connect-timeout 2 --max-time 5 -X POST \
            --data-urlencode "msg=$msg" \
            "$NOTIFICATION_URL" >/dev/null &
    fi
}

touch "$STATE_FILE"
touch "$LOG_FILE"

get_state() {
    local key="$1"
    grep -E "^${key}:" "$STATE_FILE" 2>/dev/null
}

update_state() {
    local key="$1"
    local status="$2"
    local timestamp="$3"
    if [ -f "$STATE_FILE" ]; then
        grep -vE "^${key}:" "$STATE_FILE" > "${STATE_FILE}.tmp" 2>/dev/null
        mv "${STATE_FILE}.tmp" "$STATE_FILE"
    fi
    echo "${key}:${status}:${timestamp}" >> "$STATE_FILE"
}

check_metric() {
    local key="$1"
    local current_val="$2"
    local threshold="$3"
    local is_critical="$4" # 1 if critical, 0 if OK
    local alert_tmpl="$5"
    local recovery_tmpl="$6"
    local path_val="$7"
    local service_val="$8"
    local vmid_val="$9"
    local guest_name_val="${10}"
    local pool_val="${11}"

    # Setup variables for eval
    local VALUE="$current_val"
    local THRESHOLD="$threshold"
    local PATH="$path_val"
    local SERVICE="$service_val"
    local VMID="$vmid_val"
    local GUEST_NAME="$guest_name_val"
    local POOL="$pool_val"

    local state_line=$(get_state "$key")
    local prev_status=$(echo "$state_line" | cut -d':' -f2)
    local prev_timestamp=$(echo "$state_line" | cut -d':' -f3)
    [ -z "$prev_status" ] && prev_status="OK"
    [ -z "$prev_timestamp" ] && prev_timestamp=0

    local now=$(date +%s)

    if [ "$is_critical" -eq 1 ]; then
        local alert_msg=$(eval echo "\"$alert_tmpl\"")
        if [ "$prev_status" = "OK" ]; then
            log "Metric $key entered CRITICAL: $current_val"
            notify "$alert_msg"
            update_state "$key" "CRITICAL" "$now"
        else
            local elapsed=$((now - prev_timestamp))
            if [ "$elapsed" -ge "$MONITOR_COOLDOWN_SEC" ]; then
                log "Metric $key remains CRITICAL: $current_val. Sending reminder."
                notify "$alert_msg (Reminder)"
                update_state "$key" "CRITICAL" "$now"
            fi
        fi
    else
        if [ "$prev_status" = "CRITICAL" ]; then
            local recovery_msg=$(eval echo "\"$recovery_tmpl\"")
            log "Metric $key recovered to OK: $current_val"
            notify "$recovery_msg"
            update_state "$key" "OK" "$now"
        fi
    fi
}

# --- 1. Check CPU Utilization ---
read -r cpu a b c d e f g h i j < /proc/stat
prev_total=$((a+b+c+d+e+f+g+h+i+j))
prev_idle=$((d+e))
sleep 1
read -r cpu a b c d e f g h i j < /proc/stat
total=$((a+b+c+d+e+f+g+h+i+j))
idle=$((d+e))
diff_total=$((total - prev_total))
diff_idle=$((idle - prev_idle))
if [ "$diff_total" -eq 0 ]; then
    CPU_PCT=0
else
    CPU_PCT=$(( 100 * (diff_total - diff_idle) / diff_total ))
fi

CPU_CRITICAL=0
[ "$CPU_PCT" -gt "$MONITOR_CPU_THRESHOLD_PCT" ] && CPU_CRITICAL=1
check_metric "cpu" "$CPU_PCT" "$MONITOR_CPU_THRESHOLD_PCT" "$CPU_CRITICAL" "$MSG_MONITOR_CPU_ALERT" "$MSG_MONITOR_CPU_OK"

# --- 2. Check RAM Utilization ---
RAM_PCT=$(free | awk '/^Mem:/ {print int(($3 / $2) * 100)}')
RAM_CRITICAL=0
[ "$RAM_PCT" -gt "$MONITOR_RAM_THRESHOLD_PCT" ] && RAM_CRITICAL=1
check_metric "ram" "$RAM_PCT" "$MONITOR_RAM_THRESHOLD_PCT" "$RAM_CRITICAL" "$MSG_MONITOR_RAM_ALERT" "$MSG_MONITOR_RAM_OK"

# --- 3. Check Disk Utilization ---
for path in $MONITOR_DISK_PATHS; do
    if [ -d "$path" ] || [ -f "$path" ]; then
        DISK_PCT=$(df -h "$path" 2>/dev/null | awk 'NR==2 {print $5}' | tr -d '%')
        if [ -n "$DISK_PCT" ]; then
            DISK_CRITICAL=0
            [ "$DISK_PCT" -gt "$MONITOR_DISK_THRESHOLD_PCT" ] && DISK_CRITICAL=1
            # Replace non-alphanumeric chars in key to keep it clean
            key_path=$(echo "$path" | tr -cd 'a-zA-Z0-9_')
            [ -z "$key_path" ] && key_path="root"
            check_metric "disk_${key_path}" "$DISK_PCT" "$MONITOR_DISK_THRESHOLD_PCT" "$DISK_CRITICAL" "$MSG_MONITOR_DISK_ALERT" "$MSG_MONITOR_DISK_OK" "$path"
        fi
    fi
done

# --- 4. Check ZFS Pools ---
if [ -n "$MONITOR_ZFS_POOLS" ] && command -v zpool >/dev/null 2>&1; then
    if [ "$MONITOR_ZFS_POOLS" = "all" ]; then
        pools=$(zpool list -H -o name 2>/dev/null)
    else
        pools="$MONITOR_ZFS_POOLS"
    fi

    for pool in $pools; do
        pool_status=$(zpool status -x "$pool" 2>/dev/null)
        ZFS_CRITICAL=0
        if ! echo "$pool_status" | grep -qiE "healthy|all pools are healthy"; then
            ZFS_CRITICAL=1
        fi
        check_metric "zpool_${pool}" "$pool_status" "healthy" "$ZFS_CRITICAL" "$MSG_MONITOR_ZFS_ALERT" "$MSG_MONITOR_ZFS_OK" "" "" "" "" "$pool"
    done
fi

# --- 5. Check Systemd Services ---
for service in $MONITOR_SERVICES; do
    service_active=1
    systemctl is-active --quiet "$service" || service_active=0
    SERVICE_CRITICAL=0
    [ "$service_active" -eq 0 ] && SERVICE_CRITICAL=1
    check_metric "service_${service}" "$service" "active" "$SERVICE_CRITICAL" "$MSG_MONITOR_SERVICE_ALERT" "$MSG_MONITOR_SERVICE_OK" "" "$service"
done

# --- 6. Check Critical Guest Nodes ---
if [ -n "$MONITOR_CRITICAL_GUESTS" ]; then
    for vmid in $(echo "$MONITOR_CRITICAL_GUESTS" | tr ',' ' '); do
        GUEST_RUNNING=0
        if pct status "$vmid" >/dev/null 2>&1; then
            [ "$(pct status "$vmid" | awk '{print $2}')" = "running" ] && GUEST_RUNNING=1
        elif qm status "$vmid" >/dev/null 2>&1; then
            [ "$(qm status "$vmid" | awk '{print $2}')" = "running" ] && GUEST_RUNNING=1
        fi

        GUEST_CRITICAL=0
        [ "$GUEST_RUNNING" -eq 0 ] && GUEST_CRITICAL=1

        # Resolve friendly name
        GUEST_NAME=$(echo "$GUEST_NAME_MAP" | grep -oE "${vmid}:[^,]+" | cut -d':' -f2 2>/dev/null)
        [ -z "$GUEST_NAME" ] && GUEST_NAME="Guest $vmid"

        check_metric "guest_${vmid}" "$vmid" "running" "$GUEST_CRITICAL" "$MSG_MONITOR_GUEST_ALERT" "$MSG_MONITOR_GUEST_OK" "" "" "$vmid" "$GUEST_NAME"
    done
fi

wait
exit 0
