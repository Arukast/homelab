#!/bin/sh

install_scripts() {
    cp telegram/telegram_bot_daemon.sh /usr/bin/telegram_bot_daemon.sh
    cp power_proxy/power_proxy_daemon.sh /usr/bin/power_proxy_daemon.sh
    # Deploy shared components
    mkdir -p /usr/bin/components
    cp components/* /usr/bin/components/
    # Deploy power_proxy components
    mkdir -p /usr/bin/power_proxy_components
    cp power_proxy/components/* /usr/bin/power_proxy_components/
    # Deploy telegram components
    mkdir -p /usr/bin/telegram_components/commands
    cp telegram/components/*.sh /usr/bin/telegram_components/
    cp telegram/components/commands/*.sh /usr/bin/telegram_components/commands/
    # Deploy config_sync components
    mkdir -p /usr/bin/config_sync_components
    cp config_sync/components/*.sh /usr/bin/config_sync_components/

    cp power_proxy/game_wake_listener.sh /usr/bin/game_wake_listener.sh
    cp power_proxy/guest_wake_listener.sh /usr/bin/guest_wake_listener.sh
    cp telegram/notify_homelab.sh /usr/bin/homelab_notify.sh
    cp config_sync/homelab_config_sync.sh /usr/bin/homelab_config_sync.sh
    cp telegram/maintenance_homelab.sh /usr/bin/homelab_maintenance

    chmod +x /usr/bin/telegram_bot_daemon.sh
    chmod +x /usr/bin/power_proxy_daemon.sh
    chmod +x /usr/bin/game_wake_listener.sh
    chmod +x /usr/bin/guest_wake_listener.sh
    chmod +x /usr/bin/homelab_notify.sh
    chmod +x /usr/bin/homelab_config_sync.sh
    chmod +x /usr/bin/homelab_maintenance

    echo "Scripts installed to /usr/bin/."
}
