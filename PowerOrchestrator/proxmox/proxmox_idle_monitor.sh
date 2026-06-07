#!/bin/bash
# =============================================================================
# Proxmox VE Idle Monitor & ACPI S3 Suspend Script
# File: /usr/local/bin/proxmox_idle_monitor.sh
# =============================================================================

# Default Config Path
CONF="/etc/homelab_power.conf"

# Default fallback values
CPU_THRESHOLD="0.15"
NET_INTERFACE="vmbr0"
NET_THRESHOLD_KBPS="50"
MONITORED_PORTS="25565,32400,8006,8123,22"
LXC_SUSPEND_METHOD="suspend"
VM_SUSPEND_METHOD="suspend"
PROTECTED_PROCESSES="vzdump qm pct rsync proxmox-backup-client apt-get dpkg"
LOG_FILE="/var/log/proxmox_power.log"
ENABLE_SYSLOG=1

# Default fallback messages (if /etc/homelab_messages.conf is not present)
MSG_PROXMOX_GUEST_SUSPENDED='💤 *Guest Idle Sleep:* Service $GUEST_NAME (VMID $VMID) was idle for $TIMEOUT_MIN minutes and has been successfully suspended to reclaim system resources!'
MSG_PROXMOX_GUEST_STOPPED='🛑 *Guest Idle Sleep:* Service $GUEST_NAME (VMID $VMID) was idle for $TIMEOUT_MIN minutes and has been stopped cleanly to reclaim system resources!'
MSG_PROXMOX_HOST_SLEEPING='😴 *Proxmox Host Sleeping:* Host is entering S3 Suspend-to-RAM. All system states successfully saved!'
MSG_PROXMOX_HOST_AWAKE='⚡ *Proxmox Host Awake:* Host successfully woke up from ACPI S3 sleep. Restoring all guest VMs...'

# Load configuration if exists
if [ -f "$CONF" ]; then
    source "$CONF"
fi

# Load messages configuration if exists
MSG_CONF="/etc/homelab_messages.conf"
if [ -f "$MSG_CONF" ]; then
    source "$MSG_CONF"
fi

# Log helper
log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$msg" >> "$LOG_FILE"
    if [ "$ENABLE_SYSLOG" -eq 1 ]; then
        logger -t "proxmox-idle-monitor" "$1"
    fi
    echo "$msg"
}

# Notification helper
notify() {
    local msg="$1"
    log "NOTIFICATION: $msg"
    
    # Telegram dispatch
    if [ -n "$BOT_TOKEN" ] && [ -n "$ALLOWED_USER_IDS" ]; then
        local target_chats="${NOTIFY_CHAT_ID}"
        [ -z "$target_chats" ] && target_chats=$(echo "$ALLOWED_USER_IDS" | cut -d',' -f1)
        
        for chat in $(echo "$target_chats" | tr ',' ' '); do
            # If notifications are disabled, only notify IDs in ALLOWED_USER_IDS (admin private chats)
            if [ "$DISABLE_NOTIFICATIONS" = "1" ]; then
                local is_allowed=0
                for allowed in $(echo "$ALLOWED_USER_IDS" | tr ',' ' '); do
                    if [ "$chat" = "$allowed" ]; then
                        is_allowed=1
                        break
                    fi
                done
                if [ "$is_allowed" -eq 0 ]; then
                    continue
                fi
            fi
            
            curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
                --data-urlencode "chat_id=${chat}" \
                --data-urlencode "text=🔔 *Power Monitor:* $msg" \
                --data-urlencode "parse_mode=Markdown" >/dev/null &
        done
    fi

    # Discord Webhook dispatch
    if [ "$DISABLE_NOTIFICATIONS" != "1" ] && [ -n "$DISCORD_WEBHOOK_URL" ]; then
        local color=3899126 # Default Cyber Blue
        if echo "$msg" | grep -iqE "awake|online|restored"; then
            color=1095905 # Green
        elif echo "$msg" | grep -iqE "sleep|S3|offline|down|shutdown|suspended|stopped"; then
            color=15680580 # Red
        fi
        
        local clean_msg=$(echo "$msg" | sed 's/"/\\"/g')
        local payload="{\"embeds\":[{\"title\":\"🔔 Power Monitor Notification\",\"description\":\"${clean_msg}\",\"color\":${color},\"footer\":{\"text\":\"Arukast Homelab Portal\"}}]}"
        for url in $(echo "$DISCORD_WEBHOOK_URL" | tr ',' ' '); do
            curl -s -H "Content-Type: application/json" -X POST -d "$payload" "$url" >/dev/null &
        done
    fi
}

