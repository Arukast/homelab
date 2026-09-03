#!/bin/bash

#!/bin/bash

# Main Command Processor
process_command() {
    local cmd="$1"
    local chat_id="$2"
    local msg_id="$3"

    # Extract action and arguments
    local action_raw=$(echo "$cmd" | awk '{print $1}')
    # Strip bot username suffix if present (e.g., /status@MyBot -> /status)
    local action=$(echo "$action_raw" | cut -d'@' -f1 | tr 'A-Z' 'a-z')
    local arg1=$(echo "$cmd" | awk '{print $2}')

    case "$action" in
        /start|/help)
            help_command "$chat_id" "$msg_id"
            ;;

        /status)
            status_command "$chat_id" "$msg_id"
            ;;

        /wake)
            wake_command "$chat_id" "$msg_id"
            ;;

        /sleep)
            sleep_command "$chat_id" "$msg_id"
            ;;

        /sleepforce)
            sleepforce_command "$chat_id" "$msg_id"
            ;;

        /hostshutdown)
            hostshutdown_command "$chat_id" "$msg_id"
            ;;

        /hostshutdownforce)
            hostshutdownforce_command "$chat_id" "$msg_id"
            ;;

        /hostreboot)
            hostreboot_command "$chat_id" "$msg_id"
            ;;

        /hostrebootforce)
            hostrebootforce_command "$chat_id" "$msg_id"
            ;;

        /list)
            list_command "$chat_id" "$msg_id"
            ;;

        /ctstart)
            ctstart_command "$chat_id" "$msg_id" "$arg1"
            ;;

        /ctstop)
            ctstop_command "$chat_id" "$msg_id" "$arg1"
            ;;

        /ctrestart)
            ctrestart_command "$chat_id" "$msg_id" "$arg1"
            ;;

        /vmstart)
            vmstart_command "$chat_id" "$msg_id" "$arg1"
            ;;

        /vmstop)
            vmstop_command "$chat_id" "$msg_id" "$arg1"
            ;;

        /vmrestart)
            vmrestart_command "$chat_id" "$msg_id" "$arg1"
            ;;

        /maintenance)
            # Use all remaining arguments for maintenance (e.g., /maintenance system on)
            local full_cmd=$(echo "$cmd" | cut -d' ' -f2-)
            # Pass arguments properly
            if [ -z "$full_cmd" ]; then
                maintenance_command "$chat_id" "$msg_id"
            else
                maintenance_command "$chat_id" "$msg_id" $full_cmd
            fi
            ;;

        *)
            send_message "$chat_id" "$MSG_BOT_UNKNOWN_COMMAND"
            ;;
    esac
}

# Action Processor for callback-based structured data (action:type:id:op)
process_action() {
    local action_data="$1"
    local chat_id="$2"
    local msg_id="$3"

    # Parse action:type:id:op
    local action_type=$(echo "$action_data" | cut -d':' -f1)
    local target_id=$(echo "$action_data" | cut -d':' -f2)
    local operation=$(echo "$action_data" | cut -d':' -f3)

    # Note: We use a specialized dispatcher for menu-driven actions to avoid complexity
    # in the main case statement, but all actions eventually resolve to commands.
    # For simplicity in this shell implementation, we map common actions to their
    # existing slash-command equivalents, but handle them via direct function calls.

    case "$action_type" in
        cmd)
            # cmd:status:0:refresh -> /status
            # cmd:list:0:refresh -> /list
            # cmd:sleep:0:execute -> /sleep
            # cmd:shutdown:0:execute -> /hostshutdown
            # cmd:reboot:0:execute -> /hostreboot
            # cmd:vm:101:start -> /vmstart 101
            # cmd:ct:100:stop -> /ctstop 100
            # cmd:maint:sys:on -> /maintenance system ON
            # ... and so on.

            local cmd_name=$(echo "$action_data" | cut -d':' -f2)
            local target=$(echo "$action_data" | cut -d':' -f3)
            local op=$(echo "$action_data" | cut -d':' -f4)

            case "$cmd_name" in
                status|list|wake|sleep|sleepforce|hostshutdown|hostshutdownforce|hostreboot|hostrebootforce|maintenance)
                    process_command "/$cmd_name" "$chat_id" "$msg_id"
                    ;;
                vm|ct)
                    # Map vm/ct target/op to specific command handlers
                    # cmd:vm:101:start -> vmstart_command 101
                    # cmd:vm:101:stop -> vmstop_command 101
                    # cmd:vm:101:restart -> vmrestart_command 101
                    local handler=""
                    if [ "$cmd_name" = "vm" ]; then
                        case "$op" in
                            start) handler="vmstart_command" ;;
                            stop) handler="vmstop_command" ;;
                            restart) handler="vmrestart_command" ;;
                        esac
                    elif [ "$cmd_name" = "ct" ]; then
                        case "$op" in
                            start) handler="ctstart_command" ;;
                            stop) handler="ctstop_command" ;;
                            restart) handler="ctrestart_command" ;;
                        esac
                    fi

                    if [ -n "$handler" ]; then
                        $handler "$chat_id" "$msg_id" "$target"
                    else
                        send_message "$chat_id" "Invalid guest operation: $op"
                    fi
                    ;;
                *)
                    send_message "$chat_id" "Unknown command: $cmd_name"
                    ;;
            esac
            ;;
        maint)
            # maint:sys:on -> /maintenance system ON
            # maint:service:101:off -> /maintenance service 101 off
            local sub_type=$(echo "$action_data" | cut -d':' -f2)
            local target=$(echo "$action_data" | cut -d':' -f3)
            local op=$(echo "$action_data" | cut -d':' -f4)

            if [ "$sub_type" = "sys" ]; then
                # maint:sys:on -> /maintenance system on
                # maint:sys:off -> /maintenance system off
                process_command "/maintenance system $op" "$chat_id" "$msg_id"
            elif [ "$sub_type" = "service" ]; then
                # maint:service:101:off -> /maintenance service 101 off
                process_command "/maintenance service $target $op" "$chat_id" "$msg_id"
            fi
            ;;
        *)
            # Fall back to sending an error message inline rather than calling send_message
            # if the function is somehow unavailable, to prevent a crash loop
            send_message "$chat_id" "Invalid action format."
            ;;
    esac
}

