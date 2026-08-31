#!/bin/bash

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
            help_command
            ;;

        /status)
            status_command
            ;;

        /wake)
            wake_command
            ;;

        /sleep)
            sleep_command
            ;;

        /sleepforce)
            sleepforce_command
            ;;

        /hostshutdown)
            hostshutdown_command
            ;;

        /hostshutdownforce)
            hostshutdownforce_command
            ;;

        /hostreboot)
            hostreboot_command
            ;;

        /hostrebootforce)
            hostrebootforce_command
            ;;

        /list)
            list_command
            ;;

        /ctstart)
            ctstart_command
            ;;

        /ctstop)
            ctstop_command
            ;;

        /ctrestart)
            ctrestart_command
            ;;

        /vmstart)
            vmstart_command
            ;;

        /vmstop)
            vmstop_command
            ;;

        /vmrestart)
            vmrestart_command
            ;;

        /maintenance)
            maintenance_command
            ;;

        *)
            send_message "$chat_id" "$MSG_BOT_UNKNOWN_COMMAND"
            ;;
    esac
}
