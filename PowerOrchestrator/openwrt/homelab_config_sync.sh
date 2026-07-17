#!/bin/sh
# =============================================================================
# OpenWrt Homelab Configuration Synchronization & SSH Trust Verification
# File: /usr/bin/homelab_config_sync.sh
# =============================================================================

CONF="/etc/homelab_power.conf"
if [ ! -f "$CONF" ]; then
    echo "ERROR: Local configuration file $CONF not found." >&2
    exit 1
fi

# Load config variables locally
. "$CONF"

if [ -z "$HOST_IP" ]; then
    echo "ERROR: HOST_IP is not configured in $CONF" >&2
    exit 1
fi

SSH_KEY_PATH="${SSH_KEY_PATH:-/etc/dropbear/id_dropbear}"

echo "===================================================="
echo "Homelab Power Orchestrator Configuration Sync Tool"
echo "===================================================="

# 1. Check local Dropbear private key permissions
if [ -f "$SSH_KEY_PATH" ]; then
    perms=$(ls -ld "$SSH_KEY_PATH" | cut -c 2-4)
    if [ "$perms" != "rw-" ] && [ "$perms" != "r--" ]; then
        echo "Warning: SSH key permissions are too open. Setting to 600..."
        chmod 600 "$SSH_KEY_PATH" 2>/dev/null
    fi
else
    echo "Error: SSH key not found at $SSH_KEY_PATH." >&2
    exit 1
fi

# 2. Verify passwordless SSH connection & SSH Wrapper status
echo "Verifying SSH connection and security wrapper on Proxmox..."
SSH_OPTS="-o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=5"

# Test simple connectivity with wrapper-allowed echo OK
SSH_TEST=$(ssh -i "$SSH_KEY_PATH" $SSH_OPTS -y -K 3 root@$HOST_IP "echo OK" 2>/dev/null)
if [ "$SSH_TEST" != "OK" ]; then
    echo "Error: Cannot establish passwordless SSH trust. SSH command failed." >&2
    echo "Please ensure the public key is added to Proxmox /root/.ssh/authorized_keys." >&2
    exit 1
fi
echo "Passwordless SSH trust verified."

# Test if wrapper is active by running unauthorized command
SSH_BLOCK_TEST=$(ssh -i "$SSH_KEY_PATH" $SSH_OPTS -y -K 3 root@$HOST_IP "uname" 2>&1)
if echo "$SSH_BLOCK_TEST" | grep -iq "Access Denied"; then
    echo "SSH Command Wrapper detected and active on Proxmox."
    WRAPPER_ACTIVE=1
else
    echo "WARNING: SSH command restrictions NOT detected on Proxmox!"
    echo "The host executed 'uname' without wrapper blocking. This is a security risk."
    echo "Please prepend the command wrapper inside Proxmox /root/.ssh/authorized_keys."
    WRAPPER_ACTIVE=0
fi

# 3. Calculate dynamic Router IP facing Proxmox
ROUTER_IP=$(ip route get "$HOST_IP" 2>/dev/null | grep -oE "src [0-9.]+" | awk '{print $2}')
if [ -z "$ROUTER_IP" ]; then
    # Fallback if route fails
    ROUTER_IP=$(ip addr show dev br-lan 2>/dev/null | grep -oE 'inet [0-9.]+' | awk '{print $2}')
fi

if [ -z "$ROUTER_IP" ]; then
    echo "Error: Could not determine router local IP." >&2
    exit 1
fi
echo "Determined Router IP facing Proxmox: $ROUTER_IP"

# 4. Generate sanitized configuration file
TEMP_CONF="/tmp/homelab_power_pve_sync.conf"
echo "# =============================================================================" > "$TEMP_CONF"
echo "# Proxmox VE Idle Monitor Configuration (Auto-Synchronized from OpenWrt)" >> "$TEMP_CONF"
echo "# Generated on: $(date)" >> "$TEMP_CONF"
echo "# =============================================================================" >> "$TEMP_CONF"
echo "" >> "$TEMP_CONF"

# Filter and extract variables from /etc/homelab_power.conf
# This strictly keeps only PVE-relevant parameters and avoids leaking secrets
for var in CPU_THRESHOLD SCALE_CPU_THRESHOLD_BY_CORES NET_INTERFACE NET_THRESHOLD_KBPS MONITORED_PORTS \
           LXC_SUSPEND_METHOD VM_SUSPEND_METHOD PROTECTED_PROCESSES \
           GUEST_ORCHESTRATION_MAP ACTIVE_TIME_WINDOWS GUEST_NAME_MAP GUEST_PORT_MAP \
           LOG_FILE ENABLE_SYSLOG \
           MONITOR_CPU_THRESHOLD_PCT MONITOR_RAM_THRESHOLD_PCT MONITOR_DISK_THRESHOLD_PCT \
           MONITOR_DISK_PATHS MONITOR_SERVICES MONITOR_ZFS_POOLS MONITOR_CRITICAL_GUESTS \
           MONITOR_COOLDOWN_SEC; do
    # Extract line from config
    val=$(grep -E "^${var}=" "$CONF" | head -n 1)
    if [ -n "$val" ]; then
        echo "$val" >> "$TEMP_CONF"
    fi
done

# Write the dynamic notification url pointing back to OpenWrt uhttpd CGI endpoint
echo "NOTIFICATION_URL=\"http://${ROUTER_IP}:8080/cgi-bin/notify\"" >> "$TEMP_CONF"

echo "Sanitized configuration generated at $TEMP_CONF."

# 5. Push the configuration to Proxmox
echo "Deploying configuration to Proxmox..."
if [ "$WRAPPER_ACTIVE" -eq 1 ]; then
    # Push via cat redirect permitted by wrapper
    ssh -i "$SSH_KEY_PATH" $SSH_OPTS -y -K 3 root@$HOST_IP "cat > /etc/homelab_power.conf" < "$TEMP_CONF"
else
    # Fallback to standard scp if wrapper is not configured yet
    scp -i "$SSH_KEY_PATH" $SSH_OPTS "$TEMP_CONF" root@$HOST_IP:/etc/homelab_power.conf >/dev/null
fi

if [ $? -eq 0 ]; then
    echo "Configuration successfully synchronized to Proxmox /etc/homelab_power.conf."
    # Trigger systemd reload/restart on PVE if timer is active
    ssh -i "$SSH_KEY_PATH" $SSH_OPTS -y -K 3 root@$HOST_IP "systemctl restart proxmox_idle_monitor.timer" >/dev/null 2>&1 || true
else
    echo "Error: Failed to write configuration to Proxmox." >&2
    exit 1
fi

rm -f "$TEMP_CONF"
echo "Sync complete."
exit 0
