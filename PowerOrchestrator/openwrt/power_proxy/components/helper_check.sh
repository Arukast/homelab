#!/bin/sh

is_pid_running() {
    PIDFILE="/var/run/power_proxy_daemon.pid"
    if [ -f "$PIDFILE" ]; then
        PID=$(cat "$PIDFILE" 2>/dev/null)
        if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
            echo "ERROR: power_proxy_daemon.sh is already running with PID $PID." >&2
            exit 1
        fi
    fi
    echo "$$" > "$PIDFILE"
}

# Multi-stage Host Liveness Probe (ICMP ping + Dropbear SSH + WebUI curl fallback)
is_host_alive() {
    if ping -c 1 -W 1 "$HOST_IP" >/dev/null 2>&1; then
        return 0
    fi
    if $SSH_CMD "echo OK" >/dev/null 2>&1; then
        return 0
    fi
    if command -v curl >/dev/null 2>&1; then
        if curl -k -s --connect-timeout 1 "https://${HOST_IP}:8006" >/dev/null 2>&1 || \
           curl -s --connect-timeout 1 "http://${HOST_IP}:80" >/dev/null 2>&1; then
            return 0
        fi
    fi
    return 1
}