# Ensure log file exists
touch "$LOG_FILE"

# Parse arguments
FORCE_SLEEP=0
ACTION="suspend"

for arg in "$@"; do
    case "$arg" in
        --force|force)
            FORCE_SLEEP=1
            ;;
        --shutdown|shutdown)
            ACTION="shutdown"
            ;;
        --reboot|reboot)
            ACTION="reboot"
            ;;
    esac
done

# If the target host action is shutdown or reboot, we MUST stop guests rather than S3-suspending to RAM!
if [ "$ACTION" = "shutdown" ] || [ "$ACTION" = "reboot" ]; then
    log "Host action is $ACTION. Overriding guest suspension methods to safe stop/shutdown..."
    LXC_SUSPEND_METHOD="stop"
    VM_SUSPEND_METHOD="shutdown"
fi

if [ "$FORCE_SLEEP" -eq 1 ]; then
    log "=== Manual Force Action Triggered: $ACTION ==="
else
    log "=== Running Idle Check Cycle for Action: $ACTION ==="
fi

# Run activity and idle checks only if not forced
if [ "$FORCE_SLEEP" -eq 0 ]; then

# 0. Individual Guest Auto-Sleep Check
if [ -n "$GUEST_ORCHESTRATION_MAP" ]; then
    log "Checking individual guest idle states..."
    STATE_FILE="/tmp/proxmox_guest_idle_states"
    touch "$STATE_FILE"
    CURRENT_TIME=$(date +%s)
    
    NEW_STATES=""
    ORCHESTRATED_GUESTS_RUNNING=0
    
    for entry in $(echo "$GUEST_ORCHESTRATION_MAP" | tr ',' ' '); do
        VMID=$(echo "$entry" | cut -d':' -f1)
        GUEST_IP=$(echo "$entry" | cut -d':' -f2)
        PORT_RAW=$(echo "$entry" | cut -d':' -f3)
        TIMEOUT_MIN=$(echo "$entry" | cut -d':' -f4)
        
        GUEST_RUNNING=0
        if pct status "$VMID" >/dev/null 2>&1; then
            if [ "$(pct status "$VMID" | awk '{print $2}')" = "running" ]; then
                GUEST_RUNNING=1
            fi
        elif qm status "$VMID" >/dev/null 2>&1; then
            if [ "$(qm status "$VMID" | awk '{print $2}')" = "running" ]; then
                GUEST_RUNNING=1
            fi
        fi
        
        if [ "$GUEST_RUNNING" -eq 1 ]; then
            ORCHESTRATED_GUESTS_RUNNING=$((ORCHESTRATED_GUESTS_RUNNING + 1))
            CONN_COUNT=0
            
            # Support multiple ports separated by + (e.g. 25565/tcp+19132/udp)
            for sub_port in $(echo "$PORT_RAW" | tr '+' ' '); do
                sub_port_num=$(echo "$sub_port" | cut -d'/' -f1)
                sub_proto=$(echo "$sub_port" | cut -d'/' -f2 -s)
                [ -z "$sub_proto" ] && sub_proto="tcp"
                
                sub_count=0
                # Check based on guest type (LXC vs QEMU VM)
                if pct status "$VMID" >/dev/null 2>&1; then
                    # LXC Container: query network namespace directly
                    sub_count=$(pct exec "$VMID" -- ss -tuan state established 2>/dev/null | grep -c -E ":${sub_port_num}[[:space:]]")
                    if [ $? -ne 0 ] || [ -z "$sub_count" ] || [ "$sub_count" -eq 0 ]; then
                        # Fallback: check /proc/net/tcp and /proc/net/udp inside namespace
                        hex_port=$(printf "%04x" "$sub_port_num")
                        if [ "$sub_proto" = "tcp" ]; then
                            sub_count=$(pct exec "$VMID" -- cat /proc/net/tcp 2>/dev/null | awk -v hp="$hex_port" '$3 ~ ":" hp && $4 == "01"' | wc -l)
                        else
                            sub_count=$(pct exec "$VMID" -- cat /proc/net/udp 2>/dev/null | awk -v hp="$hex_port" '$3 ~ ":" hp && $4 != "00000000:0000"' | wc -l)
                        fi
                    fi
                elif qm status "$VMID" >/dev/null 2>&1; then
                    # QEMU VM
                    # Method A: Check via QEMU Guest Agent (if active)
                    if qm guest cmd "$VMID" ping >/dev/null 2>&1; then
                        guest_out=$(qm guest exec "$VMID" -- ss -tuan state established 2>/dev/null)
                        if [ -n "$guest_out" ]; then
                            b64_data=$(echo "$guest_out" | grep -oE '"out-data"\s*:\s*"[^"]+"' | cut -d'"' -f4)
                            if [ -n "$b64_data" ]; then
                                sub_count=$(echo "$b64_data" | base64 -d 2>/dev/null | grep -c -E ":${sub_port_num}[[:space:]]")
                            fi
                        fi
                    fi
                    
                    # Method B: Fallback to capturing L2 packet flows on VM's virtual tap interface
                    if [ -z "$sub_count" ] || [ "$sub_count" -eq 0 ]; then
                        if [ -d "/sys/class/net/tap${VMID}i0" ]; then
                            if timeout 2 tcpdump -i "tap${VMID}i0" -c 1 -p -n "port ${sub_port_num}" >/dev/null 2>&1; then
                                sub_count=1
                            fi
                        fi
                    fi
                fi
                [ -z "$sub_count" ] && sub_count=0
                CONN_COUNT=$((CONN_COUNT + sub_count))
            done
            
            log "Guest [$VMID] ($GUEST_IP) ports $PORT_RAW active connections: $CONN_COUNT"
            
            if [ "$CONN_COUNT" -eq 0 ]; then
                START_TIME=$(grep -E "^${VMID}:" "$STATE_FILE" | cut -d':' -f2)
                if [ -z "$START_TIME" ]; then
                    log "Guest [$VMID] is idle. Starting idle timer."
                    NEW_STATES="${NEW_STATES}${VMID}:${CURRENT_TIME}
