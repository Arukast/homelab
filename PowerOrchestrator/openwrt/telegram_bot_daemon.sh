#!/bin/sh
# =============================================================================
# OpenWrt Shell Telegram Bot Daemon for Homelab Power Control
# File: /usr/bin/telegram_bot_daemon.sh
# =============================================================================

CONF="/etc/homelab_power.conf"
if [ ! -f "$CONF" ]; then
    echo "ERROR: Configuration file $CONF not found." >&2
    exit 1
fi

PIDFILE="/var/run/telegram_bot_daemon.pid"
if [ -f "$PIDFILE" ]; then
    PID=$(cat "$PIDFILE" 2>/dev/null)
    if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
        echo "ERROR: telegram_bot_daemon.sh is already running with PID $PID." >&2
        exit 1
    fi
fi
echo "$$" > "$PIDFILE"

cleanup_pid() {
    rm -f "$PIDFILE"
    exit 0
}
trap cleanup_pid SIGTERM SIGINT EXIT

# Load config
. "$CONF"

# Load messages config
MSG_CONF="/etc/homelab_messages.conf"
if [ -f "$MSG_CONF" ]; then
    . "$MSG_CONF"
fi

# Check token
if [ -z "$BOT_TOKEN" ] || [ "$BOT_TOKEN" = "YOUR_TELEGRAM_BOT_TOKEN" ]; then
    echo "ERROR: BOT_TOKEN is not configured in $CONF" >&2
    exit 1
fi

HOST_SSH_PORT="${HOST_SSH_PORT:-${SSH_PORT:-22}}"
HOST_SSH_USER="${HOST_SSH_USER:-root}"
SSH_CMD="ssh -p $HOST_SSH_PORT -i $SSH_KEY_PATH -y -K 3 ${HOST_SSH_USER}@$HOST_IP"

# Multi-stage Host Liveness Probe (ICMP ping + Dropbear SSH + WebUI curl fallback)
is_host_alive() {
    if ping -c 1 -W 1 "$HOST_IP" >/dev/null 2>&1; then
        return 0
    fi
    if $SSH_CMD "echo OK" >/dev/null 2>&1; then
        return 0
    fi
    if command -v curl >/dev/null 2>&1; then
        if curl -k -s --connect-timeout 1 "https://${HOST_IP}:8006" >/dev/null 2>&1 || \
           curl -s --connect-timeout 1 "http://${HOST_IP}:80" >/dev/null 2>&1; then
            return 0
        fi
    fi
    return 1
}

# Helper to dynamically evaluate/expand strings containing variables
expand_msg() {
    local raw_msg="$1"
    eval echo "\"$raw_msg\""
}

# Helper to send messages to Telegram with Markdown auto-fallback
send_message() {
    local chat_id="$1"
    local text="$2"
    local markup="$3"
    local resp=""
    
    if [ -n "$markup" ]; then
        resp=$(curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
            --data-urlencode "chat_id=${chat_id}" \
            --data-urlencode "text=${text}" \
            --data-urlencode "parse_mode=Markdown" \
            --data-urlencode "reply_markup=${markup}")
        # If Markdown failed (e.g. error 400), retry without Markdown formatting as plain text
        if ! echo "$resp" | grep -q '"ok":true'; then
            curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
                --data-urlencode "chat_id=${chat_id}" \
                --data-urlencode "text=${text}" \
                --data-urlencode "reply_markup=${markup}" >/dev/null
        fi
    else
        resp=$(curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
            --data-urlencode "chat_id=${chat_id}" \
            --data-urlencode "text=${text}" \
            --data-urlencode "parse_mode=Markdown")
        # If Markdown failed, retry without Markdown formatting as plain text
        if ! echo "$resp" | grep -q '"ok":true'; then
            curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
                --data-urlencode "chat_id=${chat_id}" \
                --data-urlencode "text=${text}" >/dev/null
        fi
    fi
}

