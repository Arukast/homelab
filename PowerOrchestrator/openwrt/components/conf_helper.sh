#!/bin/sh

read_conf() {
    local CONF=$1
    if [ ! -f "$CONF" ]; then
        echo "ERROR: Configuration file $CONF not found." >&2
        exit 1
    fi
    # Load config
    . "$CONF"
}

read_optional_conf() {
    local CONF=$1
    if [ -f "$CONF" ]; then
        . "$CONF"
    fi
}

check_ip() {
    local CONF=$1
    if [ -z "$HOST_IP" ]; then
        echo "ERROR: HOST_IP is not configured in $CONF" >&2
        exit 1
    fi
}
