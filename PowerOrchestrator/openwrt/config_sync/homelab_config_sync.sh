#!/bin/sh
# =============================================================================
# OpenWrt Homelab Configuration Synchronization & SSH Trust Verification
# File: /usr/bin/homelab_config_sync.sh
# =============================================================================

# Load shared components from /usr/bin/components
SHARED_COMP="/usr/bin/components"
# Load power_proxy components from /usr/bin/homelab_config_sync.sh
SYNC_COMP="/usr/bin/homelab_config_sync.sh"

# Load Helper
. "$SHARED_COMP"/conf_helper.sh
. "$SYNC_COMP"/permission_helper.sh
. "$SYNC_COMP"/verify_helper.sh
. "$SYNC_COMP"/router_ip_helper.sh
. "$SYNC_COMP"/sanitized_conf_helper.sh
. "$SYNC_COMP"/deploy_helper.sh


# Read Config
read_conf "/etc/homelab_power.conf"

# Check IP
check_ip

SSH_KEY_PATH="${SSH_KEY_PATH:-/etc/dropbear/id_dropbear}"
HOST_SSH_PORT="${HOST_SSH_PORT:-${SSH_PORT:-22}}"
HOST_SSH_USER="${HOST_SSH_USER:-root}"

echo "===================================================="
echo "Homelab Power Orchestrator Configuration Sync Tool"
echo "===================================================="

# 1. Check local Dropbear private key permissions
check_permission

# 2. Verify passwordless SSH connection & SSH Wrapper status
verify_ssh
ssh_test
ssh_block

# 3. Calculate dynamic Router IP facing Proxmox
get_router_ip

# 4. Generate sanitized configuration file
sanitize_config

# 5. Push the configuration to Proxmox
deploy_config

echo "Sync complete."
exit 0
