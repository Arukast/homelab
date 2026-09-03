#!/bin/bash

maintenance_command() {
    local chat_id="$1"
    local message_id="$2"
    local sub_cmd="$3"
    local target="$4"
    local reason="$5"

    if [ -z "$sub_cmd" ]; then
        local markup=$(get_markup "maintenance")
        send_message "$chat_id" "$MSG_BOT_MAINT_HELP" "$markup" "$message_id"
        return
    fi

    case "$sub_cmd" in
        system)
            if [ -z "$target" ]; then
                send_message "$chat_id" "$MSG_BOT_MAINT_USAGE_SYS" "" "$message_id"
                return
            fi
            if [ "$target" == "off" ]; then
                # Logic to turn off system maintenance
                local maint_out=$(maintenance_set_system off)
                send_message "$chat_id" "$maint_out" "" "$message_id"
            else
                # Logic to turn on system maintenance
                local maint_out=$(maintenance_set_system on "$target")
                send_message "$chat_id" "$maint_out" "" "$message_id"
            fi
            ;;
        service)
            if [ -z "$target" ]; then
                send_message "$chat_id" "$MSG_BOT_MAINT_USAGE_SVC" "" "$message_id"
                return
            fi
            if ! [[ "$target" =~ ^[0-9]+$ ]]; then
                send_message "$chat_id" "$MSG_BOT_MAINT_ERR_NUMERIC" "" "$message_id"
                return
            fi
            if [ -z "$reason" ]; then
                send_message "$chat_id" "$MSG_BOT_MAINT_USAGE_SVC" "" "$message_id"
                return
            fi
            if [ "$reason" == "off" ]; then
                # Logic to turn off service maintenance
                local maint_out=$(maintenance_set_service "$target" off)
                send_message "$chat_id" "$maint_out" "" "$message_id"
            else
                # Logic to turn on service maintenance
                local maint_out=$(maintenance_set_service "$target" on "$reason")
                send_message "$chat_id" "$maint_out" "" "$message_id"
            fi
            ;;
        status)
            local maint_out=$(maintenance_status)
            send_message "$chat_id" "$maint_out" "" "$message_id"
            ;;
        *)
            send_message "$chat_id" "$MSG_BOT_MAINT_ERR_UNKNOWN" "" "$message_id"
            ;;
    esac
}