"
                else
                    ELAPSED=$((CURRENT_TIME - START_TIME))
                    TIMEOUT_SEC=$((TIMEOUT_MIN * 60))
                    log "Guest [$VMID] has been idle for $ELAPSED seconds (Timeout: $TIMEOUT_SEC seconds)."
                    
                    if [ "$ELAPSED" -ge "$TIMEOUT_SEC" ]; then
                        log "Guest [$VMID] idle timeout reached. Preparing to suspend/stop..."
                        ORCHESTRATED_GUESTS_RUNNING=$((ORCHESTRATED_GUESTS_RUNNING - 1))
                        
                        # Resolve friendly name for notifications
                        GUEST_NAME=$(echo "$GUEST_NAME_MAP" | grep -oE "${VMID}:[^,]+" | cut -d':' -f2 2>/dev/null)
                        [ -z "$GUEST_NAME" ] && GUEST_NAME="Guest $VMID"
                        TIMEOUT_MIN="$TIMEOUT_MIN"
                        
                        if pct status "$VMID" >/dev/null 2>&1; then
                            if [ "$LXC_SUSPEND_METHOD" = "suspend" ]; then
                                log "Suspending LXC [$VMID]..."
                                pct suspend "$VMID"
                                notify "$(eval echo "\"$MSG_PROXMOX_GUEST_SUSPENDED\"")"
                            else
                                log "Stopping LXC [$VMID]..."
                                pct stop "$VMID"
                                notify "$(eval echo "\"$MSG_PROXMOX_GUEST_STOPPED\"")"
                            fi
                        else
                            if [ "$VM_SUSPEND_METHOD" = "suspend" ]; then
                                log "Suspending VM [$VMID]..."
                                qm suspend "$VMID" --todisk 0
                                notify "$(eval echo "\"$MSG_PROXMOX_GUEST_SUSPENDED\"")"
                            else
                                log "Shutting down VM [$VMID]..."
                                qm shutdown "$VMID"
                                notify "$(eval echo "\"$MSG_PROXMOX_GUEST_STOPPED\"")"
                            fi
                        fi
                    else
                        NEW_STATES="${NEW_STATES}${VMID}:${START_TIME}
