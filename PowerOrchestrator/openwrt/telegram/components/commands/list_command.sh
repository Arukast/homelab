#!/bin/bash

list_command() {
    local chat_id="$1"
    local msg_id="$2"

    if ! is_host_alive; then
        send_message "$chat_id" "$MSG_BOT_LIST_HOST_OFFLINE" "$msg_id"
        return
    fi

    local payload=$($SSH_CMD "echo '===LXC==='; pct list; echo '===VM==='; qm list" 2>/dev/null)
    if [ $? -ne 0 ] || [ -z "$payload" ]; then
        send_message "$chat_id" "$MSG_BOT_SSH_FAILED" "$msg_id"
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

    # Dynamic node buttons for the secondary menu (Guest Control)
    local lxc_buttons=$(echo "$payload" | awk '
        /===LXC===/{flag=1; next}
        /===VM===/{flag=0}
        flag && NR>2 && $1 != "VMID" && $1 != "" {
            vmid = $1; status = $2; name = $3;
            btn_text = (status == "running" ? "🛑 " name : "▶️ " name);
            # Format: cmd:node:vmid:op
            cmd = (status == "running" ? "cmd:node:" vmid ":stop" : "cmd:node:" vmid ":start");
            printf "[{\"text\":\"%s\",\"callback_data\":\"%s\"}]", btn_text, cmd
        }
    ' | paste -sd, -)

    local vm_buttons=$(echo "$payload" | awk '
        /===VM===/{flag=1; next}
        flag && NR>2 && $1 != "VMID" && $1 != "" {
            vmid = $1; name = $2; status = $3;
            btn_text = (status == "running" ? "🛑 " name : "▶️ " name);
            # Format: cmd:node:vmid:op
            cmd = (status == "running" ? "cmd:node:" vmid ":stop" : "cmd:node:" vmid ":start");
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
        # Main List Menu Keyboard
        markup="{\"inline_keyboard\":[[$all_buttons],[{\"text\":\"🔙 Back to Main Menu\",\"callback_data\":\"cmd:menu:0:back\"}]]}"
    fi

    send_message "$chat_id" "$list_msg" "$markup" "$msg_id"
}
