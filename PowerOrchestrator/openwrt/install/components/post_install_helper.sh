#!/bin/sh

post_install() {
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

    if [ -n "$HOST_IP" ] && { [ "$HOST_IP" != "192.168.11.10" ] || [ "$HOST_MAC" != "aa:bb:cc:dd:ee:ff" ] || [ "$BOT_TOKEN" != "YOUR_TELEGRAM_BOT_TOKEN" ]; }; then
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
}