"
                    fi
                fi
            else
                log "Guest [$VMID] is active. Resetting idle timer."
            fi
        fi
    done
    
    printf "%s" "$NEW_STATES" | sed '/^$/d' > "$STATE_FILE"
    
    if [ "$ORCHESTRATED_GUESTS_RUNNING" -gt 0 ]; then
        log "BLOCK: Orchestrated guest(s) are still active or waiting for idle timeout. Host is NOT idle."
        exit 0
    fi
fi

# 1. Check Protected Processes
for proc in $PROTECTED_PROCESSES; do
    if pgrep -x "$proc" >/dev/null 2>&1; then
        log "BLOCK: Protected process '$proc' is currently running. Host is NOT idle."
        exit 0
    fi
done

# 2. Check CPU Load Average
# Read 1-minute load average from /proc/loadavg
LOAD_1=$(awk '{print $1}' /proc/loadavg)
log "Current 1-minute CPU load average: $LOAD_1 (Threshold: $CPU_THRESHOLD)"

# Compare float numbers in bash
if (( $(echo "$LOAD_1 > $CPU_THRESHOLD" | bc -l) )); then
    log "BLOCK: CPU load average ($LOAD_1) exceeds threshold ($CPU_THRESHOLD). Host is NOT idle."
    exit 0
fi

# 2.5. Check Network Interface Traffic Rate (Over 10-second window)
if [ -n "$NET_INTERFACE" ] && [ -d "/sys/class/net/$NET_INTERFACE" ]; then
    log "Measuring network throughput on $NET_INTERFACE over 10 seconds..."
    
    RX_BYTES_1=$(cat "/sys/class/net/$NET_INTERFACE/statistics/rx_bytes")
    TX_BYTES_1=$(cat "/sys/class/net/$NET_INTERFACE/statistics/tx_bytes")
    
    sleep 10
    
    RX_BYTES_2=$(cat "/sys/class/net/$NET_INTERFACE/statistics/rx_bytes")
    TX_BYTES_2=$(cat "/sys/class/net/$NET_INTERFACE/statistics/tx_bytes")
    
    RX_DIFF=$((RX_BYTES_2 - RX_BYTES_1))
    TX_DIFF=$((TX_BYTES_2 - TX_BYTES_1))
    
    # Calculate average KB/s
    TOTAL_KB=$(( (RX_DIFF + TX_DIFF) / 1024 ))
    AVERAGE_KBPS=$(echo "scale=2; $TOTAL_KB / 10" | bc -l)
    
    log "Network activity: $AVERAGE_KBPS KB/s (Threshold: ${NET_THRESHOLD_KBPS} KB/s)"
    
    if (( $(echo "$AVERAGE_KBPS > $NET_THRESHOLD_KBPS" | bc -l) )); then
        log "BLOCK: Average network throughput ($AVERAGE_KBPS KB/s) exceeds threshold (${NET_THRESHOLD_KBPS} KB/s). Host is NOT idle."
        exit 0
    fi
