#!/bin/sh
# =============================================================================
# Proxmox VE Homelab SSH Command Wrapper
# File: /usr/local/bin/homelab_ssh_wrapper.sh
# Restricts incoming SSH commands from OpenWrt to the minimum required subset.
# =============================================================================

# Log attempts to syslog if enabled
logger -t homelab-ssh-wrapper "Received command execution request: $SSH_ORIGINAL_COMMAND"

# --- 1. Match Exact Static Commands ---
case "$SSH_ORIGINAL_COMMAND" in
    "echo OK")
        echo "OK"
        exit 0
        ;;
        
    "echo '===LXC==='; pct list; echo '===VM==='; qm list")
        echo '===LXC==='
        pct list
        echo '===VM==='
        qm list
        exit 0
        ;;
        
    "echo '===METRICS==='; uptime; echo '===RAM==='; free -h; echo '===LXC==='; pct list; echo '===VM==='; qm list")
        echo '===METRICS==='
        uptime
        echo '===RAM==='
        free -h
        echo '===LXC==='
        pct list
        echo '===VM==='
        qm list
        exit 0
        ;;
        
    "pct list | awk 'NR>1 && \$2==\"running\" {print \$1}'; qm list | awk 'NR>1 && \$3==\"running\" {print \$1}'" | \
    "pct list | awk 'NR>1 && $2==\"running\" {print \$1}'; qm list | awk 'NR>1 && $3==\"running\" {print \$1}'")
        pct list | awk 'NR>1 && $2=="running" {print $1}'
        qm list | awk 'NR>1 && $3=="running" {print $1}'
        exit 0
        ;;
        
    "pct list | awk 'NR>1 {print \"• LXC [\" \$1 \"] (\" \$3 \"): \" \$2}'" | \
    "pct list | awk 'NR>1 {print \"• LXC [\" $1 \"] (\" $3 \"): \" $2}'")
        pct list | awk 'NR>1 {print "• LXC [" $1 "] (" $3 "): " $2}'
        exit 0
        ;;
        
    "qm list | awk 'NR>1 {print \"• VM [\" \$1 \"] (\" \$2 \"): \" \$3}'" | \
    "qm list | awk 'NR>1 {print \"• VM [\" $1 \"] (\" $2 \"): \" $3}'")
        qm list | awk 'NR>1 {print "• VM [" $1 "] (" $2 "): " $3}'
        exit 0
        ;;
        
    "nohup /usr/local/bin/proxmox_idle_monitor.sh >/dev/null 2>&1 &")
        nohup /usr/local/bin/proxmox_idle_monitor.sh >/dev/null 2>&1 &
        exit 0
        ;;
        
    "nohup /usr/local/bin/proxmox_idle_monitor.sh --force >/dev/null 2>&1 &")
        nohup /usr/local/bin/proxmox_idle_monitor.sh --force >/dev/null 2>&1 &
        exit 0
        ;;
        
    "nohup /usr/local/bin/proxmox_idle_monitor.sh --shutdown >/dev/null 2>&1 &")
        nohup /usr/local/bin/proxmox_idle_monitor.sh --shutdown >/dev/null 2>&1 &
        exit 0
        ;;
        
    "nohup /usr/local/bin/proxmox_idle_monitor.sh --shutdown --force >/dev/null 2>&1 &")
        nohup /usr/local/bin/proxmox_idle_monitor.sh --shutdown --force >/dev/null 2>&1 &
        exit 0
        ;;
        
    "nohup /usr/local/bin/proxmox_idle_monitor.sh --reboot >/dev/null 2>&1 &")
        nohup /usr/local/bin/proxmox_idle_monitor.sh --reboot >/dev/null 2>&1 &
        exit 0
        ;;
        
    "nohup /usr/local/bin/proxmox_idle_monitor.sh --reboot --force >/dev/null 2>&1 &")
        nohup /usr/local/bin/proxmox_idle_monitor.sh --reboot --force >/dev/null 2>&1 &
        exit 0
        ;;

    "cat > /etc/homelab_power.conf")
        cat > /etc/homelab_power.conf
        exit 0
        ;;

    "systemctl restart proxmox_idle_monitor.timer")
        systemctl restart proxmox_idle_monitor.timer
        exit 0
        ;;

    "cpu=\$(grep 'cpu ' /proc/stat | awk '{usage=(\$2+\$4)*100/(\$2+\$4+\$5)} END {printf \"%.1f\", usage}'); ram=\$(free -m | awk 'NR==2 {printf \"%d:%d\", \$3, \$2}'); temp=\$(for z in /sys/class/thermal/thermal_zone*; do [ -f \"\$z/temp\" ] && read -r t < \"\$z/temp\" && read -r y < \"\$z/type\" && echo \"\$y:\$t\" || true; done | grep -iE 'pkg|cpu|soc' | head -n 1 | cut -d: -f2); [ -z \"\$temp\" ] && temp=\$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null); [ -z \"\$temp\" ] && temp=0; temp=\$((temp/1000)); disk=\$(df -h / | awk 'NR==2 {print \$5}' | tr -d '%'); echo \"\$cpu|\$ram|\$temp|\$disk\"" | \
    "cpu=\$(grep 'cpu ' /proc/stat | awk '{usage=(\$2+\$4)*100/(\$2+\$4+\$5)} END {printf \"%.1f\", usage}'); ram=\$(free -m | awk 'NR==2 {printf \"%d:%d\", \$3, \$2}'); temp=\$(for z in /sys/class/thermal/thermal_zone*; do [ -f \"\$z/temp\" ] && read -r t < \"\$z/temp\" && read -r y < \"\$z/type\" && echo \"\$y:\$t\" || true; done | grep -iE 'pkg|cpu|soc' | head -n 1 | cut -d: -f2); [ -z \"\$temp\" ] && temp=\$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null); [ -z \"\$temp\" ] && temp=0; temp=\$((temp/1000)); disk=\$(df -h / | awk 'NR==2 {print \$5}' | tr -d '%'); echo \"\$cpu|\$ram|\$temp|\$disk\"")
        cpu=$(grep 'cpu ' /proc/stat | awk '{usage=($2+$4)*100/($2+$4+$5)} END {printf "%.1f", usage}')
        ram=$(free -m | awk 'NR==2 {printf "%d:%d", $3, $2}')
        temp=$(for z in /sys/class/thermal/thermal_zone*; do [ -f "$z/temp" ] && read -r t < "$z/temp" && read -r y < "$z/type" && echo "$y:$t" || true; done | grep -iE 'pkg|cpu|soc' | head -n 1 | cut -d: -f2)
        [ -z "$temp" ] && temp=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null)
        [ -z "$temp" ] && temp=0
        temp=$((temp/1000))
        disk=$(df -h / | awk 'NR==2 {print $5}' | tr -d '%')
        echo "$cpu|$ram|$temp|$disk"
        exit 0
        ;;