edit_message_text() {
    local chat_id="$1"
    local message_id="$2"
    local text="$3"
    local markup="$4"
    local resp=""

    if [ -z "$message_id" ]; then
        send_message "$chat_id" "$text" "$markup"
        return
    fi

    if [ -n "$markup" ]; then
        resp=$(curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/editMessageText" \
            --data-urlencode "chat_id=${chat_id}" \
            --data-urlencode "message_id=${message_id}" \
            --data-urlencode "text=${text}" \
            --data-urlencode "parse_mode=Markdown" \
            --data-urlencode "reply_markup=${markup}")
        if ! echo "$resp" | grep -q '"ok":true'; then
            curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/editMessageText" \
                --data-urlencode "chat_id=${chat_id}" \
                --data-urlencode "message_id=${message_id}" \
                --data-urlencode "text=${text}" \
                --data-urlencode "reply_markup=${markup}" >/dev/null
        fi
    else
        resp=$(curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/editMessageText" \
            --data-urlencode "chat_id=${chat_id}" \
            --data-urlencode "message_id=${message_id}" \
            --data-urlencode "text=${text}" \
            --data-urlencode "parse_mode=Markdown")
        if ! echo "$resp" | grep -q '"ok":true'; then
            curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/editMessageText" \
                --data-urlencode "chat_id=${chat_id}" \
                --data-urlencode "message_id=${message_id}" \
                --data-urlencode "text=${text}" >/dev/null
        fi
    fi
}

# Main Command Processor
process_command() {
    local cmd="$1"
    local chat_id="$2"
    
    # Extract action and arguments
    local action_raw=$(echo "$cmd" | awk '{print $1}')
    # Strip bot username suffix if present (e.g., /status@MyBot -> /status)
    local action=$(echo "$action_raw" | cut -d'@' -f1 | tr 'A-Z' 'a-z')
    local arg1=$(echo "$cmd" | awk '{print $2}')
    
    case "$action" in
        /start|/help)
            local markup='{"inline_keyboard":[
                [{"text":"📊 Status","callback_data":"action:status"},{"text":"📋 List Nodes","callback_data":"action:list_nodes"}],
                [{"text":"⚡ Host Power","callback_data":"action:host_power_menu"},{"text":"🛠️ Maintenance","callback_data":"action:maintenance_menu"}]
            ]}'
            send_message "$chat_id" "$MSG_BOT_HELP" "$markup"
            ;;
            
        /status)
            send_message "$chat_id" "$MSG_BOT_QUERY_STATUS"
            
            if ! is_host_alive; then
                local markup='{"inline_keyboard":[
                    [{"text":"Wake Host","callback_data":"/wake"},{"text":"Refresh","callback_data":"/status"}]
                ]}'
                send_message "$chat_id" "$(expand_msg "$MSG_BOT_HOST_SLEEPING")" "$markup"
                return
            fi
            
            # Host is online, gather all metrics in a single SSH connection payload!
            local metrics_payload=$($SSH_CMD "echo '===METRICS==='; uptime; echo '===RAM==='; free -h; echo '===LXC==='; pct list; echo '===VM==='; qm list" 2>/dev/null)
            if [ $? -ne 0 ] || [ -z "$metrics_payload" ]; then
                send_message "$chat_id" "$MSG_BOT_SSH_FAILED"
                return
            fi
            
            local load_avg=$(echo "$metrics_payload" | awk '/===METRICS===/{getline; print}' | awk -F'load average:' '{print $2}' | sed 's/^[[:space:]]*//')
            local ram_info=$(echo "$metrics_payload" | awk '/===RAM===/{getline; getline; print $3 " / " $2}')
            
            # Nodes summary
            local lxc_count=$(echo "$metrics_payload" | awk '/===LXC===/{flag=1; next} /===VM===/{flag=0} flag' | awk 'NR>1' | wc -l)
            local lxc_running=$(echo "$metrics_payload" | awk '/===LXC===/{flag=1; next} /===VM===/{flag=0} flag' | awk 'NR>1 && $2=="running"' | wc -l)
            local vm_count=$(echo "$metrics_payload" | awk '/===VM===/{flag=1; next} flag' | awk 'NR>1' | wc -l)
            local vm_running=$(echo "$metrics_payload" | awk '/===VM===/{flag=1; next} flag' | awk 'NR>1 && $3=="running"' | wc -l)
            
            local status_msg="*Host Status:* ONLINE
*Load Average:* ${load_avg}
*RAM Usage:* ${ram_info}

