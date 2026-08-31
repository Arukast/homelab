#!/bin/sh
# =============================================================================
# OpenWrt Shell Telegram Bot Daemon for Homelab Power Control
# File: /usr/bin/telegram_bot_daemon.sh
# =============================================================================

# Load shared components from /usr/bin/components
SHARED_COMP="/usr/bin/components"
# Load power_proxy components from /usr/bin/telegram_components
TB_COMP="/usr/bin/telegram_components"

# Load Helper
. "$SHARED_COMP"/conf_helper.sh
. "$SHARED_COMP"/check_helper.sh
. "$TB_COMP"/message_helper.sh
. "$TB_COMP"/polling_helper.sh
. "$TB_COMP"/process_command_helper.sh


# Read Config
read_conf "/etc/homelab_power.conf"
check_ip "/etc/homelab_power.conf"
read_optional_conf "/etc/homelab_messages.conf"

PIDFILE="/var/run/telegram_bot_daemon.pid"
HOST_SSH_PORT="${HOST_SSH_PORT:-${SSH_PORT:-22}}"
HOST_SSH_USER="${HOST_SSH_USER:-root}"
SSH_CMD="ssh -p $HOST_SSH_PORT -i $SSH_KEY_PATH -y -K 3 ${HOST_SSH_USER}@$HOST_IP"

is_pid_running "$PIDFILE" "telegram_bot_daemon.sh"

cleanup_pid() {
    rm -f "$PIDFILE"
    exit 0
}
trap cleanup_pid SIGTERM SIGINT EXIT

# Check token
is_telegram_bot_token

# Check host alliveness
is_host_alive

# Helper to dynamically evaluate/expand strings containing variables
expand_msg

# Helper to send messages to Telegram with Markdown auto-fallback
send_message

process_command

# Main polling loop
poll_updates
