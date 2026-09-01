#!/bin/bash

help_command() {
    local chat_id="$1"
    local msg_id="$2"

    local markup='{"inline_keyboard":[
        [{"text":"📊 Status","callback_data":"cmd:status:0:refresh"},{"text":"📋 List Nodes","callback_data":"cmd:list:0:refresh"}],
        [{"text":"⚡ Host Power","callback_data":"cmd:power:0:menu"},{"text":"🛠️ Maintenance","callback_data":"cmd:maint:0:status"}]
    ]}'

    send_message "$chat_id" "$MSG_BOT_HELP" "$markup" "$msg_id"
}