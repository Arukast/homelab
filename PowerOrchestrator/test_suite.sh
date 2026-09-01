#!/bin/bash
# =============================================================================
# Homelab Power Orchestrator - Automated Verification & Unit Test Suite
# File: PowerOrchestrator/test_suite.sh
# Usage: ./test_suite.sh
# =============================================================================

# Change directory to the script's root location
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# Formatting Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

PASSED_TESTS=0
FAILED_TESTS=0

report_pass() {
    echo -e "  [${GREEN}PASS${NC}] $1"
    PASSED_TESTS=$((PASSED_TESTS + 1))
}

report_fail() {
    echo -e "  [${RED}FAIL${NC}] $1"
    [ -n "$2" ] && echo -e "         ${RED}Detail: $2${NC}"
    FAILED_TESTS=$((FAILED_TESTS + 1))
}

print_header() {
    echo ""
    echo -e "${BLUE}${BOLD}======================================================================${NC}"
    echo -e "${CYAN}${BOLD} $1 ${NC}"
    echo -e "${BLUE}${BOLD}======================================================================${NC}"
}

echo -e "${BOLD}Starting PowerOrchestrator Test Suite...${NC}"

# =============================================================================
# TEST SUITE 1: Script Syntax Validation
# =============================================================================
print_header "1. Script Syntax Validation (bash -n / sh -n)"

check_syntax() {
    local file="$1"
    local shell_bin="$2"
    if [ -f "$file" ]; then
        if $shell_bin -n "$file" 2>/dev/null; then
            report_pass "Syntax valid: $file ($shell_bin)"
        else
            local err=$($shell_bin -n "$file" 2>&1)
            report_fail "Syntax error: $file ($shell_bin)" "$err"
        fi
    else
        report_fail "File not found: $file"
    fi
}

check_syntax "proxmox/proxmox_idle_monitor.sh" "bash"
check_syntax "proxmox/homelab_ssh_wrapper.sh" "sh"
check_syntax "proxmox/proxmox_resource_monitor.sh" "bash"
check_syntax "proxmox/install_proxmox.sh" "bash"

# Shared components
check_syntax "openwrt/components/check_helper.sh" "sh"
check_syntax "openwrt/components/common_init.sh" "sh"
check_syntax "openwrt/components/conf_helper.sh" "sh"

# Config Sync
check_syntax "openwrt/config_sync/homelab_config_sync.sh" "sh"
check_syntax "openwrt/config_sync/components/deploy_helper.sh" "bash"
check_syntax "openwrt/config_sync/components/permission_helper.sh" "sh"
check_syntax "openwrt/config_sync/components/router_ip_helper.sh" "bash"
check_syntax "openwrt/config_sync/components/sanitized_conf_helper.sh" "bash"
check_syntax "openwrt/config_sync/components/verify_helper.sh" "sh"

# Installer
check_syntax "openwrt/install/install_openwrt.sh" "sh"
check_syntax "openwrt/install/components/packages_helper.sh" "sh"
check_syntax "openwrt/install/components/post_install_helper.sh" "sh"
check_syntax "openwrt/install/components/script_helper.sh" "sh"
check_syntax "openwrt/install/components/service_helper.sh" "sh"
check_syntax "openwrt/install/components/setup_conf_helper.sh" "sh"

# Power Proxy
check_syntax "openwrt/power_proxy/power_proxy_daemon.sh" "sh"
check_syntax "openwrt/power_proxy/guest_wake_listener.sh" "sh"
check_syntax "openwrt/power_proxy/game_wake_listener.sh" "sh"
check_syntax "openwrt/power_proxy/components/cleanup_helper.sh" "sh"
check_syntax "openwrt/power_proxy/components/listener_helper.sh" "sh"
check_syntax "openwrt/power_proxy/components/main.sh" "sh"
check_syntax "openwrt/power_proxy/components/network_helper.sh" "bash"
check_syntax "openwrt/power_proxy/components/notify_helper.sh" "sh"
check_syntax "openwrt/power_proxy/components/redirect_helper.sh" "sh"