esac

# --- 2. Match Dynamic Multi-line config and resume command blocks ---
# Check if it starts with "if pct config "
if echo "$SSH_ORIGINAL_COMMAND" | grep -qE "^if pct config [0-9]+ "; then
    VMID=$(echo "$SSH_ORIGINAL_COMMAND" | awk 'NR==1 {print $4}')
    if [ -n "$VMID" ] && echo "$VMID" | grep -qE "^[0-9]+$"; then
        # Ensure the rest of the command matches the expected pattern exactly to prevent parameter injection
        EXPECTED="if pct config $VMID >/dev/null 2>&1; then pct resume $VMID >/dev/null 2>&1 || pct start $VMID >/dev/null 2>&1 elif qm config $VMID >/dev/null 2>&1; then qm resume $VMID >/dev/null 2>&1 || qm start $VMID >/dev/null 2>&1 fi"
        
        # Normalize whitespace in original and expected to compare safely
        ORIG_NORM=$(echo "$SSH_ORIGINAL_COMMAND" | tr -s '[:space:]' ' ')
        EXP_NORM=$(echo "$EXPECTED" | tr -s '[:space:]' ' ')
        
        if [ "$ORIG_NORM" = "$EXP_NORM" ]; then
            # Clear guest idle timer state so it gets a fresh cooldown window on boot
            sed -i "/^${VMID}:/d" /tmp/proxmox_guest_idle_states 2>/dev/null
            if pct config "$VMID" >/dev/null 2>&1; then
                pct resume "$VMID" >/dev/null 2>&1 || pct start "$VMID" >/dev/null 2>&1
            elif qm config "$VMID" >/dev/null 2>&1; then
                qm resume "$VMID" >/dev/null 2>&1 || qm start "$VMID" >/dev/null 2>&1
            fi
            exit 0
        fi
    fi
fi

# --- 3. Match Dynamic Single-Line Commands (3 arguments, e.g. "pct start 101") ---
set -- $SSH_ORIGINAL_COMMAND
if [ $# -eq 3 ]; then
    cmd="$1"
    subcmd="$2"
    vmid="$3"
    
    if echo "$vmid" | grep -qE "^[0-9]+$"; then
        if [ "$cmd" = "pct" ] || [ "$cmd" = "qm" ]; then
            case "$subcmd" in
                config|start|stop|shutdown|reboot|resume)
                    # Clear guest idle timer state on start/resume
                    if [ "$subcmd" = "start" ] || [ "$subcmd" = "resume" ]; then
                        sed -i "/^${vmid}:/d" /tmp/proxmox_guest_idle_states 2>/dev/null
                    fi
                    # Directly execute without eval!
                    "$cmd" "$subcmd" "$vmid"
                    exit 0
                    ;;
            esac
        fi
    fi
fi

# If we get here, the command is blocked
logger -t homelab-ssh-wrapper "BLOCKED unauthorized command: $SSH_ORIGINAL_COMMAND"
echo "Access Denied: Command not permitted by Homelab SSH wrapper." >&2
exit 1
