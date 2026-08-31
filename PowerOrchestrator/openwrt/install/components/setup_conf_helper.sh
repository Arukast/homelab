#!/bin/sh

setup_confs() {
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
}
