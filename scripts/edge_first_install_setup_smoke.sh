#!/usr/bin/env bash
# edge_first_install_setup_smoke.sh - Smoke test for EDGE-SETUP-1 & EDGE-SETUP-2
#
# EDGE-SETUP-1 - Validates that after first install:
#   1. The pit crew dashboard is the ONLY service on port 8080
#   2. Visiting / redirects to /setup when not configured
#   3. /setup returns the "Pit Crew Dashboard Setup" page
#   4. Old provision server status page is NOT served
#   5. argus-dashboard is active/enabled, argus-provision is inactive/disabled
#
# EDGE-SETUP-2 - Validates self-healing:
#   6. install.sh has validate_and_recover() function
#   7. install.sh uses INSTALL_HAD_ERRORS flag for conditional troubleshooting
#   8. Troubleshooting section only shown on failure (not in success path)
#
# This script should be run on the edge device after install.sh completes.
# For source-level testing (without running services), checks are limited.
#
# Usage:
#   bash scripts/edge_first_install_setup_smoke.sh
#
# Exit non-zero on any failure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

FAIL=0
SOURCE_ONLY=false

log()  { echo "[edge-setup-smoke]  $*"; }
pass() { echo "[edge-setup-smoke]    PASS: $*"; }
fail() { echo "[edge-setup-smoke]    FAIL: $*"; FAIL=1; }
skip() { echo "[edge-setup-smoke]    SKIP: $*"; }

# Detect if we're running on the actual edge device or just source-checking
detect_environment() {
    if command -v systemctl >/dev/null 2>&1 && [[ -f /etc/systemd/system/argus-dashboard.service ]]; then
        log "Running on edge device with systemd services installed"
        SOURCE_ONLY=false
    else
        log "Running in source-only mode (no systemd services)"
        SOURCE_ONLY=true
    fi
}

# ── 1. Check process listening on port 8080 ──────────────────────────
check_port_8080() {
    log "Step 1: Check what's listening on port 8080"

    if $SOURCE_ONLY; then
        skip "Port check requires running services (source-only mode)"
        return
    fi

    # Get the process listening on 8080
    local listener
    listener=$(ss -lntp 2>/dev/null | grep ':8080 ' | head -1 || true)

    if [[ -z "$listener" ]]; then
        fail "Nothing listening on port 8080"
        return
    fi

    # Check if it's pit_crew_dashboard.py
    if echo "$listener" | grep -q 'pit_crew_dashboard.py\|python.*pit_crew'; then
        pass "pit_crew_dashboard.py is listening on port 8080"
    else
        # Get more details about what's listening
        local pid
        pid=$(echo "$listener" | grep -oP 'pid=\K\d+' || echo "")
        if [[ -n "$pid" ]]; then
            local cmdline
            cmdline=$(ps -p "$pid" -o args= 2>/dev/null || echo "unknown")
            if echo "$cmdline" | grep -q 'pit_crew_dashboard'; then
                pass "pit_crew_dashboard.py is listening on port 8080 (pid=$pid)"
            else
                fail "Port 8080 is NOT pit_crew_dashboard.py: $cmdline"
            fi
        else
            fail "Could not determine process on port 8080: $listener"
        fi
    fi
}

