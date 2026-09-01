#!/bin/sh
# =============================================================================
# OpenWrt Homelab Power Orchestrator Installer
# File: PowerOrchestrator/openwrt/install_openwrt.sh
# Run this script on the OpenWrt router as root.
# =============================================================================

set -e

# Change directory to the script's location
cd "$(dirname "$0")"

# Load helper
. components/packages_helper.sh
. components/setup_conf_helper.sh
. components/script_helper.sh
. components/service_helper.sh
. components/post_install_helper.sh

# Parse command line arguments
FORCE_CONFIG=0
for arg in "$@"; do
    if [ "$arg" = "-f" ] || [ "$arg" = "--force" ]; then
        FORCE_CONFIG=1
    fi
done

echo "===================================================="
echo "Installing Homelab Power Orchestrator on OpenWrt    "
echo "===================================================="

# 1. Dependency checks and package installation
echo "[1/4] Installing dependencies..."
install_packages

# 2. Setup Configuration file
echo "[2/4] Setting up configuration..."
setup_confs

# 3. Install core scripts and utilities
echo "[3/4] Installing executable scripts..."
install_scripts

# 4. Install procd services and activate
echo "[4/4] Activating procd daemon services..."
install_services

# 5. Post-install Dropbear SSH Trust verification
echo "===================================================="
echo "Checking SSH Key and Security Wrapper setup...      "
echo "===================================================="
post_install

echo "===================================================="
echo "Installation Successful!                            "
echo "===================================================="
echo "Next Steps:"
echo "1. Edit values and bot token in: /etc/homelab_power.conf"
echo "2. Copy OpenWrt public key to Proxmox root's authorized_keys:"
echo "   Get public key by running:"
echo "   dropbearkey -y -f /etc/dropbear/id_dropbear"
echo "3. Run 'homelab_config_sync.sh' to sync configs and test SSH connection!"
echo "===================================================="
