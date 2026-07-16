#!/bin/sh
# =============================================================================
# OpenWrt Homelab Power Orchestrator Installer
# File: PowerOrchestrator/openwrt/install_openwrt.sh
# Run this script on the OpenWrt router as root.
# =============================================================================

set -e

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
echo "[1/6] Installing dependencies..."

PACKAGES="etherwake jsonfilter uhttpd uhttpd-mod-ubus curl"

if command -v apk >/dev/null 2>&1; then
    echo "Modern OpenWrt (apk package manager) detected. Updating repository index..."
    apk update
    
    # In OpenWrt 24+, uhttpd is split/named slightly differently or already present. 
    # apk handles package names natively.
    for pkg in $PACKAGES; do
        if ! apk info -e "$pkg" >/dev/null 2>&1; then
            echo "Installing $pkg..."
            apk add "$pkg"
        else
            echo "$pkg is already installed."
        fi
    done
else
    echo "Traditional OpenWrt (opkg package manager) detected. Updating package list..."
    opkg update
    for pkg in $PACKAGES; do
        if ! opkg list-installed | grep -q "^$pkg[[:space:]]"; then
            echo "Installing $pkg..."
            opkg install "$pkg"
        else
            echo "$pkg is already installed."
        fi
    done
fi

# 2. Setup Configuration file
echo "[2/6] Setting up configuration..."
if [ -f "/etc/homelab_power.conf" ] && [ "$FORCE_CONFIG" -ne 1 ]; then
    echo "Configuration file /etc/homelab_power.conf already exists. Preserving it."
    echo "Run this installer with the -f or --force flag to overwrite it with your laptop's version."
else
    if [ -f "homelab_power.conf" ]; then
        cp homelab_power.conf /etc/homelab_power.conf
        echo "Created/Overwrote /etc/homelab_power.conf from your custom local config file."
    else
        cp homelab_power.conf.example /etc/homelab_power.conf
        echo "Created/Overwrote /etc/homelab_power.conf from the default template."
    fi
    chmod 600 /etc/homelab_power.conf
fi

# Setup Messages Configuration file
if [ -f "/etc/homelab_messages.conf" ] && [ "$FORCE_CONFIG" -ne 1 ]; then
    echo "Message configuration file /etc/homelab_messages.conf already exists. Preserving it."
else
    if [ -f "homelab_messages.conf" ]; then
        cp homelab_messages.conf /etc/homelab_messages.conf
        echo "Created/Overwrote /etc/homelab_messages.conf from your local config file."
    fi
    chmod 600 /etc/homelab_messages.conf
fi

# 3. Install core scripts and utilities
echo "[3/6] Installing executable scripts..."
cp telegram_bot_daemon.sh /usr/bin/telegram_bot_daemon.sh
cp power_proxy_daemon.sh /usr/bin/power_proxy_daemon.sh
cp game_wake_listener.sh /usr/bin/game_wake_listener.sh
cp guest_wake_listener.sh /usr/bin/guest_wake_listener.sh
cp homelab_notify.sh /usr/bin/homelab_notify.sh
cp homelab_config_sync.sh /usr/bin/homelab_config_sync.sh

chmod +x /usr/bin/telegram_bot_daemon.sh
chmod +x /usr/bin/power_proxy_daemon.sh
chmod +x /usr/bin/game_wake_listener.sh
chmod +x /usr/bin/guest_wake_listener.sh
chmod +x /usr/bin/homelab_notify.sh
chmod +x /usr/bin/homelab_config_sync.sh

echo "Scripts installed to /usr/bin/."

# 4. Setup Waking Web Server files
echo "[4/6] Copying waking server files..."
mkdir -p /www_waking/cgi-bin

cp waking_server/index.html /www_waking/index.html
cp waking_server/cgi-bin/status /www_waking/cgi-bin/status
cp waking_server/cgi-bin/notify /www_waking/cgi-bin/notify
chmod +x /www_waking/cgi-bin/status
chmod +x /www_waking/cgi-bin/notify

