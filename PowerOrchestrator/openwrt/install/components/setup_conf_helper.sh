#!/bin/sh

setup_confs() {
    if [ -f "/etc/power_homelab.conf" ] && [ "$FORCE_CONFIG" -ne 1 ]; then
        echo "Configuration file /etc/power_homelab.conf already exists. Preserving it."
        echo "Run this installer with the -f or --force flag to overwrite it with your laptop's version."
    else
        if [ -f "/tmp/openwrt_powerorchestractor/power_homelab.conf" ]; then
            cp /tmp/openwrt_powerorchestractor/power_homelab.conf /etc/power_homelab.conf
            echo "Created/Overwrote /etc/power_homelab.conf from your custom local config file."
        else
            cp /tmp/openwrt_powerorchestractor/power_homelab.conf.example /etc/power_homelab.conf
            echo "Created/Overwrote /etc/power_homelab.conf from the default template."
        fi
        chmod 600 /etc/power_homelab.conf
    fi

    # Setup Messages Configuration file
    if [ -f "/etc/messages_homelab.conf" ] && [ "$FORCE_CONFIG" -ne 1 ]; then
        echo "Message configuration file /etc/messages_homelab.conf already exists. Preserving it."
    else
        if [ -f "/tmp/openwrt_powerorchestractor/messages_homelab.conf" ]; then
            cp /tmp/openwrt_powerorchestractor/messages_homelab.conf /etc/messages_homelab.conf
            echo "Created/Overwrote /etc/messages_homelab.conf from your local config file."
        fi
        chmod 600 /etc/messages_homelab.conf
    fi
}