# ── 2. Check curl / returns setup redirect or page ───────────────────
check_root_redirect() {
    log "Step 2: Check GET / returns setup page when not configured"

    if $SOURCE_ONLY; then
        skip "HTTP check requires running services (source-only mode)"
        return
    fi

    # Curl root and follow redirects
    local response
    response=$(curl -sS -L --max-redirs 5 http://127.0.0.1:8080/ 2>&1 || true)

    if echo "$response" | grep -qi 'Pit Crew Dashboard Setup'; then
        pass "GET / shows 'Pit Crew Dashboard Setup' page"
    elif echo "$response" | grep -qi 'Pit Crew.*Login'; then
        # If already configured, login page is OK
        pass "GET / shows login page (already configured)"
    else
        fail "GET / does not show expected setup/login page"
        echo "Response preview: ${response:0:500}"
    fi
}

# ── 3. Check /setup returns setup page ───────────────────────────────
check_setup_route() {
    log "Step 3: Check GET /setup returns setup page"

    if $SOURCE_ONLY; then
        skip "HTTP check requires running services (source-only mode)"
        return
    fi

    local response
    response=$(curl -sS http://127.0.0.1:8080/setup 2>&1 || true)

    if echo "$response" | grep -qi 'Pit Crew Dashboard Setup'; then
        pass "GET /setup returns 'Pit Crew Dashboard Setup' page"
    elif echo "$response" | grep -qi 'redirect\|login'; then
        # If already configured, redirect to login is expected
        pass "GET /setup redirects (already configured)"
    else
        fail "GET /setup does not return expected page"
        echo "Response preview: ${response:0:500}"
    fi
}

# ── 4. Check old provision /status is NOT served ─────────────────────
check_no_old_status() {
    log "Step 4: Check old provision /status page is NOT served"

    if $SOURCE_ONLY; then
        skip "HTTP check requires running services (source-only mode)"
        return
    fi

    local response
    local http_code
    http_code=$(curl -sS -o /dev/null -w '%{http_code}' http://127.0.0.1:8080/status 2>&1 || echo "000")

    if [[ "$http_code" == "404" ]]; then
        pass "GET /status returns 404 (old provision page not served)"
    elif [[ "$http_code" == "401" || "$http_code" == "302" || "$http_code" == "303" ]]; then
        # Redirect to login or unauthorized is OK (dashboard handles /status differently)
        pass "GET /status returns $http_code (not old provision page)"
    else
        # Check if it's the old provision status page content
        response=$(curl -sS http://127.0.0.1:8080/status 2>&1 || true)
        if echo "$response" | grep -qi 'Telemetry Unit Status\|argus-provision\|NOT CONFIGURED'; then
            fail "GET /status still returns OLD provision status page"
        else
            pass "GET /status does not return old provision page (HTTP $http_code)"
        fi
    fi
}

# ── 5. Check systemd service states ──────────────────────────────────
check_systemd_services() {
    log "Step 5: Check systemd service states"

    if $SOURCE_ONLY; then
        skip "Systemd check requires installed services (source-only mode)"
        return
    fi

    # Check argus-dashboard is active
    local dashboard_active
    dashboard_active=$(systemctl is-active argus-dashboard 2>/dev/null || echo "unknown")
    if [[ "$dashboard_active" == "active" ]]; then
        pass "argus-dashboard is active"
    else
        fail "argus-dashboard is NOT active (status: $dashboard_active)"
    fi

    # Check argus-dashboard is enabled
    local dashboard_enabled
    dashboard_enabled=$(systemctl is-enabled argus-dashboard 2>/dev/null || echo "unknown")
    if [[ "$dashboard_enabled" == "enabled" ]]; then
        pass "argus-dashboard is enabled"
    else
        fail "argus-dashboard is NOT enabled (status: $dashboard_enabled)"
    fi

    # Check argus-provision is NOT active
    local provision_active
    provision_active=$(systemctl is-active argus-provision 2>/dev/null || echo "inactive")
    if [[ "$provision_active" == "inactive" || "$provision_active" == "unknown" ]]; then
        pass "argus-provision is inactive"
    else
        fail "argus-provision is still active (status: $provision_active)"
    fi

    # Check argus-provision is disabled
    local provision_enabled
    provision_enabled=$(systemctl is-enabled argus-provision 2>/dev/null || echo "disabled")
    if [[ "$provision_enabled" == "disabled" || "$provision_enabled" == "unknown" ]]; then
        pass "argus-provision is disabled"
    else
        fail "argus-provision is still enabled (status: $provision_enabled)"
    fi
}

# ── 6. Source-level checks ───────────────────────────────────────────
check_source_level() {
    log "Step 6: Source-level verification (EDGE-SETUP-1)"

    # Check install.sh does NOT enable argus-provision
    local install_sh="$REPO_ROOT/edge/install.sh"
    if [[ -f "$install_sh" ]]; then
        if grep -q 'systemctl enable argus-provision$' "$install_sh"; then
            fail "install.sh still enables argus-provision"
        else
            pass "install.sh does NOT enable argus-provision"
        fi

        if grep -q 'systemctl start argus-provision$' "$install_sh"; then
            fail "install.sh still starts argus-provision"
        else
            pass "install.sh does NOT start argus-provision"
        fi

        if grep -q 'systemctl enable argus-dashboard' "$install_sh"; then
            pass "install.sh enables argus-dashboard"
        else
            fail "install.sh does NOT enable argus-dashboard"
        fi

        if grep -q 'systemctl start argus-dashboard' "$install_sh"; then
            pass "install.sh starts argus-dashboard"
        else
            fail "install.sh does NOT start argus-dashboard"
        fi

        # Check for health check loop
        if grep -q 'curl.*8080/health' "$install_sh"; then
            pass "install.sh has health check loop"
        else
            fail "install.sh missing health check loop"
        fi
    else
        fail "install.sh not found at $install_sh"
    fi

    # Check pit_crew_dashboard.py has /health endpoint
    local dashboard_py="$REPO_ROOT/edge/pit_crew_dashboard.py"
    if [[ -f "$dashboard_py" ]]; then
        if grep -q "'/health'" "$dashboard_py" && grep -q 'handle_health' "$dashboard_py"; then
            pass "pit_crew_dashboard.py has /health endpoint"
        else
            fail "pit_crew_dashboard.py missing /health endpoint"
        fi

        # Check /setup route exists
        if grep -q "'/setup'" "$dashboard_py"; then
            pass "pit_crew_dashboard.py has /setup route"
        else
            fail "pit_crew_dashboard.py missing /setup route"
        fi
    else
        fail "pit_crew_dashboard.py not found at $dashboard_py"
    fi
}

# ── 8. EDGE-SETUP-2: Self-healing verification ────────────────────────
check_self_healing() {
    log "Step 8: Self-healing verification (EDGE-SETUP-2)"

    local install_sh="$REPO_ROOT/edge/install.sh"
    if [[ ! -f "$install_sh" ]]; then
        fail "install.sh not found"
        return
    fi

    # Check validate_and_recover() function exists
    if grep -q 'validate_and_recover()' "$install_sh"; then
        pass "install.sh has validate_and_recover() function"
    else
        fail "install.sh missing validate_and_recover() function"
    fi

    # Check INSTALL_HAD_ERRORS flag exists
    if grep -q 'INSTALL_HAD_ERRORS=' "$install_sh"; then
        pass "install.sh has INSTALL_HAD_ERRORS flag"
    else
        fail "install.sh missing INSTALL_HAD_ERRORS flag"
    fi

    # Check validate_and_recover is called on failure
    if grep -q 'validate_and_recover' "$install_sh" | grep -q 'if.*validate_and_recover'; then
        pass "install.sh calls validate_and_recover on failure"
    elif grep -qE '!\s*validate_and_recover|validate_and_recover.*then' "$install_sh"; then
        pass "install.sh calls validate_and_recover on failure"
    else
        # More lenient check
        if grep -q 'validate_and_recover' "$install_sh" && grep -q 'self-healing' "$install_sh"; then
            pass "install.sh has self-healing logic"
        else
            fail "install.sh doesn't call validate_and_recover on failure"
        fi
    fi

    # Check success path doesn't have manual troubleshooting commands
    # Extract the print_completion function and check the else branch (success path)
    # Success message should NOT contain "systemctl status" or "diagnose.sh" or "journalctl"
    # These should only be in the INSTALL_HAD_ERRORS=true branch

    # The success path is after "That's it! No reboot required." until "if $INSTALL_HAD_ERRORS"
    # We check that there's an if/else structure separating success from troubleshooting

    if grep -q 'if \$INSTALL_HAD_ERRORS' "$install_sh"; then
        pass "install.sh uses INSTALL_HAD_ERRORS to conditionally show troubleshooting"
    else
        fail "install.sh doesn't conditionally show troubleshooting based on INSTALL_HAD_ERRORS"
    fi

    # Verify troubleshooting section is inside the conditional
    # Check that "Troubleshooting" appears after "if $INSTALL_HAD_ERRORS"
    local troubleshoot_line
    local conditional_line
    troubleshoot_line=$(grep -n 'Troubleshooting' "$install_sh" | head -1 | cut -d: -f1 || echo "0")
    conditional_line=$(grep -n 'if \$INSTALL_HAD_ERRORS' "$install_sh" | head -1 | cut -d: -f1 || echo "999999")

    if [[ "$troubleshoot_line" -gt "$conditional_line" ]]; then
        pass "Troubleshooting section is inside INSTALL_HAD_ERRORS conditional"
    else
        fail "Troubleshooting section should be inside INSTALL_HAD_ERRORS conditional"
    fi
}

# ── 7. Python syntax check ───────────────────────────────────────────
check_python_syntax() {
    log "Step 7: Python syntax check"

    local dashboard_py="$REPO_ROOT/edge/pit_crew_dashboard.py"
    if [[ -f "$dashboard_py" ]]; then
        if python3 -c "import py_compile; py_compile.compile('$dashboard_py', doraise=True)" 2>/dev/null; then
            pass "pit_crew_dashboard.py syntax OK"
        else
            fail "pit_crew_dashboard.py has syntax errors"
        fi
    else
        skip "pit_crew_dashboard.py not found"
    fi

    local install_sh="$REPO_ROOT/edge/install.sh"
    if [[ -f "$install_sh" ]]; then
        if bash -n "$install_sh" 2>/dev/null; then
            pass "install.sh syntax OK"
        else
            fail "install.sh has syntax errors"
        fi
    else
        skip "install.sh not found"
    fi
}

# ── Summary ──────────────────────────────────────────────────────────
main() {
    log "EDGE-SETUP-1 & EDGE-SETUP-2 Smoke Test"
    echo ""

    detect_environment

    check_source_level
    check_python_syntax
    check_self_healing  # EDGE-SETUP-2

    if ! $SOURCE_ONLY; then
        check_port_8080
        check_root_redirect
        check_setup_route
        check_no_old_status
        check_systemd_services
    fi

    echo ""
    if [[ "$FAIL" -eq 0 ]]; then
        log "ALL CHECKS PASSED"
        exit 0
    else
        log "SOME CHECKS FAILED"
        exit 1
    fi
}

main "$@"
