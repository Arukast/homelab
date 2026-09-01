#!/bin/bash

help_command() {
    local markup='{"inline_keyboard":[
        [{"text":"Status","callback_data":"/status"},{"text":"List VMs","callback_data":"/list"}],
        [{"text":"Wake Host","callback_data":"/wake"},{"text":"Sleep (Safe)","callback_data":"/sleep"}]
    ]}'
    send_message "$chat_id" "$MSG_BOT_HELP" "$markup"
}