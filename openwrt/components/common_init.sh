#!/bin/sh
# =============================================================================
# OpenWrt Homelab Power Orchestrator Common Initialization Helper
# File: /usr/bin/components/common_init.sh
# =============================================================================

# Define common component paths
export SHARED_COMP="/usr/bin/components"
export PP_COMP="/usr/bin/power_proxy_components"
export TB_COMP="/usr/bin/telegram_components"
export SYNC_COMP="/usr/bin/config_sync_components" # This will be the new path for config sync components

# Source essential helpers
. "$SHARED_COMP"/conf_helper.sh
. "$SHARED_COMP"/check_helper.sh

# Function to load common configurations
init_common_config() {
    local config_file="${1:-/etc/power_homelab.conf}"
    local msg_config_file="${2:-/etc/messages_homelab.conf}"

    read_conf "$config_file"
    check_ip "$config_file" # Use config_file for error message consistency
    read_optional_conf "$msg_config_file"
}

# Function to set up SSH connection parameters
# SSH_CMD is kept as a string for compatibility with existing call sites
# (e.g. "$SSH_CMD" "remote command"). Its components — key path, port, user, IP —
# are non-whitespace values by nature, so word-splitting is not a concern here.
init_ssh_vars() {
    export SSH_KEY_PATH="${SSH_KEY_PATH:-/etc/dropbear/id_dropbear}"
    export HOST_SSH_PORT="${HOST_SSH_PORT:-${SSH_PORT:-22}}"
    export HOST_SSH_USER="${HOST_SSH_USER:-root}"

    SSH_CMD="ssh -p $HOST_SSH_PORT -i $SSH_KEY_PATH -y -K 3 ${HOST_SSH_USER}@$HOST_IP"
    export SSH_CMD
}

# Function to set up daemon PID file and cleanup trap
init_daemon_pid() {
    local pidfile="$1"
    local daemon_name="$2"

    is_pid_running "$pidfile" "$daemon_name"

    cleanup_pid() {
        rm -f "$pidfile"
        exit 0
    }
    trap cleanup_pid SIGTERM SIGINT EXIT
}