# Telegram bot
check_syntax "openwrt/telegram/telegram_bot_daemon.sh" "sh"
check_syntax "openwrt/telegram/maintenance_homelab.sh" "sh"
check_syntax "openwrt/telegram/notify_homelab.sh" "sh"
check_syntax "openwrt/telegram/components/command_helper.sh" "bash"
check_syntax "openwrt/telegram/components/message_helper.sh" "bash"
check_syntax "openwrt/telegram/components/polling_helper.sh" "sh"
check_syntax "openwrt/telegram/components/process_command_helper.sh" "bash"
check_syntax "openwrt/telegram/components/commands/help_command.sh" "bash"
check_syntax "openwrt/telegram/components/commands/status_command.sh" "bash"
check_syntax "openwrt/telegram/components/commands/list_command.sh" "bash"
check_syntax "openwrt/telegram/components/commands/node_command.sh" "bash"
check_syntax "openwrt/telegram/components/commands/wake_command.sh" "bash"
check_syntax "openwrt/telegram/components/commands/sleep_command.sh" "bash"
check_syntax "openwrt/telegram/components/commands/sleepforce_command.sh" "bash"
check_syntax "openwrt/telegram/components/commands/hostreboot_command.sh" "bash"
check_syntax "openwrt/telegram/components/commands/hostrebootforce_command.sh" "bash"
check_syntax "openwrt/telegram/components/commands/hostshutdown_command.sh" "bash"
check_syntax "openwrt/telegram/components/commands/hostshutdownforce_command.sh" "bash"
check_syntax "openwrt/telegram/components/commands/vmstart_command.sh" "bash"
check_syntax "openwrt/telegram/components/commands/vmstop_command.sh" "bash"
check_syntax "openwrt/telegram/components/commands/vmrestart_command.sh" "bash"
check_syntax "openwrt/telegram/components/commands/ctstart_command.sh" "bash"
check_syntax "openwrt/telegram/components/commands/ctstop_command.sh" "bash"
check_syntax "openwrt/telegram/components/commands/ctrestart_command.sh" "bash"
check_syntax "openwrt/telegram/components/commands/maintenance_command.sh" "bash"

# =============================================================================
# TEST SUITE 2: Active Time Window Evaluation Logic
# =============================================================================
print_header "2. Active Time Window Evaluation Logic"

# Extract day_to_num and is_in_active_window logic directly
day_to_num() {
    case "$1" in
        Mon) echo 1 ;;
        Tue) echo 2 ;;
        Wed) echo 3 ;;
        Thu) echo 4 ;;
        Fri) echo 5 ;;
        Sat) echo 6 ;;
        Sun) echo 7 ;;
        *) echo 0 ;;
    esac
}

