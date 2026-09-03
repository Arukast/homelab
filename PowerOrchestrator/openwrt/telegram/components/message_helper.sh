#!/bin/bash

# Helper to generate context-specific inline keyboard markup
get_markup() {
    local type="$1"
    case "$type" in
        help)
            cat <<EOF
{"inline_keyboard": [
    [{"text": "Status", "callback_data": "/status"}, {"text": "Wake", "callback_data": "/wake"}],
    [{"text": "List", "callback_data": "/list"}, {"text": "Maint", "callback_data": "/maintenance status"}]
]}
EOF
            ;;
        status_online)
            cat <<EOF
{"inline_keyboard": [
    [{"text": "List", "callback_data": "/list"}, {"text": "Sleep", "callback_data": "/sleep"}],
    [{"text": "Refresh", "callback_data": "/status"}]
]}
EOF
            ;;
        status_offline)
            cat <<EOF
{"inline_keyboard": [
    [{"text": "Wake Host", "callback_data": "/wake"}]
]}
EOF
            ;;
        list)
            cat <<EOF
{"inline_keyboard": [
    [{"text": "Status", "callback_data": "/status"}, {"text": "Maint", "callback_data": "/maintenance status"}]
]}
EOF
            ;;
        maintenance)
            cat <<EOF
{"inline_keyboard": [
    [{"text": "Status", "callback_data": "/maintenance status"}, {"text": "Main Menu", "callback_data": "/help"}]
]}
EOF
            ;;
        wake)
            cat <<EOF
{"inline_keyboard": [
    [{"text": "Main Menu", "callback_data": "/status"}]
]}
EOF
            ;;
        *)
            echo ""
            ;;
    esac
}

# Helper to expand messages with placeholders $arg1, $arg2, $arg3, $arg4
expand_msg() {
    local raw_msg="$1"

    # Use sed to replace placeholders $arg1, $arg2, $arg3, $arg4 with the values
    # of the environment variables.
    # We use single quotes for the sed expression to prevent premature expansion.
    # We escape the backslashes for the variable references.
    echo "$raw_msg" | sed "s/\\\$arg1/${arg1//\//\\/}/g; s/\\\$arg2/${arg2//\//\\/}/g; s/\\\$arg3/${arg3//\//\\/}/g; s/\\\$arg4/${arg4//\//\\/}/g; s/\\\$HOST_MAC/$HOST_MAC/g"
}

# Helper to send messages to Telegram with Markdown auto-fallback
send_message() {
    local chat_id="$1"
    local raw_text="$2"
    local markup="$3"
    local message_id="$4"

    # Expand the message here, inside the function, using the current environment
    local text
    text=$(expand_msg "$raw_text")

    local method="sendMessage"

    if [ -n "$message_id" ]; then
        method="editMessageText"
        resp=$(curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/$method" \
            --data-urlencode "chat_id=${chat_id}" \
            --data-urlencode "message_id=${message_id}" \
            --data-urlencode "text=${text}" \
            --data-urlencode "parse_mode=Markdown" \
            --data-urlencode "reply_markup=${markup}")

        # If Markdown failed, retry without Markdown formatting
        if ! echo "$resp" | grep -q '"ok":true'; then
            curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/$method" \
                --data-urlencode "chat_id=${chat_id}" \
                --data-urlencode "message_id=${message_id}" \
                --data-urlencode "text=${text}" \
                --data-urlencode "reply_markup=${markup}" >/dev/null
        fi
    else
        resp=$(curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/$method" \
            --data-urlencode "chat_id=${chat_id}" \
            --data-urlencode "text=${text}" \
            --data-urlencode "parse_mode=Markdown" \
            --data-urlencode "reply_markup=${markup}")

        # If Markdown failed, retry without Markdown formatting
        if ! echo "$resp" | grep -q '"ok":true'; then
            curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/$method" \
                --data-urlencode "chat_id=${chat_id}" \
                --data-urlencode "text=${text}" \
                --data-urlencode "reply_markup=${markup}" >/dev/null
        fi
    fi
}
