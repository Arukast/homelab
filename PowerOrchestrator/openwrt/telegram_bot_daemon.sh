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

SSH_CMD="ssh -i $SSH_KEY_PATH -y -K 3 root@$HOST_IP"

# Helper to dynamically evaluate/expand strings containing variables
expand_msg() {
    local raw_msg="$1"
    eval echo "\"$raw_msg\""
}

# Helper to send messages to Telegram
send_message() {
    local chat_id="$1"
    local text="$2"
    
    # URL encode the text using a simple sed/hexdump parser if needed, 
    # but curl --data-urlencode is native and handles everything perfectly!
    curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
        --data-urlencode "chat_id=${chat_id}" \
        --data-urlencode "text=${text}" \
        --data-urlencode "parse_mode=Markdown" >/dev/null
}

# Main Command Processor
process_command() {
    local cmd="$1"
    local chat_id="$2"
    
    # Extract action and arguments
    local action=$(echo "$cmd" | awk '{print $1}')
    local arg1=$(echo "$cmd" | awk '{print $2}')
    
    case "$action" in
        /start|/help)
            send_message "$chat_id" "$MSG_BOT_HELP"
            ;;
            
        /status)
            send_message "$chat_id" "$MSG_BOT_QUERY_STATUS"
            
            if ! ping -c 1 -W 1 "$HOST_IP" >/dev/null 2>&1; then
                send_message "$chat_id" "$(expand_msg "$MSG_BOT_HOST_SLEEPING")"
                return
            fi
            
            # Host is online, gather resources via SSH
            local uptime_info=$($SSH_CMD "uptime" 2>/dev/null)
            if [ $? -ne 0 ]; then
                send_message "$chat_id" "$MSG_BOT_SSH_FAILED"
                return
            fi
            
            local load_avg=$(echo "$uptime_info" | awk -F'load average:' '{print $2}' | sed 's/^[[:space:]]*//')
            local ram_info=$($SSH_CMD "free -h | awk 'NR==2 {print \$3 \" / \" \$2}'" 2>/dev/null)
            
            # Nodes summary
            local lxc_count=$($SSH_CMD "pct list | awk 'NR>1' | wc -l" 2>/dev/null)
            local lxc_running=$($SSH_CMD "pct list | awk 'NR>1 && \$2==\"running\"' | wc -l" 2>/dev/null)
            local vm_count=$($SSH_CMD "qm list | awk 'NR>1' | wc -l" 2>/dev/null)
            local vm_running=$($SSH_CMD "qm list | awk 'NR>1 && \$3==\"running\"' | wc -l" 2>/dev/null)
            
            local status_msg="⚡ *Host Status:* ONLINE
🔥 *Load Average:* ${load_avg}
📟 *RAM Usage:* ${ram_info}

🖥️ *Guest Nodes:*
• LXC Containers: ${lxc_running}/${lxc_count} running
• QEMU VMs: ${vm_running}/${vm_count} running

