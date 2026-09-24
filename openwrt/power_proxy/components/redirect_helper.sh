#!/bin/sh

# Apply Nat Redirect rules dynamically
apply_redirects() {
    echo "Host is offline. Activating dynamic HTTP/HTTPS proxy redirects..."

    if command -v nft >/dev/null 2>&1; then
        # Modern OpenWrt (nftables)
        # We create a dedicated nat table 'power_homelab_nat' which can be instantly deleted
        nft delete table inet power_homelab_nat 2>/dev/null
        nft create table inet power_homelab_nat
        nft add chain inet power_homelab_nat dstnat "{ type nat hook prerouting priority dstnat - 5 ; policy accept ; }"

        # Add HTTP Redirects (to port 8080)
        for port in $(echo "$HTTP_REDIRECT_PORTS" | tr ',' ' '); do
            nft add rule inet power_homelab_nat dstnat ip daddr "$HOST_IP" tcp dport "$port" redirect to :8080
        done

        # Add HTTPS Redirects (to port 8443)
        for port in $(echo "$HTTPS_REDIRECT_PORTS" | tr ',' ' '); do
            nft add rule inet power_homelab_nat dstnat ip daddr "$HOST_IP" tcp dport "$port" redirect to :8443
        done
    else
        # Older OpenWrt (iptables)
        # Flush any existing rules first to prevent duplicates
        remove_redirects

        for port in $(echo "$HTTP_REDIRECT_PORTS" | tr ',' ' '); do
            iptables -t nat -I PREROUTING -p tcp -d "$HOST_IP" --dport "$port" -j REDIRECT --to-ports 8080
        done
        for port in $(echo "$HTTPS_REDIRECT_PORTS" | tr ',' ' '); do
            iptables -t nat -I PREROUTING -p tcp -d "$HOST_IP" --dport "$port" -j REDIRECT --to-ports 8443
        done
    fi
}

# Remove Nat Redirect rules dynamically
remove_redirects() {
    echo "Host is online. Deactivating HTTP/HTTPS proxy redirects..."

    if command -v nft >/dev/null 2>&1; then
        # Modern OpenWrt (nftables)
        nft delete table inet power_homelab_nat 2>/dev/null
    else
        # Older OpenWrt (iptables)
        for port in $(echo "$HTTP_REDIRECT_PORTS" | tr ',' ' '); do
            while iptables -t nat -D PREROUTING -p tcp -d "$HOST_IP" --dport "$port" -j REDIRECT --to-ports 8080 2>/dev/null; do :; done
        done
        for port in $(echo "$HTTPS_REDIRECT_PORTS" | tr ',' ' '); do
            while iptables -t nat -D PREROUTING -p tcp -d "$HOST_IP" --dport "$port" -j REDIRECT --to-ports 8443 2>/dev/null; do :; done
        done
    fi
}