echo "Waking server deployed to /www_waking."

# 5. Configure Managed uhttpd instance for Waking Server
echo "[5/6] Registering waking server instance in uhttpd..."
# Check for system certificates to enable SSL on port 8443
SSL_SUPPORT=1
if [ ! -f "/etc/uhttpd.crt" ] || [ ! -f "/etc/uhttpd.key" ]; then
    echo "Warning: System uhttpd SSL certificates not found at /etc/uhttpd.crt"
    echo "Checking fallback locations..."
    if [ -f "/etc/uhttpd/uhttpd.crt" ]; then
        CERT_PATH="/etc/uhttpd/uhttpd.crt"
        KEY_PATH="/etc/uhttpd/uhttpd.key"
    else
        echo "SSL certs unavailable. Setting up waking server on HTTP port 8080 only."
        SSL_SUPPORT=0
    fi
else
    CERT_PATH="/etc/uhttpd.crt"
    KEY_PATH="/etc/uhttpd.key"
fi

# Clean existing UCI waking configuration if present, then rebuild cleanly
uci delete uhttpd.waking 2>/dev/null || true

uci set uhttpd.waking=uhttpd
uci set uhttpd.waking.home='/www_waking'
uci add_list uhttpd.waking.listen_http='0.0.0.0:8080'
uci add_list uhttpd.waking.listen_http='[::]:8080'

if [ "$SSL_SUPPORT" -eq 1 ]; then
    uci add_list uhttpd.waking.listen_https='0.0.0.0:8443'
    uci add_list uhttpd.waking.listen_https='[::]:8443'
    uci set uhttpd.waking.cert="$CERT_PATH"
    uci set uhttpd.waking.key="$KEY_PATH"
fi

uci set uhttpd.waking.cgi_prefix='/cgi-bin'
uci commit uhttpd

# Restart uhttpd service to apply the configuration
/etc/init.d/uhttpd restart
echo "Waking server registered natively on uhttpd!"

# 6. Install procd services and activate
echo "[6/6] Activating procd daemon services..."
cp telegram_bot.init /etc/init.d/telegram_bot
cp power_proxy.init /etc/init.d/power_proxy

chmod +x /etc/init.d/telegram_bot
chmod +x /etc/init.d/power_proxy

# Enable services to run on boot
/etc/init.d/power_proxy enable
/etc/init.d/telegram_bot enable

# Start services
/etc/init.d/power_proxy start
/etc/init.d/telegram_bot start

# 7. Post-install Dropbear SSH Trust verification
echo "===================================================="
echo "Checking SSH Key and Security Wrapper setup...      "
echo "===================================================="
SSH_KEY_PATH="/etc/dropbear/id_dropbear"
if [ ! -f "$SSH_KEY_PATH" ]; then
    echo "Warning: SSH key not found at $SSH_KEY_PATH!"
    echo "Generating new Dropbear key..."
    mkdir -p /etc/dropbear
    dropbearkey -t rsa -f "$SSH_KEY_PATH"
fi

# Load config to get host IP
if [ -f "/etc/homelab_power.conf" ]; then
    . "/etc/homelab_power.conf"
fi

if [ -n "$HOST_IP" ] && [ "$HOST_IP" != "192.168.11.10" ]; then
    echo "Attempting to verify SSH connectivity and wrapper on Proxmox ($HOST_IP)..."
    if /usr/bin/homelab_config_sync.sh; then
        echo "Sync and verification succeeded!"
    else
        echo "Verification warning/failure. Please check SSH keys and host connectivity."
    fi
else
    echo "HOST_IP is still default. Skipping automatic connection tests."
    echo "Once you edit /etc/homelab_power.conf, you can sync config and verify security by running:"
    echo "homelab_config_sync.sh"
fi

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