👉 Send \`/list\` to view all virtual machines and containers."
            send_message "$chat_id" "$status_msg"
            ;;
            
        /wake)
            send_message "$chat_id" "$(expand_msg "$MSG_BOT_WOL_SENT")"
            etherwake -i br-lan "$HOST_MAC"
            send_message "$chat_id" "$MSG_BOT_WOL_DISPATCHED"
            ;;
            
        /sleep)
            if ! ping -c 1 -W 1 "$HOST_IP" >/dev/null 2>&1; then
                send_message "$chat_id" "$MSG_BOT_SLEEP_ALREADY_OFFLINE"
                return
            fi
            
            send_message "$chat_id" "$MSG_BOT_SLEEP_TRIGGERED"
            echo "SLEEP" > /tmp/homelab_target_state
            # Run the idle monitor script on Proxmox in background with --force so it doesn't block the bot and suspends immediately
            $SSH_CMD "nohup /usr/local/bin/proxmox_idle_monitor.sh --force >/dev/null 2>&1 &" 2>/dev/null
            send_message "$chat_id" "$MSG_BOT_SLEEP_EXECUTED"
            ;;
            
        /host_shutdown)
            if ! ping -c 1 -W 1 "$HOST_IP" >/dev/null 2>&1; then
                send_message "$chat_id" "$MSG_BOT_SHUTDOWN_ALREADY_OFFLINE"
                return
            fi
            send_message "$chat_id" "$MSG_BOT_SHUTDOWN_SENDING"
            echo "SHUTDOWN" > /tmp/homelab_target_state
            $SSH_CMD "shutdown -h now" 2>/dev/null &
            send_message "$chat_id" "$MSG_BOT_SHUTDOWN_EXECUTED"
            ;;
            
        /host_reboot)
            if ! ping -c 1 -W 1 "$HOST_IP" >/dev/null 2>&1; then
                send_message "$chat_id" "$MSG_BOT_REBOOT_ALREADY_OFFLINE"
                return
            fi
            send_message "$chat_id" "$MSG_BOT_REBOOT_SENDING"
            echo "REBOOT" > /tmp/homelab_target_state
            $SSH_CMD "reboot" 2>/dev/null &
            send_message "$chat_id" "$MSG_BOT_REBOOT_EXECUTED"
            ;;
            
        /list)
            if ! ping -c 1 -W 1 "$HOST_IP" >/dev/null 2>&1; then
                send_message "$chat_id" "$MSG_BOT_LIST_HOST_OFFLINE"
                return
            fi
            
            local lxcs=$($SSH_CMD "pct list | awk 'NR>1 {print \"• LXC [\" \$1 \"] (\" \$3 \"): \" \$2}'" 2>/dev/null)
            local vms=$($SSH_CMD "qm list | awk 'NR>1 {print \"• VM [\" \$1 \"] (\" \$2 \"): \" \$3}'" 2>/dev/null)
            
            [ -z "$lxcs" ] && lxcs="None configured."
            [ -z "$vms" ] && vms="None configured."
            
            local list_msg="🖥️ *Proxmox Guest Nodes:*

📦 *Containers:*
${lxcs}

🎮 *Virtual Machines:*
${vms}"
            send_message "$chat_id" "$list_msg"
            ;;
            
        /ct_start)
            if [ -z "$arg1" ]; then
                send_message "$chat_id" "$MSG_BOT_CT_START_USAGE"
                return
            fi
            
            if ! ping -c 1 -W 1 "$HOST_IP" >/dev/null 2>&1; then
                send_message "$chat_id" "$MSG_BOT_CT_START_HOST_OFFLINE"
                return
            fi
            
            send_message "$chat_id" "$(expand_msg "$MSG_BOT_CT_START_STARTING")"
            # Detect if VM or LXC and start
            local start_out
            if $SSH_CMD "pct config $arg1" >/dev/null 2>&1; then
                start_out=$($SSH_CMD "pct start $arg1" 2>&1)
            elif $SSH_CMD "qm config $arg1" >/dev/null 2>&1; then
                start_out=$($SSH_CMD "qm start $arg1" 2>&1)
            else
                send_message "$chat_id" "$(expand_msg "$MSG_BOT_CT_START_NOT_FOUND")"
                return
            fi
            
            send_message "$chat_id" "$(expand_msg "$MSG_BOT_CT_START_SUCCESS")
\`\`\`
${start_out:-Started successfully}
\`\`\`"
            ;;
            
        /ct_stop)
            if [ -z "$arg1" ]; then
                send_message "$chat_id" "$MSG_BOT_CT_STOP_USAGE"
                return
            fi
            
            if ! ping -c 1 -W 1 "$HOST_IP" >/dev/null 2>&1; then
                send_message "$chat_id" "$MSG_BOT_CT_STOP_HOST_OFFLINE"
                return
            fi
            
            send_message "$chat_id" "$(expand_msg "$MSG_BOT_CT_STOP_STOPPING")"
            local stop_out
            if $SSH_CMD "pct config $arg1" >/dev/null 2>&1; then
                stop_out=$($SSH_CMD "pct stop $arg1" 2>&1)
            elif $SSH_CMD "qm config $arg1" >/dev/null 2>&1; then
                stop_out=$($SSH_CMD "qm shutdown $arg1" 2>&1)
            else
                send_message "$chat_id" "$(expand_msg "$MSG_BOT_CT_STOP_NOT_FOUND")"
                return
            fi
            
            send_message "$chat_id" "$(expand_msg "$MSG_BOT_CT_STOP_SUCCESS")
\`\`\`
${stop_out:-Stop signal dispatched}
\`\`\`"
            ;;
            
        /ct_restart)
            if [ -z "$arg1" ]; then
                send_message "$chat_id" "$MSG_BOT_CT_RESTART_USAGE"
                return
            fi
            
            if ! ping -c 1 -W 1 "$HOST_IP" >/dev/null 2>&1; then
                send_message "$chat_id" "$MSG_BOT_CT_RESTART_HOST_OFFLINE"
                return
            fi
            
            send_message "$chat_id" "$(expand_msg "$MSG_BOT_CT_RESTART_RESTARTING")"
            local res_out
            if $SSH_CMD "pct config $arg1" >/dev/null 2>&1; then
                res_out=$($SSH_CMD "pct reboot $arg1" 2>&1)
            elif $SSH_CMD "qm config $arg1" >/dev/null 2>&1; then
                res_out=$($SSH_CMD "qm reboot $arg1" 2>&1)
            else
                send_message "$chat_id" "$(expand_msg "$MSG_BOT_CT_RESTART_NOT_FOUND")"
                return
            fi
            
            send_message "$chat_id" "$(expand_msg "$MSG_BOT_CT_RESTART_SUCCESS")
\`\`\`
${res_out:-Restart signal dispatched}
\`\`\`"
            ;;
            
        *)
            send_message "$chat_id" "$MSG_BOT_UNKNOWN_COMMAND"
            ;;
    esac
}

# Main polling loop
OFFSET=0
echo "Starting Homelab Telegram Bot Daemon..."

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
        sleep 10
        continue
    fi
    
    # Get total count of updates
    COUNT=$(echo "$UPDATES" | jsonfilter -e '@.result[*].update_id' 2>/dev/null | wc -l)
    if [ -z "$COUNT" ] || [ "$COUNT" -eq 0 ]; then
        continue
    fi
    
    i=0
    while [ $i -lt $COUNT ]; do
        UPDATE_ID=$(echo "$UPDATES" | jsonfilter -e "@.result[$i].update_id")
        USER_ID=$(echo "$UPDATES" | jsonfilter -e "@.result[$i].message.from.id")
        CHAT_ID=$(echo "$UPDATES" | jsonfilter -e "@.result[$i].message.chat.id")
        CMD_TEXT=$(echo "$UPDATES" | jsonfilter -e "@.result[$i].message.text")
        
        # Advance offset to acknowledge this update
        OFFSET=$((UPDATE_ID + 1))
        
        if [ -n "$CMD_TEXT" ] && [ -n "$USER_ID" ]; then
            # Verify if user is allowed
            AUTHORIZED=0
            for allowed in $(echo "$ALLOWED_USER_IDS" | tr ',' ' '); do
                if [ "$allowed" = "$USER_ID" ]; then
                    AUTHORIZED=1
                    break
                fi
            done
            
            if [ $AUTHORIZED -eq 0 ]; then
                echo "Blocked unauthorized user ID: $USER_ID attempting command: $CMD_TEXT"
                send_message "$CHAT_ID" "$(expand_msg "$MSG_BOT_UNAUTHORIZED")"
            else
                echo "Running command: $CMD_TEXT from authorized User ID: $USER_ID"
                process_command "$CMD_TEXT" "$CHAT_ID"
            fi
        fi
        
        i=$((i + 1))
    done
done
