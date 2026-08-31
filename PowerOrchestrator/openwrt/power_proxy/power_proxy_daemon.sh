#!/bin/sh
# =============================================================================
# OpenWrt Homelab Power Proxy and Redirection Daemon
# File: /usr/bin/power_proxy_daemon.sh
# =============================================================================

# Load shared components from /usr/bin/components
SHARED_COMP="/usr/bin/components"
# Load power_proxy components from /usr/bin/power_proxy_components
PP_COMP="/usr/bin/power_proxy_components"

# Load Helper
. "$SHARED_COMP"/conf_helper.sh
. "$SHARED_COMP"/check_helper.sh
. "$PP_COMP"/notify_helper.sh
. "$PP_COMP"/redirects_helper.sh
. "$PP_COMP"/network_helper.sh
. "$PP_COMP"/listener_helper.sh
. "$PP_COMP"/cleanup_helper.sh
. "$PP_COMP"/main.sh

# Read Config
read_conf "/etc/homelab_power.conf"
check_ip "/etc/homelab_power.conf"
read_optional_conf "/etc/homelab_messages.conf"

is_pid_running "/var/run/power_proxy_daemon.pid" "power_proxy_daemon.sh"

# State variables
CURRENT_STATE="UNKNOWN"
FAILED_PINGS=0
GAME_PIDS=""

HOST_SSH_PORT="${HOST_SSH_PORT:-${SSH_PORT:-22}}"
HOST_SSH_USER="${HOST_SSH_USER:-root}"
SSH_CMD="ssh -p $HOST_SSH_PORT -i $SSH_KEY_PATH -y -K 3 ${HOST_SSH_USER}@$HOST_IP"
IFACE="${LAN_INTERFACE:-br-lan}"

trap cleanup_main SIGTERM SIGINT

# Initialize ARP binding
apply_static_arp

main