*Guest Nodes:*
• LXC Containers: ${lxc_running}/${lxc_count} running
• QEMU VMs: ${vm_running}/${vm_count} running"
 
            local markup='{"inline_keyboard":[
                [{"text":"List VMs","callback_data":"/list"},{"text":"Sleep (Safe)","callback_data":"/sleep"}],
                [{"text":"Refresh","callback_data":"/status"}]
            ]}'
            send_message "$chat_id" "$status_msg" "$markup"
            ;;
            
        /wake)
            send_message "$chat_id" "$(expand_msg "$MSG_BOT_WOL_SENT")"
            etherwake -i "${LAN_INTERFACE:-br-lan}" "$HOST_MAC"
            send_message "$chat_id" "$MSG_BOT_WOL_DISPATCHED"
            ;;
            
        /sleep)
            if ! is_host_alive; then
                send_message "$chat_id" "$MSG_BOT_SLEEP_ALREADY_OFFLINE"
                return
            fi
            
            send_message "$chat_id" "$MSG_BOT_SLEEP_TRIGGERED"
            echo "SLEEP" > /tmp/homelab_target_state
            # Run the idle monitor script on Proxmox in background WITHOUT --force (evaluates idle criteria)
            $SSH_CMD "nohup /usr/local/bin/proxmox_idle_monitor.sh >/dev/null 2>&1 &" 2>/dev/null
            send_message "$chat_id" "$MSG_BOT_SLEEP_EXECUTED"
            ;;
            
        /sleepforce)
            if ! is_host_alive; then
                send_message "$chat_id" "$MSG_BOT_SLEEP_ALREADY_OFFLINE"
                return
            fi
            
            send_message "$chat_id" "$MSG_BOT_SLEEP_FORCE_TRIGGERED"
            echo "SLEEP" > /tmp/homelab_target_state
            # Run the idle monitor script on Proxmox in background WITH --force so it suspends immediately
            $SSH_CMD "nohup /usr/local/bin/proxmox_idle_monitor.sh --force >/dev/null 2>&1 &" 2>/dev/null
            send_message "$chat_id" "$MSG_BOT_SLEEP_EXECUTED"
            ;;
            
        /hostshutdown)
            if ! is_host_alive; then
                send_message "$chat_id" "$MSG_BOT_SHUTDOWN_ALREADY_OFFLINE"
                return
            fi
            
            # Safe check: block if there are running VMs or containers (excluding exempt guests)
            local running_guests=$($SSH_CMD "pct list | awk 'NR>1 && \$2==\"running\" {print \$1}'; qm list | awk 'NR>1 && \$3==\"running\" {print \$1}'" 2>/dev/null)
            local blocking_guests=""
            
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
            
            if [ -n "$blocking_guests" ]; then
                local clean_blocking=$(echo "$blocking_guests" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
                send_message "$chat_id" "*Shutdown Blocked:* Core power actions are blocked because active non-exempt guest(s) are running: *${clean_blocking}*.

Please stop them first, or use \`/hostshutdownforce\`."
                return
            fi
            
            send_message "$chat_id" "$MSG_BOT_SHUTDOWN_SENDING"
            echo "SHUTDOWN" > /tmp/homelab_target_state
            # Run the idle monitor script on Proxmox in background with --shutdown (respects other idle checks)
            $SSH_CMD "nohup /usr/local/bin/proxmox_idle_monitor.sh --shutdown >/dev/null 2>&1 &" 2>/dev/null
            send_message "$chat_id" "$MSG_BOT_SHUTDOWN_EXECUTED"
            ;;
            
        /hostshutdownforce)
            if ! is_host_alive; then
                send_message "$chat_id" "$MSG_BOT_SHUTDOWN_ALREADY_OFFLINE"
                return
            fi
            send_message "$chat_id" "$MSG_BOT_SHUTDOWN_FORCE_SENDING"
            echo "SHUTDOWN" > /tmp/homelab_target_state
            # Run the idle monitor script on Proxmox in background with --shutdown --force (bypasses checks, suspends/stops guests cleanly)
            $SSH_CMD "nohup /usr/local/bin/proxmox_idle_monitor.sh --shutdown --force >/dev/null 2>&1 &" 2>/dev/null
            send_message "$chat_id" "$MSG_BOT_SHUTDOWN_EXECUTED"
            ;;
            
        /hostreboot)
            if ! is_host_alive; then
                send_message "$chat_id" "$MSG_BOT_REBOOT_ALREADY_OFFLINE"
                return
            fi
            
            # Safe check: block if there are running VMs or containers (excluding exempt guests)
            local running_guests=$($SSH_CMD "pct list | awk 'NR>1 && \$2==\"running\" {print \$1}'; qm list | awk 'NR>1 && \$3==\"running\" {print \$1}'" 2>/dev/null)
            local blocking_guests=""
            
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
            
            if [ -n "$blocking_guests" ]; then
                local clean_blocking=$(echo "$blocking_guests" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
                send_message "$chat_id" "*Reboot Blocked:* Core power actions are blocked because active non-exempt guest(s) are running: *${clean_blocking}*.

Please stop them first, or use \`/hostrebootforce\`."
                return
            fi
            
            send_message "$chat_id" "$MSG_BOT_REBOOT_SENDING"
            echo "REBOOT" > /tmp/homelab_target_state
            # Run the idle monitor script on Proxmox in background with --reboot (respects other idle checks)
            $SSH_CMD "nohup /usr/local/bin/proxmox_idle_monitor.sh --reboot >/dev/null 2>&1 &" 2>/dev/null
            send_message "$chat_id" "$MSG_BOT_REBOOT_EXECUTED"
            ;;
            
        /hostrebootforce)
            if ! is_host_alive; then
                send_message "$chat_id" "$MSG_BOT_REBOOT_ALREADY_OFFLINE"
                return
            fi
            send_message "$chat_id" "$MSG_BOT_REBOOT_FORCE_SENDING"
            echo "REBOOT" > /tmp/homelab_target_state
            # Run the idle monitor script on Proxmox in background with --reboot --force (bypasses checks, suspends/stops guests cleanly)
            $SSH_CMD "nohup /usr/local/bin/proxmox_idle_monitor.sh --reboot --force >/dev/null 2>&1 &" 2>/dev/null
            send_message "$chat_id" "$MSG_BOT_REBOOT_EXECUTED"
            ;;
            
        /list)
            if ! is_host_alive; then
                send_message "$chat_id" "$MSG_BOT_LIST_HOST_OFFLINE"
                return
            fi
            
            local payload=$($SSH_CMD "echo '===LXC==='; pct list; echo '===VM==='; qm list" 2>/dev/null)
            if [ $? -ne 0 ] || [ -z "$payload" ]; then
                send_message "$chat_id" "$MSG_BOT_SSH_FAILED"
                return
            fi
            
            local lxcs=$(echo "$payload" | awk '
                /===LXC===/{flag=1; next}
                /===VM===/{flag=0}
                flag && NR>2 && $1 != "VMID" {
                    print "• LXC #" $1 " (" $3 "): " $2
                }
            ')
            local vms=$(echo "$payload" | awk '
                /===VM===/{flag=1; next}
                flag && NR>2 && $1 != "VMID" {
                    print "• VM #" $1 " (" $2 "): " $3
                }
            ')
            
            [ -z "$lxcs" ] && lxcs="None configured."
            [ -z "$vms" ] && vms="None configured."
            
            local list_msg="*Proxmox Guest Nodes:*
 
*Containers:*
${lxcs}
 
*Virtual Machines:*
${vms}"
            
            local lxc_buttons=$(echo "$payload" | awk '
                /===LXC===/{flag=1; next}
                /===VM===/{flag=0}
                flag && NR>2 && $1 != "VMID" && $1 != "" {
                    vmid = $1; status = $2; name = $3;
                    btn_text = (status == "running" ? "Stop " name : "Start " name);
                    cmd = (status == "running" ? "/ctstop " vmid : "/ctstart " vmid);
                    printf "[{\"text\":\"%s\",\"callback_data\":\"%s\"}]", btn_text, cmd
                }
            ' | paste -sd, -)
            
            local vm_buttons=$(echo "$payload" | awk '
                /===VM===/{flag=1; next}
                flag && NR>2 && $1 != "VMID" && $1 != "" {
                    vmid = $1; name = $2; status = $3;
                    btn_text = (status == "running" ? "Stop " name : "Start " name);
                    cmd = (status == "running" ? "/vmstop " vmid : "/vmstart " vmid);
                    printf "[{\"text\":\"%s\",\"callback_data\":\"%s\"}]", btn_text, cmd
                }
            ' | paste -sd, -)
            
            local all_buttons=""
            if [ -n "$lxc_buttons" ] && [ -n "$vm_buttons" ]; then
                all_buttons="${lxc_buttons},${vm_buttons}"
            elif [ -n "$lxc_buttons" ]; then
                all_buttons="$lxc_buttons"
            else
                all_buttons="$vm_buttons"
            fi
            
            local markup=""
            if [ -n "$all_buttons" ]; then
                all_buttons="${all_buttons},[{\"text\":\"Refresh List\",\"callback_data\":\"/list\"}]"
                markup="{\"inline_keyboard\":[$all_buttons]}"
            fi
            
            send_message "$chat_id" "$list_msg" "$markup"
            ;;
            
        /ctstart)
            if [ -z "$arg1" ]; then
                send_message "$chat_id" "[Usage] /ctstart <vmid>"
                return
            fi
            
            if ! echo "$arg1" | grep -qE "^[0-9]+$"; then
                send_message "$chat_id" "Error: VMID must be numeric."
                return
            fi
            
            # We run the entire waking & starting sequence in the background to prevent daemon blocking
            (
                # Check if host is offline, if so wake it first
                if ! is_host_alive; then
                    send_message "$chat_id" "Host is Offline: Dispatching Wake-on-LAN magic packet to wake Proxmox first..."
                    etherwake -i "${LAN_INTERFACE:-br-lan}" "$HOST_MAC"
                    
                    # Wait for host to come online and respond to SSH
                    send_message "$chat_id" "Waiting for Proxmox host to boot and respond to SSH (typically 30-45 seconds)..."
                    
                    local success=0
                    local attempt=1
                    while [ $attempt -le 25 ]; do
                        if is_host_alive; then
                            if $SSH_CMD "echo OK" >/dev/null 2>&1; then
                                success=1
                                break
                            fi
                        fi
                        sleep 3
                        attempt=$((attempt + 1))
                    done
                    
                    if [ $success -eq 0 ]; then
                        send_message "$chat_id" "Timeout: Proxmox host did not respond to SSH in time. Please check physical status."
                        return
                    fi
                    
                    send_message "$chat_id" "Host Online: Proxmox host is awake! Proceeding to boot LXC container..."
                fi
                
                send_message "$chat_id" "$(expand_msg "$MSG_BOT_CT_START_STARTING")"
                # Check LXC status directly
                if ! $SSH_CMD "pct status $arg1" >/dev/null 2>&1; then
                    send_message "$chat_id" "[Error] LXC container ID $arg1 not found on Proxmox. (If this is a VM, use /vmstart $arg1)"
                    return
                fi
                
                local start_out
                start_out=$($SSH_CMD "pct start $arg1" 2>&1)
                local ret=$?
                local clean_out=$(echo "$start_out" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
                if [ $ret -ne 0 ]; then
                    send_message "$chat_id" "[Error] Failed to start LXC ID $arg1:
\`\`\`
${clean_out:-Command failed with exit code $ret}
\`\`\`"
                else
                    send_message "$chat_id" "$(expand_msg "$MSG_BOT_CT_START_SUCCESS")
\`\`\`
${clean_out:-Started successfully}
\`\`\`"
                fi
            ) >/dev/null 2>&1 </dev/null &
            ;;
            
        /ctstop)
            if [ -z "$arg1" ]; then
                send_message "$chat_id" "$MSG_BOT_CT_STOP_USAGE"
                return
            fi
            
            if ! echo "$arg1" | grep -qE "^[0-9]+$"; then
                send_message "$chat_id" "Error: VMID must be numeric."
                return
            fi
            
            if ! is_host_alive; then
                send_message "$chat_id" "$MSG_BOT_CT_STOP_HOST_OFFLINE"
                return
            fi
            
            send_message "$chat_id" "$(expand_msg "$MSG_BOT_CT_STOP_STOPPING")"
            if ! $SSH_CMD "pct status $arg1" >/dev/null 2>&1; then
                send_message "$chat_id" "[Error] LXC container ID $arg1 not found on Proxmox. (If this is a VM, use /vmstop $arg1)"
                return
            fi
            
            local stop_out
            stop_out=$($SSH_CMD "pct stop $arg1" 2>&1)
            local ret=$?
            local clean_stop=$(echo "$stop_out" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
            if [ $ret -ne 0 ]; then
                send_message "$chat_id" "[Error] Failed to stop LXC ID $arg1:
\`\`\`
${clean_stop:-Command failed with exit code $ret}
\`\`\`"
            else
                send_message "$chat_id" "$(expand_msg "$MSG_BOT_CT_STOP_SUCCESS")
\`\`\`
${clean_stop:-Stop signal dispatched}
\`\`\`"
            fi
            ;;
            
        /ctrestart)
            if [ -z "$arg1" ]; then
                send_message "$chat_id" "$MSG_BOT_CT_RESTART_USAGE"
                return
            fi
            
            if ! echo "$arg1" | grep -qE "^[0-9]+$"; then
                send_message "$chat_id" "Error: VMID must be numeric."
                return
            fi
            
            if ! is_host_alive; then
                send_message "$chat_id" "$MSG_BOT_CT_RESTART_HOST_OFFLINE"
                return
            fi
            
            send_message "$chat_id" "$(expand_msg "$MSG_BOT_CT_RESTART_RESTARTING")"
            if ! $SSH_CMD "pct status $arg1" >/dev/null 2>&1; then
                send_message "$chat_id" "[Error] LXC container ID $arg1 not found on Proxmox. (If this is a VM, use /vmrestart $arg1)"
                return
            fi
            
            local res_out
            res_out=$($SSH_CMD "pct reboot $arg1" 2>&1)
            local ret=$?
            local clean_res=$(echo "$res_out" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
            if [ $ret -ne 0 ]; then
                send_message "$chat_id" "[Error] Failed to restart LXC ID $arg1:
\`\`\`
${clean_res:-Command failed with exit code $ret}
\`\`\`"
            else
                send_message "$chat_id" "$(expand_msg "$MSG_BOT_CT_RESTART_SUCCESS")
\`\`\`
${clean_res:-Restart signal dispatched}
\`\`\`"
            fi
            ;;

        /vmstart)
            if [ -z "$arg1" ]; then
                send_message "$chat_id" "[Usage] /vmstart <vmid>"
                return
            fi
            
            if ! echo "$arg1" | grep -qE "^[0-9]+$"; then
                send_message "$chat_id" "Error: VMID must be numeric."
                return
            fi
            
            # We run the entire waking & starting sequence in the background to prevent daemon blocking
            (
                # Check if host is offline, if so wake it first
                if ! is_host_alive; then
                    send_message "$chat_id" "Host is Offline: Dispatching Wake-on-LAN magic packet to wake Proxmox first..."
                    etherwake -i "${LAN_INTERFACE:-br-lan}" "$HOST_MAC"
                    
                    # Wait for host to come online and respond to SSH
                    send_message "$chat_id" "Waiting for Proxmox host to boot and respond to SSH (typically 30-45 seconds)..."
                    
                    local success=0
                    local attempt=1
                    while [ $attempt -le 25 ]; do
                        if is_host_alive; then
                            if $SSH_CMD "echo OK" >/dev/null 2>&1; then
                                success=1
                                break
                            fi
                        fi
                        sleep 3
                        attempt=$((attempt + 1))
                    done
                    
                    if [ $success -eq 0 ]; then
                        send_message "$chat_id" "Timeout: Proxmox host did not respond to SSH in time. Please check physical status."
                        return
                    fi
                    
                    send_message "$chat_id" "Host Online: Proxmox host is awake! Proceeding to boot Virtual Machine..."
                fi
                
                send_message "$chat_id" "[Start] Starting Virtual Machine $arg1..."
                if ! $SSH_CMD "qm status $arg1" >/dev/null 2>&1; then
                    send_message "$chat_id" "[Error] Virtual Machine ID $arg1 not found on Proxmox. (If this is an LXC, use /ctstart $arg1)"
                    return
                fi
                
                local start_out
                start_out=$($SSH_CMD "qm start $arg1" 2>&1)
                local ret=$?
                local clean_out=$(echo "$start_out" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
                if [ $ret -ne 0 ]; then
                    send_message "$chat_id" "[Error] Failed to start VM ID $arg1:
\`\`\`
${clean_out:-Command failed with exit code $ret}
\`\`\`"
                else
                    # Filter benign PCI reset and TPM state warnings on successful start
                    local display_out=$(echo "$clean_out" | grep -vE "failed to reset PCI device|error writing '1' to '/sys/bus/pci/devices/.*reset'|swtpm_setup:" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
                    send_message "$chat_id" "[Success] VM $arg1 start response:
\`\`\`
${display_out:-Started successfully}
\`\`\`"
                fi
            ) >/dev/null 2>&1 </dev/null &
            ;;

        /vmstop)
            if [ -z "$arg1" ]; then
                send_message "$chat_id" "[Usage] /vmstop <vmid>"
                return
            fi
            
            if ! echo "$arg1" | grep -qE "^[0-9]+$"; then
                send_message "$chat_id" "Error: VMID must be numeric."
                return
            fi
            
            if ! is_host_alive; then
                send_message "$chat_id" "$MSG_BOT_CT_STOP_HOST_OFFLINE"
                return
            fi
            
            send_message "$chat_id" "[Stop] Sending ACPI shutdown signal to Virtual Machine $arg1..."
            if ! $SSH_CMD "qm status $arg1" >/dev/null 2>&1; then
                send_message "$chat_id" "[Error] Virtual Machine ID $arg1 not found on Proxmox. (If this is an LXC, use /ctstop $arg1)"
                return
            fi
            
            local stop_out
            stop_out=$($SSH_CMD "qm shutdown $arg1" 2>&1)
            local ret=$?
            local clean_stop=$(echo "$stop_out" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
            if [ $ret -ne 0 ]; then
                send_message "$chat_id" "[Error] Failed to stop VM ID $arg1:
\`\`\`
${clean_stop:-Command failed with exit code $ret}
\`\`\`"
            else
                send_message "$chat_id" "[Success] VM $arg1 stop response:
\`\`\`
${clean_stop:-Shutdown signal dispatched}
\`\`\`"
            fi
            ;;

        /vmrestart)
            if [ -z "$arg1" ]; then
                send_message "$chat_id" "[Usage] /vmrestart <vmid>"
                return
            fi
            
            if ! echo "$arg1" | grep -qE "^[0-9]+$"; then
                send_message "$chat_id" "Error: VMID must be numeric."
                return
            fi
            
            if ! is_host_alive; then
                send_message "$chat_id" "$MSG_BOT_CT_RESTART_HOST_OFFLINE"
                return
            fi
            
            send_message "$chat_id" "[Restart] Sending reboot signal to Virtual Machine $arg1..."
            if ! $SSH_CMD "qm status $arg1" >/dev/null 2>&1; then
                send_message "$chat_id" "[Error] Virtual Machine ID $arg1 not found on Proxmox. (If this is an LXC, use /ctrestart $arg1)"
                return
            fi
            
            local res_out
            res_out=$($SSH_CMD "qm reboot $arg1" 2>&1)
            local ret=$?
            local clean_res=$(echo "$res_out" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
            if [ $ret -ne 0 ]; then
                send_message "$chat_id" "[Error] Failed to restart VM ID $arg1:
\`\`\`
${clean_res:-Command failed with exit code $ret}
\`\`\`"
            else
                send_message "$chat_id" "[Success] VM $arg1 restart response:
\`\`\`
${clean_res:-Reboot signal dispatched}
\`\`\`"
            fi
            ;;
            
        /maintenance)
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
            ;;
            
        *)
            send_message "$chat_id" "$MSG_BOT_UNKNOWN_COMMAND"
            ;;
    esac
}

# Main polling loop
OFFSET=0
echo "Starting Homelab Telegram Bot Daemon..."

# Clear any active webhook so long polling functions reliably
curl -s "https://api.telegram.org/bot${BOT_TOKEN}/deleteWebhook" >/dev/null 2>&1

while true; do
    # Long polling with a 30s timeout
    UPDATES=$(curl -s --max-time 35 "https://api.telegram.org/bot${BOT_TOKEN}/getUpdates?offset=${OFFSET}&timeout=30")
    
    if [ $? -ne 0 ] || [ -z "$UPDATES" ]; then
        sleep 5
        continue
    fi
    
    # Check if OK
    OK=$(echo "$UPDATES" | jsonfilter -e '@.ok')
    if [ "$OK" != "true" ]; then
        echo "Telegram API Error response: $UPDATES"
        sleep 10
        continue
    fi
    
    # Get total count of updates
    RAW_IDS=$(echo "$UPDATES" | jsonfilter -e '@.result[*].update_id' 2>/dev/null)
    if [ -z "$RAW_IDS" ]; then
        continue
    fi
    COUNT=$(echo "$RAW_IDS" | grep -c .)
    if [ "$COUNT" -eq 0 ]; then
        continue
    fi
    
    i=0
    while [ $i -lt $COUNT ]; do
        UPDATE_ID=$(echo "$UPDATES" | jsonfilter -e "@.result[$i].update_id")
        
        # Try to parse normal message
        USER_ID=$(echo "$UPDATES" | jsonfilter -e "@.result[$i].message.from.id")
        CHAT_ID=$(echo "$UPDATES" | jsonfilter -e "@.result[$i].message.chat.id")
        CMD_TEXT=$(echo "$UPDATES" | jsonfilter -e "@.result[$i].message.text")
        MESSAGE_ID=$(echo "$UPDATES" | jsonfilter -e "@.result[$i].message.message_id")
        CALLBACK_ID=$(echo "$UPDATES" | jsonfilter -e "@.result[$i].callback_query.id")

        # Fall back to callback query values if present
        if [ -n "$CALLBACK_ID" ]; then
            USER_ID=$(echo "$UPDATES" | jsonfilter -e "@.result[$i].callback_query.from.id")
            CHAT_ID=$(echo "$UPDATES" | jsonfilter -e "@.result[$i].callback_query.message.chat.id")
            CMD_TEXT=$(echo "$UPDATES" | jsonfilter -e "@.result[$i].callback_query.data")
            MESSAGE_ID=$(echo "$UPDATES" | jsonfilter -e "@.result[$i].callback_query.message.message_id")
        fi
        
        # Advance offset to acknowledge this update safely (preventing empty string shell errors)
        if [ -n "$UPDATE_ID" ] && echo "$UPDATE_ID" | grep -qE "^[0-9]+$"; then
            OFFSET=$((UPDATE_ID + 1))
        fi
        
        if [ -n "$CMD_TEXT" ] && [ -n "$USER_ID" ]; then
            # In groups, ignore standard conversation. Only react to slash commands.
            IS_COMMAND=0
            if echo "$CMD_TEXT" | grep -qE "^/"; then
                IS_COMMAND=1
            fi
            
            if [ "$IS_COMMAND" -eq 1 ] || [ "$CHAT_ID" = "$USER_ID" ]; then
                # Verify if user is allowed
                AUTHORIZED=0
                for allowed in $(echo "$ALLOWED_USER_IDS" | tr ',' ' '); do
                    if [ "$allowed" = "$USER_ID" ]; then
                        AUTHORIZED=1
                        break
                    fi
                done
                
                if [ $AUTHORIZED -eq 0 ]; then
                    # Only reply to unauthorized messages if they were actual commands (starts with '/')
                    if echo "$CMD_TEXT" | grep -qE "^/"; then
                        echo "Blocked unauthorized user ID: $USER_ID attempting command: $CMD_TEXT"
                        send_message "$CHAT_ID" "$(expand_msg "$MSG_BOT_UNAUTHORIZED")"
                    fi
                else
                    # Execute commands starting with a slash
                    if echo "$CMD_TEXT" | grep -qE "^/"; then
                        echo "Running command: $CMD_TEXT from authorized User ID: $USER_ID"
                        process_command "$CMD_TEXT" "$CHAT_ID"
                    elif [ "$CHAT_ID" = "$USER_ID" ]; then
                        # In private chat, if authorized user sends plain text (e.g. 'status', 'help', 'hi'), show command menu or execute match
                        echo "Received non-slash message '$CMD_TEXT' from authorized User ID: $USER_ID. Replying with command menu."
                        case "$(echo "$CMD_TEXT" | tr 'A-Z' 'a-z')" in
                            status) process_command "/status" "$CHAT_ID" ;;
                            list|vms|lxcs) process_command "/list" "$CHAT_ID" ;;
                            wake|on) process_command "/wake" "$CHAT_ID" ;;
                            sleep|off) process_command "/sleep" "$CHAT_ID" ;;
                            *) process_command "/help" "$CHAT_ID" ;;
                        esac
                    fi
                fi
            fi
        fi
        
        # Acknowledge callback query if it was one
        if [ -n "$CALLBACK_ID" ]; then
            curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/answerCallbackQuery" \
                --data-urlencode "callback_query_id=${CALLBACK_ID}" >/dev/null &
        fi
        
        i=$((i + 1))
    done
done
