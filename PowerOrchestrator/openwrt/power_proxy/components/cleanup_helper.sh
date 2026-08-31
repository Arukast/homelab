#!/bin/sh

# Clean up rules and listeners on exit (SIGTERM/SIGINT)
cleanup() {
    echo "Terminating power proxy. Restoring network defaults..."
    remove_redirects
    stop_game_listeners
    stop_guest_listeners
    # Remove permanent static ARP (return to dynamic ARP)
    ip neigh del "$HOST_IP" dev "$IFACE" 2>/dev/null
    rm -f "/var/run/power_proxy_daemon.pid" 2>/dev/null
    exit 0
}