else
    log "Skipping network throughput check (Interface $NET_INTERFACE not found or not configured)."
fi

# 3. Check Network Connections on Monitored Ports
for port in $(echo "$MONITORED_PORTS" | tr ',' ' '); do
    port_num=$(echo "$port" | cut -d'/' -f1)
    proto=$(echo "$port" | cut -d'/' -f2 -s)
    [ -z "$proto" ] && proto="tcp"
    
    conn_count=0
    if [ "$proto" = "tcp" ]; then
        # We look for ESTABLISHED TCP connections on the given port
        # Avoid matching local listening sockets or loops
        conn_count=$(ss -t -an state established | grep -c -E ":$port_num[[:space:]]")
    else
        # For UDP, check conntrack if available, else fallback to ss -ua
        if command -v conntrack >/dev/null 2>&1; then
            conn_count=$(conntrack -L -p udp --dport "$port_num" 2>/dev/null | grep -c -E "ESTABLISHED|ASSURED")
        else
            # Native fallback using ss -u -an
            conn_count=$(ss -u -an | grep -c -E ":$port_num[[:space:]]")
        fi
    fi
    
    if [ "$conn_count" -gt 0 ]; then
        log "BLOCK: Found $conn_count active $proto connection(s) on monitored port $port_num. Host is NOT idle."
        exit 0
    fi
done


fi

log "CONFIRM: All idle checks passed. Preparing to transition to power-saving mode."

# 4. Gather active guest nodes
RUNNING_LXCS=$(pct list | awk 'NR>1 && $2=="running" {print $1}')
RUNNING_VMS=$(qm list | awk 'NR>1 && $3=="running" {print $1}')

SUSPENDED_LXCS=""
STOPPED_LXCS=""
SUSPENDED_VMS=""
SHUTDOWN_VMS=""

# 5. Suspend/Shutdown Guest Nodes
# Handle LXC Containers
for vmid in $RUNNING_LXCS; do
    if [ "$LXC_SUSPEND_METHOD" = "suspend" ]; then
        log "LXC [$vmid]: Suspending/Freezing container..."
        if pct suspend "$vmid" >/dev/null 2>&1; then
            SUSPENDED_LXCS="$SUSPENDED_LXCS $vmid"
        else
            log "WARNING: Failed to suspend LXC $vmid. Falling back to stop..."
            pct stop "$vmid"
            STOPPED_LXCS="$STOPPED_LXCS $vmid"
        fi
    elif [ "$LXC_SUSPEND_METHOD" = "stop" ]; then
        log "LXC [$vmid]: Stopping container..."
        pct stop "$vmid"
        STOPPED_LXCS="$STOPPED_LXCS $vmid"
    else
        log "LXC [$vmid]: Leaving running (No action)."
    fi
done

# Handle QEMU VMs
for vmid in $RUNNING_VMS; do
    if [ "$VM_SUSPEND_METHOD" = "suspend" ]; then
        log "VM [$vmid]: Suspending/Freezing VM..."
        if qm suspend "$vmid" --todisk 0 >/dev/null 2>&1; then
            SUSPENDED_VMS="$SUSPENDED_VMS $vmid"
        else
            log "WARNING: Failed to suspend VM $vmid. Falling back to shutdown..."
            qm shutdown "$vmid"
            SHUTDOWN_VMS="$SHUTDOWN_VMS $vmid"
        fi
    elif [ "$VM_SUSPEND_METHOD" = "shutdown" ]; then
        log "VM [$vmid]: Sending ACPI shutdown signal..."
        qm shutdown "$vmid"
        SHUTDOWN_VMS="$SHUTDOWN_VMS $vmid"
    else
        log "VM [$vmid]: Leaving running (No action)."
    fi
