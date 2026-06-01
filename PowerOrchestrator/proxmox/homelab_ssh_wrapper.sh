#!/bin/sh
# =============================================================================
# Proxmox VE Homelab SSH Command Wrapper
# File: /usr/local/bin/homelab_ssh_wrapper.sh
# Restricts incoming SSH commands from OpenWrt to the minimum required subset.
# =============================================================================

# Log attempts to syslog if enabled
logger -t homelab-ssh-wrapper "Received command execution request: $SSH_ORIGINAL_COMMAND"

case "$SSH_ORIGINAL_COMMAND" in
    "echo OK")
        echo "OK"
        ;;
        
    "echo '===METRICS==='; uptime; echo '===RAM==='; free -h; echo '===LXC==='; pct list; echo '===VM==='; qm list")
        eval "$SSH_ORIGINAL_COMMAND"
        ;;
        
    # Match the AWK metrics and node count commands
    "pct list | awk "*|"qm list | awk "*)
        eval "$SSH_ORIGINAL_COMMAND"
        ;;
        
    # Match single-line config and power management commands
    "pct config "*|"qm config "*|"pct start "*|"qm start "*|"pct stop "*|"qm shutdown "*|"pct reboot "*|"qm reboot "*|"pct resume "*|"qm resume "*)
        # Extract the last argument (which should be the VMID) and strictly check that it is numeric
        VMID=$(echo "$SSH_ORIGINAL_COMMAND" | awk '{print $NF}')
        if echo "$VMID" | grep -qE "^[0-9]+$"; then
            eval "$SSH_ORIGINAL_COMMAND"
        else
            echo "Access Denied: VMID must be purely numeric." >&2
            exit 1
        fi
        ;;
        
    # Match the multi-line cgi-bin status wake command block
    "if pct config "*)
        # Extract the VMID (4th word in "if pct config <VMID>") and ensure it is strictly numeric
        VMID=$(echo "$SSH_ORIGINAL_COMMAND" | awk '{print $4}')
        if echo "$VMID" | grep -qE "^[0-9]+$"; then
            eval "$SSH_ORIGINAL_COMMAND"
        else
            echo "Access Denied: VMID must be purely numeric." >&2
            exit 1
        fi
        ;;
        
    # Match background idle monitor executions
    "nohup /usr/local/bin/proxmox_idle_monitor.sh"*)
        eval "$SSH_ORIGINAL_COMMAND"
        ;;
        
    *)
        logger -t homelab-ssh-wrapper "BLOCKED unauthorized command: $SSH_ORIGINAL_COMMAND"
        echo "Access Denied: Command not permitted by Homelab SSH wrapper." >&2
        exit 1
        ;;
esac
