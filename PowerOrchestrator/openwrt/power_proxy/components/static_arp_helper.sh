#!/bin/sh

# Apply Static ARP to prevent IP drops while sleeping
apply_static_arp() {
    echo "Applying permanent static ARP: $HOST_IP -> $HOST_MAC on $IFACE..."
    ip neigh replace "$HOST_IP" lladdr "$HOST_MAC" dev "$IFACE" nud permanent
}