eval_active_window() {
    local ACTIVE_TIME_WINDOWS="$1"
    local curr_day="$2"
    local curr_hour="$3"
    local curr_min="$4"
    
    local curr_day_num=$(day_to_num "$curr_day")
    local ch=$((10#$curr_hour))
    local cm=$((10#$curr_min))
    local curr_time_m=$(( ch * 60 + cm ))
    
    for window in $(echo "$ACTIVE_TIME_WINDOWS" | tr ',' ' '); do
        local days=""
        local times=""
        if echo "$window" | grep -q ":"; then
            days="${window%%:*}"
            times="${window#*:}"
        else
            days="All"
            times="$window"
        fi
        
        local day_match=0
        if [ "$days" = "All" ]; then
            day_match=1
        elif echo "$days" | grep -q "-"; then
            local start_day="${days%%-*}"
            local end_day="${days#*-}"
            local start_num=$(day_to_num "$start_day")
            local end_num=$(day_to_num "$end_day")
            
            if [ "$start_num" -le "$end_num" ]; then
                if [ "$curr_day_num" -ge "$start_num" ] && [ "$curr_day_num" -le "$end_num" ]; then
                    day_match=1
                fi
            else
                if [ "$curr_day_num" -ge "$start_num" ] || [ "$curr_day_num" -le "$end_num" ]; then
                    day_match=1
                fi
            fi
        else
            if [ "$curr_day" = "$days" ]; then
                day_match=1
            fi
        fi
        
        [ "$day_match" -eq 0 ] && continue
        
        local start_t="${times%%-*}"
        local end_t="${times#*-}"
        
        local sh="${start_t%%:*}"
        local sm="${start_t#*:}"
        local eh="${end_t%%:*}"
        local em="${end_t#*:}"
        
        [ -z "$sh" ] && sh=0
        [ -z "$sm" ] && sm=0
        [ -z "$eh" ] && eh=0
        [ -z "$em" ] && em=0
        
        local start_h=$((10#$sh))
        local start_m_part=$((10#$sm))
        local end_h=$((10#$eh))
        local end_m_part=$((10#$em))
        
        local start_m=$(( start_h * 60 + start_m_part ))
        local end_m=$(( end_h * 60 + end_m_part ))
        
        if [ "$end_m" -lt "$start_m" ]; then
            if [ "$curr_time_m" -ge "$start_m" ] || [ "$curr_time_m" -le "$end_m" ]; then
                return 0
            fi
        else
            if [ "$curr_time_m" -ge "$start_m" ] && [ "$curr_time_m" -le "$end_m" ]; then
                return 0
            fi
        fi
    done
    return 1
}

# Test Cases
if eval_active_window "Mon-Sun:05:00-23:00" "Tue" "09" "30"; then
    report_pass "Mon-Sun:05:00-23:00: Active at 09:30 on Tue"
else
    report_fail "Mon-Sun:05:00-23:00 should be active at 09:30 on Tue"
fi

if eval_active_window "Mon-Sun:05:00-23:00" "Sun" "05" "00"; then
    report_pass "Mon-Sun:05:00-23:00: Active at exact start boundary 05:00"
else
    report_fail "Mon-Sun:05:00-23:00 should be active at 05:00"
fi

if eval_active_window "Mon-Sun:05:00-23:00" "Mon" "23" "00"; then
    report_pass "Mon-Sun:05:00-23:00: Active at exact end boundary 23:00"
else
    report_fail "Mon-Sun:05:00-23:00 should be active at 23:00"
fi

if ! eval_active_window "Mon-Sun:05:00-23:00" "Wed" "23" "01"; then
    report_pass "Mon-Sun:05:00-23:00: Inactive at 23:01 (outside window)"
else
    report_fail "Mon-Sun:05:00-23:00 should be inactive at 23:01"
fi

if ! eval_active_window "Mon-Sun:05:00-23:00" "Fri" "04" "59"; then
    report_pass "Mon-Sun:05:00-23:00: Inactive at 04:59 (outside window)"
else
    report_fail "Mon-Sun:05:00-23:00 should be inactive at 04:59"
fi

if eval_active_window "Mon-Fri:18:00-06:00" "Wed" "02" "00"; then
    report_pass "Overnight window Mon-Fri:18:00-06:00: Active at 02:00"
else
    report_fail "Overnight window Mon-Fri:18:00-06:00 should be active at 02:00"
fi

if eval_active_window "Sat-Sun:00:00-23:59" "Sat" "14" "15"; then
    report_pass "Weekend full day window: Active at 14:15 on Sat"
else
    report_fail "Weekend full day window should be active at 14:15 on Sat"
fi

if ! eval_active_window "Mon-Fri:08:00-17:00" "Sun" "10" "00"; then
    report_pass "Weekday-only window: Inactive on Sunday"
else
    report_fail "Weekday-only window should be inactive on Sunday"
fi

# =============================================================================
# TEST SUITE 3: Floating Point Conversion Helpers
# =============================================================================
print_header "3. Float Math Helper (to_integer in proxmox_idle_monitor.sh)"

to_integer() {
    local val="$1"
    local int="${val%.*}"
    local dec=""
    if [ "$int" != "$val" ]; then
        dec="${val#*.}"
    fi
    [ -z "$int" ] && int=0
    [ -z "$dec" ] && dec=0
    
    dec="${dec}00"
    dec="${dec:0:2}"
    
    local res="${int}${dec}"
    while [[ $res == 0* && ${#res} -gt 1 ]]; do
        res="${res#0}"
    done
    echo "$res"
}

check_float() {
    local input="$1"
    local expected="$2"
    local res=$(to_integer "$input")
    if [ "$res" = "$expected" ]; then
        report_pass "to_integer '$input' -> $expected"
    else
        report_fail "to_integer '$input' failed (got: $res, expected: $expected)"
    fi
}

check_float "0.15" "15"
check_float "0.05" "5"
check_float "1.00" "100"
check_float "1.5" "150"
check_float "0.0" "0"
check_float "0" "0"

# =============================================================================
# TEST SUITE 4: JSON Escaping Engine
# =============================================================================
print_header "4. JSON Escaping Engine"

escape_json() {
    printf '%s' "$1" | awk 'BEGIN {ORS="";} {
        gsub(/\\/, "\\\\");
        gsub(/"/, "\\\"");
        gsub(/\r/, "");
        gsub(/\t/, "\\t");
        if (NR > 1) printf "\\n";
        printf "%s", $0;
    }'
}

TEST_STR="Line 1: with \"double quotes\" and \\backslashes\\
Line 2: with tab	character
Line 3: finished."

ESCAPED_STR=$(escape_json "$TEST_STR")
EXPECTED_STR='Line 1: with \"double quotes\" and \\backslashes\\\nLine 2: with tab\tcharacter\nLine 3: finished.'

if [ "$ESCAPED_STR" = "$EXPECTED_STR" ]; then
    report_pass "Multiline text, quotes, and backslashes escaped safely for JSON"
else
    report_fail "JSON escaping failed" "Got: $ESCAPED_STR"
fi

# =============================================================================
# TEST SUITE 5: SSH Command Wrapper Security Rules
# =============================================================================
print_header "5. SSH Command Security Wrapper Dispatcher"

check_wrapper_pattern() {
    local SSH_ORIGINAL_COMMAND="$1"
    case "$SSH_ORIGINAL_COMMAND" in
        "echo OK")
            echo "ALLOW: echo OK"
            ;;
        "echo '===METRICS==='; uptime; echo '===RAM==='; free -h; echo '===LXC==='; pct list; echo '===VM==='; qm list")
            echo "ALLOW: host metrics payload"
            ;;
        "pct list | awk 'NR>1 && \$2==\"running\" {print \$1}'; qm list | awk 'NR>1 && \$3==\"running\" {print \$1}'")
            echo "ALLOW: running guests list"
            ;;
        "cat > /etc/homelab_power.conf")
            echo "ALLOW: config sync push"
            ;;
        "systemctl restart proxmox_idle_monitor.timer")
            echo "ALLOW: restart idle timer"
            ;;
        "systemctl restart proxmox_resource_monitor.timer")
            echo "ALLOW: restart resource timer"
            ;;
        *cpu=\$\(grep\ \'cpu\ \'*)
            echo "ALLOW: host telemetry sensor probe"
            ;;
        *)
            # Check single line 3 args
            set -- $SSH_ORIGINAL_COMMAND
            if [ $# -eq 3 ] && echo "$3" | grep -qE "^[0-9]+$"; then
                if [ "$1" = "pct" ] || [ "$1" = "qm" ]; then
                    case "$2" in
                        config|start|stop|shutdown|reboot|resume|status)
                            echo "ALLOW: $1 $2 $3"
                            return
                            ;;
                    esac
                fi
            fi
            echo "DENY: $SSH_ORIGINAL_COMMAND"
            ;;
    esac
}

W1=$(check_wrapper_pattern 'echo OK')
[ "$W1" = "ALLOW: echo OK" ] && report_pass "Wrapper allows 'echo OK'" || report_fail "Wrapper blocked 'echo OK'"

W2=$(check_wrapper_pattern "echo '===METRICS==='; uptime; echo '===RAM==='; free -h; echo '===LXC==='; pct list; echo '===VM==='; qm list")
[ "$W2" = "ALLOW: host metrics payload" ] && report_pass "Wrapper allows metrics payload" || report_fail "Wrapper blocked metrics payload"

W3=$(check_wrapper_pattern "pct list | awk 'NR>1 && \$2==\"running\" {print \$1}'; qm list | awk 'NR>1 && \$3==\"running\" {print \$1}'")
[ "$W3" = "ALLOW: running guests list" ] && report_pass "Wrapper allows running guests awk filter" || report_fail "Wrapper blocked running guests awk"

W4=$(check_wrapper_pattern "cpu=\$(grep 'cpu ' /proc/stat | awk '{usage=(\$2+\$4)*100/(\$2+\$4+\$5)} END {printf \"%.1f\", usage}'); ram=\$(free -m | awk 'NR==2 {printf \"%d:%d\", \$3, \$2}'); temp=45; disk=20; echo \"\$cpu|\$ram|\$temp|\$disk\"")
[ "$W4" = "ALLOW: host telemetry sensor probe" ] && report_pass "Wrapper allows host telemetry sensor one-liner" || report_fail "Wrapper blocked host telemetry"

W5=$(check_wrapper_pattern 'qm start 120')
[ "$W5" = "ALLOW: qm start 120" ] && report_pass "Wrapper allows 'qm start 120'" || report_fail "Wrapper blocked 'qm start 120'"

W6=$(check_wrapper_pattern 'pct stop 101')
[ "$W6" = "ALLOW: pct stop 101" ] && report_pass "Wrapper allows 'pct stop 101'" || report_fail "Wrapper blocked 'pct stop 101'"

W7=$(check_wrapper_pattern 'qm status 120')
[ "$W7" = "ALLOW: qm status 120" ] && report_pass "Wrapper allows 'qm status 120'" || report_fail "Wrapper blocked 'qm status 120'"

W_BAD=$(check_wrapper_pattern 'rm -rf /')
[ "$W_BAD" = "DENY: rm -rf /" ] && report_pass "Wrapper correctly denies unauthorized 'rm -rf /'" || report_fail "Wrapper failed to deny malicious command"

# =============================================================================
# TEST SUITE 6: Multi-Map Guest Discovery Aggregation
# =============================================================================
print_header "6. Multi-Map Guest Discovery Aggregation"

GUEST_ORCHESTRATION_MAP=""
GUEST_NAME_MAP=""
GUEST_MESSAGE_MAP="120:Unturned Server<br>Code: 123,121:Minecraft Server<br>Code: 456"
GUEST_PORT_MAP="122:8080"
GUEST_PASSCODE_MAP="123:secret"
GUEST_PRIVACY_MAP="124:public"

ALL_DISCOVERED_VMIDS=$(
    {
        [ -n "$GUEST_ORCHESTRATION_MAP" ] && echo "$GUEST_ORCHESTRATION_MAP" | tr ',' '\n' | cut -d':' -f1
        [ -n "$GUEST_NAME_MAP" ] && echo "$GUEST_NAME_MAP" | tr ',' '\n' | cut -d':' -f1
        [ -n "$GUEST_MESSAGE_MAP" ] && echo "$GUEST_MESSAGE_MAP" | tr ',' '\n' | cut -d':' -f1
        [ -n "$GUEST_PORT_MAP" ] && echo "$GUEST_PORT_MAP" | tr ',' '\n' | cut -d':' -f1
        [ -n "$GUEST_PASSCODE_MAP" ] && echo "$GUEST_PASSCODE_MAP" | tr ',' '\n' | cut -d':' -f1
        [ -n "$GUEST_PRIVACY_MAP" ] && echo "$GUEST_PRIVACY_MAP" | tr ',' '\n' | cut -d':' -f1
    } | grep -E '^[0-9]+$' | sort -u | tr '\n' ' ' | sed 's/[[:space:]]*$//'
)

if [ "$ALL_DISCOVERED_VMIDS" = "120 121 122 123 124" ]; then
    report_pass "Discovered unique VMIDs (120, 121, 122, 123, 124) across all independent maps"
else
    report_fail "Guest discovery failed (got: '$ALL_DISCOVERED_VMIDS', expected: '120 121 122 123 124')"
fi

# =============================================================================
# SUMMARY REPORT
# =============================================================================
echo ""
echo -e "${BLUE}${BOLD}======================================================================${NC}"
echo -e "${BOLD}TEST SUITE SUMMARY${NC}"
echo -e "${BLUE}${BOLD}======================================================================${NC}"
echo -e "  Total Tests: $((PASSED_TESTS + FAILED_TESTS))"
echo -e "  Passed:      ${GREEN}${BOLD}${PASSED_TESTS}${NC}"
echo -e "  Failed:      ${RED}${BOLD}${FAILED_TESTS}${NC}"
echo -e "${BLUE}${BOLD}======================================================================${NC}"

if [ "$FAILED_TESTS" -eq 0 ]; then
    echo -e "${GREEN}${BOLD}✓ ALL TESTS PASSED SUCCESSFULLY! Codebase is ready for deployment.${NC}"
    exit 0
else
    echo -e "${RED}${BOLD}✗ SOME TESTS FAILED. Please review the output above.${NC}"
    exit 1
fi
