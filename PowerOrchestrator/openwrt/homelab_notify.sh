#!/bin/sh
# =============================================================================
# OpenWrt Centralized Notification Dispatcher for Homelab Power Control
# File: /usr/bin/homelab_notify.sh
# =============================================================================

CONF="/etc/homelab_power.conf"
if [ -f "$CONF" ]; then
    . "$CONF"
fi

MSG="$1"
if [ -z "$MSG" ]; then
    # Read from stdin if no argument provided
    MSG=$(cat)
fi

if [ -z "$MSG" ]; then
    exit 0
fi

# Telegram dispatch
if [ -n "$BOT_TOKEN" ] && [ "$BOT_TOKEN" != "YOUR_TELEGRAM_BOT_TOKEN" ]; then
    target_chats="${NOTIFY_CHAT_ID}"
    [ -z "$target_chats" ] && target_chats=$(echo "$ALLOWED_USER_IDS" | cut -d',' -f1)
    
    for chat in $(echo "$target_chats" | tr ',' ' '); do
        # If notifications are disabled, only notify IDs in ALLOWED_USER_IDS (admin private chats)
        if [ "$DISABLE_NOTIFICATIONS" = "1" ]; then
            is_allowed=0
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
            --data-urlencode "text=${MSG}" \
            --data-urlencode "parse_mode=Markdown" >/dev/null &
    done
fi

# Discord Webhook dispatch
if [ "$DISABLE_NOTIFICATIONS" != "1" ] && [ -n "$DISCORD_WEBHOOK_URL" ]; then
    color=3899126 # Default Cyber Blue
    if echo "$MSG" | grep -iqE "awake|online|restored|success"; then
        color=1095905 # Green
    elif echo "$MSG" | grep -iqE "sleep|S3|offline|down|shutdown|suspended|stopped"; then
        color=15680580 # Red
    elif echo "$MSG" | grep -iqE "reboot|rebooting"; then
        color=9133302 # Purple/Indigo
    fi
    
    clean_msg=$(echo "$MSG" | sed 's/"/\\"/g')
    payload="{\"embeds\":[{\"title\":\"🔔 Power Monitor Notification\",\"description\":\"${clean_msg}\",\"color\":${color},\"footer\":{\"text\":\"Arukast Homelab Portal\"}}]}"
    
    for url in $(echo "$DISCORD_WEBHOOK_URL" | tr ',' ' '); do
        curl -s -H "Content-Type: application/json" -X POST -d "$payload" "$url" >/dev/null &
    done
fi

# Wait briefly for background curl jobs to start/finish
wait
exit 0
