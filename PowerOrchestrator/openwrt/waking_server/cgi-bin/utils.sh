# =============================================================================
# OpenWrt Waking Server CGI Common Utilities
# File: /www_waking/cgi-bin/utils.sh
# =============================================================================

# --- Native IP CIDR Subnet Match Helpers ---
ip_to_int() {
    local o1 o2 o3 o4
    IFS=. read -r o1 o2 o3 o4 <<EOF
$1
EOF
    echo "$(( (o1 << 24) + (o2 << 16) + (o3 << 8) + o4 ))"
}

ip4_in_subnet() {
    local ip="$1"
    local subnet="$2"
    local sub_ip="${subnet%/*}"
    local mask=""
    if [ "$sub_ip" != "$subnet" ]; then
        mask="${subnet#*/}"
    fi
    [ -z "$mask" ] && mask=32
    
    local ip_int=$(ip_to_int "$ip")
    local sub_int=$(ip_to_int "$sub_ip")
    
    local mask_int=0
    if [ "$mask" -eq 0 ]; then
        mask_int=0
    else
        mask_int=$(( 0xFFFFFFFF << (32 - mask) ))
    fi
    
    local result=$(( (ip_int & mask_int) == (sub_int & mask_int) ))
    return $(( ! result ))
}

normalize_ip6() {
    local ip="$1"
    if [ "${ip#*::}" != "$ip" ]; then
        local tmp="$ip"
        local num_colons=0
        while [ "${tmp#*:}" != "$tmp" ]; do
            num_colons=$((num_colons + 1))
            tmp="${tmp#*:}"
        done
        local missing=$((8 - num_colons))
        local replacement=""
        while [ "$missing" -gt 0 ]; do
            replacement="${replacement}:0"
            missing=$((missing - 1))
        done
        replacement="${replacement}:"
        ip="${ip%%::*}${replacement}${ip#*::}"
    fi
    IFS=: read -r s1 s2 s3 s4 s5 s6 s7 s8 <<EOF
$ip
EOF
    printf "%04x:%04x:%04x:%04x:%04x:%04x:%04x:%04x\n" \
        "0x${s1:-0}" "0x${s2:-0}" "0x${s3:-0}" "0x${s4:-0}" \
        "0x${s5:-0}" "0x${s6:-0}" "0x${s7:-0}" "0x${s8:-0}" 2>/dev/null
}

ip6_in_subnet() {
    local ip="$1"
    local subnet="$2"
    local sub_ip="${subnet%/*}"
    local mask=""
    if [ "$sub_ip" != "$subnet" ]; then
        mask="${subnet#*/}"
    fi
    [ -z "$mask" ] && mask=128
    
    local ip_norm=$(normalize_ip6 "$ip")
    local sub_norm=$(normalize_ip6 "$sub_ip")
    
    IFS=: read -r i1 i2 i3 i4 i5 i6 i7 i8 <<EOF
$ip_norm
EOF
    IFS=: read -r s1 s2 s3 s4 s5 s6 s7 s8 <<EOF
$sub_norm
EOF
    
    local bits_left=$mask
    for g in 1 2 3 4 5 6 7 8; do
        eval "local ip_val=\$i$g"
        eval "local sub_val=\$s$g"
        
        ip_val=$((0x$ip_val))
        sub_val=$((0x$sub_val))
        
        if [ "$bits_left" -ge 16 ]; then
            if [ "$ip_val" -ne "$sub_val" ]; then
                return 1
            fi
            bits_left=$((bits_left - 16))
        elif [ "$bits_left" -gt 0 ]; then
            local mask_val=$(( 0xFFFF << (16 - bits_left) & 0xFFFF ))
            if [ "$((ip_val & mask_val))" -ne "$((sub_val & mask_val))" ]; then
                return 1
            fi
            bits_left=0
        else
            break
        fi
    done
    return 0
}

ip_in_subnet() {
    local ip="$1"
    local subnet="$2"
    
    if [ "${subnet#*:}" != "$subnet" ]; then
        if [ "${ip#*:}" = "$ip" ]; then
            return 1
        fi
        ip6_in_subnet "$ip" "$subnet"
    else
        if [ "${ip#*:}" != "$ip" ]; then
            return 1
        fi
        ip4_in_subnet "$ip" "$subnet"
    fi
}

# Robust Busybox-native URL decoder using AWK
url_decode() {
    echo "$1" | awk '
    BEGIN {
        for (i=0; i<256; i++) {
            char = sprintf("%c", i)
            hex = sprintf("%02x", i)
            hexcodes[hex] = char
            hexcodes[toupper(hex)] = char
        }
    }
    {
        gsub(/\+/, " ")
        while (match($0, /%[0-9A-Fa-f]{2}/)) {
            code = substr($0, RSTART+1, 2)
            $0 = substr($0, 1, RSTART-1) hexcodes[code] substr($0, RSTART+3)
        }
        print $0
    }'
}

# Helper to escape values for safe JSON transmission
escape_json() {
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

# --- Common Request Parsing & Security Helpers ---

# Extract client IP, respecting proxy headers
get_client_ip() {
    local client_ip="${REMOTE_ADDR:-127.0.0.1}"
    if [ -n "$HTTP_X_FORWARDED_FOR" ]; then
        client_ip=$(echo "$HTTP_X_FORWARDED_FOR" | cut -d',' -f1 | tr -d ' ')
    elif [ -n "$HTTP_X_REAL_IP" ]; then
        client_ip="$HTTP_X_REAL_IP"
    fi
    echo "$client_ip"
}

# Check if client IP is within private subnets
is_private_ip() {
    local ip="$1"
    local subnets="$2"
    [ -z "$subnets" ] && subnets="192.168.11.0/24,100.64.0.0/10,127.0.0.1/32"
    
    if [ "$ip" = "127.0.0.1" ] || [ "$ip" = "::1" ]; then
        return 0
    fi
    
    for range in $(echo "$subnets" | tr ',' ' '); do
        if ip_in_subnet "$ip" "$range"; then
            return 0
        fi
    done
    return 1
}

# Extract query string parameter by key
get_query_param() {
    local key="$1"
    echo "$QUERY_STRING" | tr '&' '\n' | grep -iE "^(${key})=" | cut -d'=' -f2- 2>/dev/null
}
