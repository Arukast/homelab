#!/bin/bash

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
    local message_id="$4"
    local resp=""

    local method="sendMessage"
    local data_args="--data-urlencode \"chat_id=${chat_id}\" --data-urlencode \"text=${text}\""

    if [ -n "$message_id" ]; then
        method="editMessageText"
        data_args="--data-urlencode \"chat_id=${chat_id}\" --data-urlencode \"message_id=${message_id}\" --data-urlencode \"text=${text}\""
    fi

    if [ -n "$markup" ]; then
        resp=$(curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/$method" \
            $data_args \
            --data-urlencode "parse_mode=Markdown" \
            --data-urlencode "reply_markup=${markup}")

        # If Markdown failed (e.g. error 400), retry without Markdown formatting as plain text
        if ! echo "$resp" | grep -q '"ok":true'; then
            curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/$method" \
                $data_args \
                --data-urlencode "reply_markup=${markup}" >/dev/null
        fi
    else
        resp=$(curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/$method" \
            $data_args \
            --data-urlencode "parse_mode=Markdown")

        # If Markdown failed, retry without Markdown formatting as plain text
        if ! echo "$resp" | grep -q '"ok":true'; then
            curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/$method" \
                $data_args >/dev/null
        fi
    fi
}
