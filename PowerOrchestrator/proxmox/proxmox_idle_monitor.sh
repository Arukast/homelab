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

# Load configuration if exists
if [ -f "$CONF" ]; then
    source "$CONF"
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

# Ensure log file exists
touch "$LOG_FILE"

# Parse arguments
FORCE_SLEEP=0
if [ "$1" = "--force" ] || [ "$1" = "force" ]; then
    FORCE_SLEEP=1
fi

if [ "$FORCE_SLEEP" -eq 1 ]; then
    log "=== Manual Force Sleep Triggered ==="
else
    log "=== Running Idle Check Cycle ==="
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
                if command -v conntrack >/dev/null 2>&1; then
                    sub_count=$(conntrack -L -d "$GUEST_IP" -p "$sub_proto" --dport "$sub_port_num" 2>/dev/null | grep -c -E "ESTABLISHED|ASSURED")
                else
                    sub_count=$(ss -an | grep -c -E "${GUEST_IP}:${sub_port_num}")
                fi
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
                        if pct status "$VMID" >/dev/null 2>&1; then
                            if [ "$LXC_SUSPEND_METHOD" = "suspend" ]; then
                                log "Suspending LXC [$VMID]..."
                                pct suspend "$VMID"
                            else
                                log "Stopping LXC [$VMID]..."
                                pct stop "$VMID"
                            fi
                        else
                            if [ "$VM_SUSPEND_METHOD" = "suspend" ]; then
                                log "Suspending VM [$VMID]..."
                                qm suspend "$VMID" --todisk 0
                            else
                                log "Shutting down VM [$VMID]..."
                                qm shutdown "$VMID"
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
    
    echo -e "$NEW_STATES" | sed '/^$/d' > "$STATE_FILE"
    
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
# Read 15-minute load average from /proc/loadavg
LOAD_15=$(awk '{print $3}' /proc/loadavg)
log "Current 15-minute CPU load average: $LOAD_15 (Threshold: $CPU_THRESHOLD)"

# Compare float numbers in bash
if (( $(echo "$LOAD_15 > $CPU_THRESHOLD" | bc -l) )); then
    log "BLOCK: CPU load average ($LOAD_15) exceeds threshold ($CPU_THRESHOLD). Host is NOT idle."
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
    # We look for ESTABLISHED connections on the given port
    # Avoid matching local listening sockets or loops
    CONN_COUNT=$(ss -t -an state established | grep -c -E ":$port[[:space:]]")
    if [ "$CONN_COUNT" -gt 0 ]; then
        log "BLOCK: Found $CONN_COUNT active TCP connection(s) on monitored port $port. Host is NOT idle."
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

# Wait for stopped/shutdown nodes to fully power down if needed
if [ -n "$STOPPED_LXCS" ] || [ -n "$SHUTDOWN_VMS" ]; then
    log "Waiting for stopped guest nodes to power off..."
    sleep 5
fi

# 6. Put Proxmox Host to Sleep (ACPI S3 State)
log "Zzz: Suspending Proxmox host to RAM (ACPI S3)..."
sync

# Transition to S3 Suspend
systemctl suspend

# =============================================================================
# === THE HOST IS NOW ASLEEP. EXECUTION STOPS HERE UNTIL SYSTEM WAKES UP. ===
# =============================================================================

# --- WAKE UP SEQUENCE ---
log "⚡ WAKE: Proxmox host has woken up from S3 suspend."

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
