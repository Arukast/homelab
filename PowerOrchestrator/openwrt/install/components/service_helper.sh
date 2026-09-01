#!/bin/sh

install_services() {
    cp /tmp/openwrt_powerorchestractor/telegram/telegram_bot.init /etc/init.d/telegram_bot
    cp /tmp/openwrt_powerorchestractor/power_proxy/power_proxy.init /etc/init.d/power_proxy

    chmod +x /etc/init.d/telegram_bot
    chmod +x /etc/init.d/power_proxy

    # Enable services to run on boot
    /etc/init.d/power_proxy enable
    /etc/init.d/telegram_bot enable

    # Start services
    /etc/init.d/power_proxy start
    /etc/init.d/telegram_bot start
}
