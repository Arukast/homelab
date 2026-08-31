#!/bin/sh

# Helper to send notifications
notify() {
    local msg="$1"
    echo "[Power Proxy] $msg"

    # Centralized dispatch via local helper
    /usr/bin/homelab_notify.sh "$msg" &
}