done

# Wait for stopped/shutdown nodes to fully power down with timeout
if [ -n "$STOPPED_LXCS" ] || [ -n "$SHUTDOWN_VMS" ]; then
    log "Waiting for guest nodes to power off completely..."
    for i in $(seq 1 12); do
        ACTIVE_COUNT=0
        for vmid in $STOPPED_LXCS $SHUTDOWN_VMS; do
            if qm status "$vmid" >/dev/null 2>&1 && [ "$(qm status "$vmid" | awk '{print $2}')" = "running" ]; then
                ACTIVE_COUNT=$((ACTIVE_COUNT + 1))
            elif pct status "$vmid" >/dev/null 2>&1 && [ "$(pct status "$vmid" | awk '{print $2}')" = "running" ]; then
                ACTIVE_COUNT=$((ACTIVE_COUNT + 1))
            fi
        done
        if [ "$ACTIVE_COUNT" -eq 0 ]; then
            log "All guest nodes stopped cleanly."
            break
        fi
        sleep 5
    done
fi

# 6. Put Proxmox Host to Sleep (ACPI S3 State), Shutdown or Reboot
if [ "$ACTION" = "shutdown" ]; then
    log "Shutdown: Powering off Proxmox host..."
    notify "🛑 *Proxmox Host Shutting Down:* System is powering off cleanly!"
    sync
    sleep 3
    shutdown -h now
    exit 0
elif [ "$ACTION" = "reboot" ]; then
    log "Reboot: Rebooting Proxmox host..."
    notify "🔄 *Proxmox Host Rebooting:* System is rebooting cleanly!"
    sync
    sleep 3
    reboot
    exit 0
else
    log "Zzz: Suspending Proxmox host to RAM (ACPI S3)..."
    sync
    sleep 3
    systemctl suspend
fi

# =============================================================================
# === THE HOST IS NOW ASLEEP. EXECUTION STOPS HERE UNTIL SYSTEM WAKES UP. ===
# =============================================================================

# --- WAKE UP SEQUENCE ---
log "⚡ WAKE: Proxmox host has woken up from S3 suspend."
rm -f /tmp/proxmox_guest_idle_states 2>/dev/null

# 7. Resume Suspended Nodes
# Resume QEMU VMs first (often takes a bit longer to reactivate)
for vmid in $SUSPENDED_VMS; do
    log "VM [$vmid]: Resuming VM from suspended state..."
    qm resume "$vmid" >/dev/null 2>&1
done

# Resume LXC Containers
for vmid in $SUSPENDED_LXCS; do
    log "LXC [$vmid]: Resuming container from frozen state..."
    pct resume "$vmid" >/dev/null 2>&1
done

# Start stopped/shutdown nodes that are flagged for 'onboot: 1'
# Proxmox does not run boot sequence on S3 wake, so we manually start them
# if they are set to start at boot and were stopped by this script
for vmid in $STOPPED_LXCS; do
    ONBOOT=$(pct config "$vmid" | grep -E "^onboot:[[:space:]]*1" -c)
    if [ "$ONBOOT" -gt 0 ]; then
        log "LXC [$vmid]: Restarting container (onboot enabled)..."
        pct start "$vmid" >/dev/null 2>&1
    fi
done

for vmid in $SHUTDOWN_VMS; do
    ONBOOT=$(qm config "$vmid" | grep -E "^onboot:[[:space:]]*1" -c)
    if [ "$ONBOOT" -gt 0 ]; then
        log "VM [$vmid]: Restarting VM (onboot enabled)..."
        qm start "$vmid" >/dev/null 2>&1
    fi
done

log "⚡ WAKE: All guest nodes successfully restored. Power-saving cycle complete."
exit 0
