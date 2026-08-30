#!/bin/sh

install_scripts() {
    cp telegram_bot_daemon.sh /usr/bin/telegram_bot_daemon.sh
    cp power_proxy_daemon.sh /usr/bin/power_proxy_daemon.sh
    cp game_wake_listener.sh /usr/bin/game_wake_listener.sh
    cp guest_wake_listener.sh /usr/bin/guest_wake_listener.sh
    cp homelab_notify.sh /usr/bin/homelab_notify.sh
    cp homelab_config_sync.sh /usr/bin/homelab_config_sync.sh
    cp homelab_maintenance.sh /usr/bin/homelab_maintenance

    chmod +x /usr/bin/telegram_bot_daemon.sh
    chmod +x /usr/bin/power_proxy_daemon.sh
    chmod +x /usr/bin/game_wake_listener.sh
    chmod +x /usr/bin/guest_wake_listener.sh
    chmod +x /usr/bin/homelab_notify.sh
    chmod +x /usr/bin/homelab_config_sync.sh
    chmod +x /usr/bin/homelab_maintenance

    echo "Scripts installed to /usr/bin/."
}
