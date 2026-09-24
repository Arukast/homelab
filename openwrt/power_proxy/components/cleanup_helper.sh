#!/bin/sh

# Clean up rules and listeners on exit (SIGTERM/SIGINT)
cleanup_main() {
    echo "Terminating power proxy. Restoring network defaults..."
    remove_redirects
    stop_game_listeners
    stop_guest_listeners
    # Remove permanent static ARP (return to dynamic ARP)
    ip neigh del "$HOST_IP" dev "$IFACE" 2>/dev/null
    rm -f "/var/run/power_proxy_daemon.pid" 2>/dev/null
    exit 0
}

# Clean up netcat on signal
cleanup_game() {
    echo "Stopping game wake listener..."
    [ -n "$NC_PID" ] && kill "$NC_PID" 2>/dev/null
    exit 0
}

cleanup_guest() {
    echo "Cleaning up IP alias $GUEST_IP/32 and port listeners..."
    [ -n "$NC_PID" ] && kill "$NC_PID" 2>/dev/null
    ip addr del "${GUEST_IP}/32" dev "$IFACE" >/dev/null 2>&1 || true
    exit 0
}
