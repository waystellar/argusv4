#!/bin/bash
#
# Argus Edge Installer (Headless)
# Installs edge software and starts provisioning web server
#
# Usage:
#   sudo ./edge/install.sh
#
# After installation, connect to http://<device-ip>:8080 to configure
#
# Requirements:
#   - Ubuntu 24.04 LTS (or Debian-based x86_64)
#   - Root privileges
#   - Internet connection
#
set -euo pipefail

# ============ Configuration ============

ARGUS_VERSION="4.1.0"
INSTALL_HAD_ERRORS=false  # EDGE-SETUP-2: Set true if self-healing failed
ARGUS_HOME="/opt/argus"
ARGUS_USER="argus"
CONFIG_DIR="/etc/argus"
CONFIG_FILE="${CONFIG_DIR}/config.env"
PROVISION_PORT=8080

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ============ Helper Functions ============

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

# ============ Cleanup Functions ============

cleanup_prior_installation() {
    log_info "Cleaning up any prior installation..."

    # Stop all argus services first
    local services=(
        "argus-provision"
        "argus-gps"
        "argus-can"
        "argus-uplink"
        "argus-ant"
        "argus-dashboard"
        "argus-video"
        "argus-cloudflared"
    )

    for service in "${services[@]}"; do
        systemctl stop "$service" 2>/dev/null || true
        systemctl disable "$service" 2>/dev/null || true
    done

    # Remove systemd service files
    rm -f /etc/systemd/system/argus-*.service
    systemctl daemon-reload 2>/dev/null || true

    # Remove udev rules
    rm -f /etc/udev/rules.d/99-argus.rules
    udevadm control --reload-rules 2>/dev/null || true

    # Remove sudoers configuration
    rm -f /etc/sudoers.d/argus

    # Remove config directory (includes .provisioned flag and config.env)
    rm -rf "$CONFIG_DIR"

    # Remove cloudflared config (tunnel config written by setup wizard)
    rm -rf /etc/cloudflared

    # Remove application directories but preserve user home if it exists
    if [[ -d "$ARGUS_HOME" ]]; then
        # Remove subdirectories but keep the base directory for the user
        rm -rf "$ARGUS_HOME/bin"
        rm -rf "$ARGUS_HOME/logs"
        rm -rf "$ARGUS_HOME/data"
        rm -rf "$ARGUS_HOME/config"
        rm -rf "$ARGUS_HOME/provision"
        rm -rf "$ARGUS_HOME/cache"
        rm -rf "$ARGUS_HOME/venv"
    fi

    log_success "Prior installation cleaned up"
}

# ============ Installation Steps ============

install_system_deps() {
    log_info "Installing system dependencies..."

    apt-get update -qq
    apt-get install -y -qq \
        python3 \
        python3-pip \
        python3-venv \
        python3-dev \
        build-essential \
        libzmq3-dev \
        ffmpeg \
        can-utils \
        usbutils \
        v4l-utils \
        curl \
        git

    log_success "System dependencies installed"
}

install_cloudflared() {
    log_info "Installing cloudflared for Cloudflare Tunnel..."

    # Pin to a known-good version for reproducible installs
    local CF_VERSION="2024.12.2"
    local ARCH
    ARCH="$(dpkg --print-architecture 2>/dev/null || echo amd64)"

    # Prefer Cloudflare's apt repo (auto-updates), fall back to pinned binary
    if curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg \
            | gpg --dearmor -o /usr/share/keyrings/cloudflare-main.gpg 2>/dev/null; then
        echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared $(lsb_release -cs 2>/dev/null || echo noble) main" \
            > /etc/apt/sources.list.d/cloudflared.list
        apt-get update -qq
        if apt-get install -y -qq cloudflared; then
            log_success "cloudflared installed via apt"
            return 0
        fi
        log_warn "apt install failed, falling back to binary..."
    fi

    # Fallback: pinned binary download
    local DL_URL="https://github.com/cloudflare/cloudflared/releases/download/${CF_VERSION}/cloudflared-linux-${ARCH}"
    if curl -fsSL -o /usr/local/bin/cloudflared "$DL_URL"; then
        chmod +x /usr/local/bin/cloudflared
        log_success "cloudflared ${CF_VERSION} installed (binary)"
    else
        log_error "Failed to install cloudflared — Cloudflare Tunnel will not work"
        log_error "Install manually: https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/"
        INSTALL_HAD_ERRORS=true
    fi
}

create_user() {
    if ! id -u "$ARGUS_USER" &>/dev/null; then
        log_info "Creating argus user..."
        useradd -r -m -d "$ARGUS_HOME" -s /bin/bash "$ARGUS_USER"
    fi

    # Add to required groups
    usermod -aG dialout,plugdev,video "$ARGUS_USER" 2>/dev/null || true

    log_success "User '$ARGUS_USER' configured"
}

create_directories() {
    log_info "Creating directories..."

    mkdir -p "$ARGUS_HOME"/{bin,logs,data,config,provision,state}
    mkdir -p "$ARGUS_HOME/cache/screenshots"
    mkdir -p "$CONFIG_DIR"

    chown -R "$ARGUS_USER:$ARGUS_USER" "$ARGUS_HOME"

    log_success "Directories created"
}

setup_python_env() {
    log_info "Setting up Python virtual environment..."

    # Create venv
    python3 -m venv "$ARGUS_HOME/venv"

    # Activate and install
    source "$ARGUS_HOME/venv/bin/activate"
    pip install --upgrade pip --quiet

    # Core dependencies
    pip install --quiet \
        httpx \
        pyserial \
        pynmea2 \
        pyzmq \
        aiosqlite \
        aiohttp \
        pyyaml \
        flask \
        python-can \
        cantools \
        gpxpy

    # ANT+ support (optional)
    pip install openant 2>/dev/null || log_warn "openant not available (ANT+ optional)"

    deactivate

    chown -R "$ARGUS_USER:$ARGUS_USER" "$ARGUS_HOME/venv"

    log_success "Python environment ready"
}

install_edge_scripts() {
    log_info "Installing edge scripts..."

    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    # FIXED: Added pit_crew_dashboard.py to list of installed scripts
    local scripts=(
        "gps_service.py"
        "can_telemetry.py"
        "uplink_service.py"
        "ant_heart_rate.py"
        "video_director.py"
        "pit_crew_dashboard.py"
        "stream_profiles.py"
        "simulator.py"
    )

    for script in "${scripts[@]}"; do
        if [[ -f "${SCRIPT_DIR}/${script}" ]]; then
            cp "${SCRIPT_DIR}/${script}" "$ARGUS_HOME/bin/"
            log_success "Installed: ${script}"
        else
            log_warn "Script not found: ${script}"
        fi
    done

    # Install shell utility scripts from bin/ directory
    if [[ -d "${SCRIPT_DIR}/bin" ]]; then
        for sh_script in "${SCRIPT_DIR}/bin"/*.sh; do
            if [[ -f "$sh_script" ]]; then
                cp "$sh_script" "$ARGUS_HOME/bin/"
                log_success "Installed: $(basename "$sh_script")"
            fi
        done
    fi

    chown -R "$ARGUS_USER:$ARGUS_USER" "$ARGUS_HOME/bin"
    chmod +x "$ARGUS_HOME/bin"/*.py 2>/dev/null || true
    chmod +x "$ARGUS_HOME/bin"/*.sh 2>/dev/null || true

    # EDGE-4: Install readiness/status scripts from scripts/ directory
    if [[ -d "${SCRIPT_DIR}/scripts" ]]; then
        mkdir -p "$ARGUS_HOME/scripts"
        for status_script in "${SCRIPT_DIR}/scripts"/*.sh; do
            if [[ -f "$status_script" ]]; then
                cp "$status_script" "$ARGUS_HOME/scripts/"
                log_success "Installed: scripts/$(basename "$status_script")"
            fi
        done
        chown -R "$ARGUS_USER:$ARGUS_USER" "$ARGUS_HOME/scripts"
        chmod +x "$ARGUS_HOME/scripts"/*.sh 2>/dev/null || true
    fi

    log_success "Edge scripts installed"
}

create_provision_server() {
    log_info "Creating provisioning web server..."

    cat > "$ARGUS_HOME/provision/server.py" << 'PROVISION_EOF'
#!/usr/bin/env python3
"""
Argus Edge Provisioning Server
Serves a web UI for configuring the edge device
"""

import os
import json
import socket
import subprocess
from pathlib import Path
from flask import Flask, render_template_string, request, jsonify, redirect

app = Flask(__name__)

CONFIG_DIR = Path("/etc/argus")
CONFIG_FILE = CONFIG_DIR / "config.env"
PROVISION_COMPLETE_FLAG = CONFIG_DIR / ".provisioned"

HTML_TEMPLATE = """
<!DOCTYPE html>
<html data-theme="argus-ds">
<head>
    <title>Edge Setup</title>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: #0a0a0a;
            color: #fafafa;
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 20px;
        }
        .container {
            background: #171717;
            border-radius: 12px;
            border: 1px solid #404040;
            padding: 32px;
            max-width: 500px;
            width: 100%;
        }
        h1 {
            color: #fafafa;
            margin-bottom: 8px;
            font-size: 1.5rem;
            font-weight: 700;
        }
        .subtitle {
            color: #a3a3a3;
            margin-bottom: 24px;
            font-size: 0.875rem;
        }
        .hostname {
            background: #262626;
            color: #d4d4d4;
            padding: 8px 16px;
            border-radius: 8px;
            font-family: monospace;
            font-size: 0.875rem;
            margin-bottom: 24px;
            display: inline-block;
        }
        label {
            display: block;
            margin-bottom: 6px;
            font-weight: 500;
            font-size: 0.875rem;
            color: #d4d4d4;
        }
        input, select {
            width: 100%;
            padding: 12px 16px;
            border: 1px solid #525252;
            border-radius: 8px;
            background: #0a0a0a;
            color: #fafafa;
            font-size: 1rem;
            margin-bottom: 16px;
            transition: border-color 0.1s;
        }
        input:focus, select:focus {
            outline: none;
            border-color: #3b82f6;
            box-shadow: 0 0 0 2px rgba(59, 130, 246, 0.25);
        }
        input::placeholder { color: #737373; }
        select option { background: #171717; color: #fafafa; }
        select optgroup { background: #171717; color: #a3a3a3; }
        button {
            width: 100%;
            padding: 12px;
            background: #2563eb;
            color: white;
            border: none;
            border-radius: 8px;
            font-size: 0.875rem;
            font-weight: 600;
            cursor: pointer;
            transition: background 0.1s;
            margin-top: 8px;
        }
        button:hover { background: #3b82f6; }
        button:active { background: #1d4ed8; }
        .error {
            background: rgba(239, 68, 68, 0.06);
            border: 1px solid rgba(239, 68, 68, 0.2);
            color: #fca5a5;
            padding: 12px;
            border-radius: 8px;
            margin-bottom: 16px;
            font-size: 0.875rem;
        }
        .success {
            background: rgba(34, 197, 94, 0.06);
            border: 1px solid rgba(34, 197, 94, 0.2);
            color: #86efac;
            padding: 12px;
            border-radius: 8px;
            margin-bottom: 16px;
            font-size: 0.875rem;
        }
        .info {
            background: rgba(59, 130, 246, 0.06);
            border: 1px solid rgba(59, 130, 246, 0.2);
            color: #93c5fd;
            padding: 12px;
            border-radius: 8px;
            margin-bottom: 16px;
            font-size: 0.875rem;
        }
        a { color: #60a5fa; }
        a:hover { color: #93c5fd; }
        @media (max-width: 480px) {
            body { padding: 8px; }
            .container { padding: 20px; }
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>Edge Setup</h1>
        <p class="subtitle">Configure this edge device for race telemetry</p>
        <div class="hostname">{{ hostname }}</div>

        {% if error %}
        <div class="error">{{ error }}</div>
        {% endif %}

        {% if success %}
        <div class="success">{{ success }}</div>
        {% endif %}

        <div class="info">
            Get your truck token and server URL from the race organizer or cloud admin panel.
        </div>

        <form method="POST" action="/provision">
            <label for="vehicle_number">Vehicle Number</label>
            <input type="text" id="vehicle_number" name="vehicle_number"
                   placeholder="e.g., 420" required pattern="[0-9]+"
                   value="{{ config.get('vehicle_number', '') }}">

            <label for="team_name">Team Name</label>
            <input type="text" id="team_name" name="team_name"
                   placeholder="e.g., Desert Racing Co"
                   value="{{ config.get('team_name', '') }}">

            <label for="truck_token">Truck Auth Token</label>
            <input type="password" id="truck_token" name="truck_token"
                   placeholder="From cloud server setup" required minlength="16"
                   value="{{ config.get('truck_token', '') }}">

            <label for="cloud_url">Cloud Server URL</label>
            <input type="url" id="cloud_url" name="cloud_url"
                   placeholder="http://192.168.1.100:8000" required
                   value="{{ config.get('cloud_url', '') }}">

            <label for="vehicle_class">Vehicle Class</label>
            <select id="vehicle_class" name="vehicle_class">
                <!-- Ultra4 -->
                <optgroup label="Ultra4">
                    <option value="ultra4_4400" {% if config.get('vehicle_class') == 'ultra4_4400' %}selected{% endif %}>4400 Unlimited</option>
                    <option value="ultra4_4500" {% if config.get('vehicle_class') == 'ultra4_4500' %}selected{% endif %}>4500 Modified</option>
                    <option value="ultra4_4600" {% if config.get('vehicle_class') == 'ultra4_4600' %}selected{% endif %}>4600 Stock</option>
                    <option value="ultra4_4800" {% if config.get('vehicle_class') == 'ultra4_4800' %}selected{% endif %}>4800 Legends</option>
                    <option value="ultra4_4900" {% if config.get('vehicle_class') == 'ultra4_4900' %}selected{% endif %}>4900 UTV</option>
                </optgroup>
                <!-- SCORE / BITD -->
                <optgroup label="SCORE/BITD">
                    <option value="trophy_truck" {% if config.get('vehicle_class') == 'trophy_truck' %}selected{% endif %}>Trophy Truck</option>
                    <option value="trick_truck" {% if config.get('vehicle_class') == 'trick_truck' %}selected{% endif %}>Trick Truck</option>
                    <option value="tt_spec" {% if config.get('vehicle_class') == 'tt_spec' %}selected{% endif %}>Trophy Truck Spec</option>
                    <option value="class_1" {% if config.get('vehicle_class') == 'class_1' %}selected{% endif %}>Class 1</option>
                    <option value="class_10" {% if config.get('vehicle_class') == 'class_10' %}selected{% endif %}>Class 10</option>
                    <option value="class_1_2_1600" {% if config.get('vehicle_class') == 'class_1_2_1600' %}selected{% endif %}>Class 1/2-1600</option>
                </optgroup>
                <!-- Trucks -->
                <optgroup label="Trucks">
                    <option value="class_6100" {% if config.get('vehicle_class') == 'class_6100' %}selected{% endif %}>Class 6100</option>
                    <option value="class_7200" {% if config.get('vehicle_class') == 'class_7200' %}selected{% endif %}>Class 7200</option>
                    <option value="class_8100" {% if config.get('vehicle_class') == 'class_8100' %}selected{% endif %}>Class 8100</option>
                    <option value="unlimited_truck" {% if config.get('vehicle_class') == 'unlimited_truck' %}selected{% endif %}>Unlimited Truck</option>
                    <option value="pro_truck" {% if config.get('vehicle_class') == 'pro_truck' %}selected{% endif %}>Pro Truck</option>
                    <option value="spec_truck" {% if config.get('vehicle_class') == 'spec_truck' %}selected{% endif %}>Spec Truck</option>
                </optgroup>
                <!-- UTV -->
                <optgroup label="UTV">
                    <option value="utv_pro" {% if config.get('vehicle_class') == 'utv_pro' %}selected{% endif %}>UTV Pro</option>
                    <option value="utv_pro_na" {% if config.get('vehicle_class') == 'utv_pro_na' %}selected{% endif %}>UTV Pro NA</option>
                    <option value="utv_turbo" {% if config.get('vehicle_class') == 'utv_turbo' %}selected{% endif %}>UTV Turbo</option>
                    <option value="utv_production" {% if config.get('vehicle_class') == 'utv_production' %}selected{% endif %}>UTV Production</option>
                    <option value="utv_rally" {% if config.get('vehicle_class') == 'utv_rally' %}selected{% endif %}>UTV Rally</option>
                </optgroup>
                <!-- Moto -->
                <optgroup label="Moto">
                    <option value="moto_pro" {% if config.get('vehicle_class') == 'moto_pro' %}selected{% endif %}>Pro Motorcycle</option>
                    <option value="moto_ironman" {% if config.get('vehicle_class') == 'moto_ironman' %}selected{% endif %}>Ironman</option>
                </optgroup>
                <!-- Other -->
                <optgroup label="Other">
                    <option value="buggy" {% if config.get('vehicle_class') == 'buggy' %}selected{% endif %}>Buggy</option>
                    <option value="sportsman" {% if config.get('vehicle_class') == 'sportsman' %}selected{% endif %}>Sportsman</option>
                </optgroup>
            </select>

            <button type="submit">Save & Activate Telemetry</button>
        </form>
    </div>
</body>
</html>
"""

SUCCESS_TEMPLATE = """
<!DOCTYPE html>
<html data-theme="argus-ds">
<head>
    <title>Setup Complete</title>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: #0a0a0a;
            color: #fafafa;
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            text-align: center;
            padding: 20px;
        }
        .container {
            background: #171717;
            border-radius: 12px;
            border: 1px solid #404040;
            padding: 32px;
            max-width: 500px;
            width: 100%;
        }
        h1 { font-size: 1.5rem; font-weight: 700; margin-bottom: 16px; color: #22c55e; }
        p { font-size: 1rem; color: #a3a3a3; margin-bottom: 8px; }
        .vehicle {
            font-size: 3.5rem;
            font-weight: 700;
            color: #fafafa;
            margin: 20px 0;
        }
        .team-name { font-size: 1rem; color: #d4d4d4; }
        .handoff-box {
            background: #262626;
            border: 1px solid #404040;
            padding: 16px;
            border-radius: 8px;
            margin-top: 24px;
        }
        .warnings {
            background: rgba(245, 158, 11, 0.06);
            border: 1px solid rgba(245, 158, 11, 0.2);
            padding: 12px;
            border-radius: 8px;
            margin-top: 16px;
            text-align: left;
            font-size: 0.875rem;
            color: #fcd34d;
        }
        .warnings ul { margin: 8px 0 0 20px; }
        .warnings p { color: #a3a3a3; font-size: 0.8rem; }
        a { color: #60a5fa; }
        a:hover { color: #93c5fd; }
        .spinner {
            display: inline-block;
            width: 18px;
            height: 18px;
            border: 2px solid #404040;
            border-top-color: #3b82f6;
            border-radius: 50%;
            animation: spin 0.8s linear infinite;
            vertical-align: middle;
            margin-right: 8px;
        }
        @keyframes spin { to { transform: rotate(360deg); } }
        @media (max-width: 480px) {
            body { padding: 8px; }
            .container { padding: 20px; }
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>Setup Complete</h1>
        <div class="vehicle">#{{ vehicle_number }}</div>
        <p class="team-name">{{ team_name }}</p>
        {% if warnings %}
        <div class="warnings">
            <strong>Completed with warnings:</strong>
            <ul>
            {% for w in warnings %}
                <li>{{ w }}</li>
            {% endfor %}
            </ul>
            <p style="margin-top: 8px;">These may resolve after reboot.</p>
        </div>
        {% endif %}
        <div class="handoff-box" id="handoff-status">
            <p style="color: #fafafa;"><span class="spinner"></span><strong>Switching to Pit Crew Dashboard...</strong></p>
            <p style="font-size: 0.8rem; color: #737373;">Telemetry services starting</p>
        </div>
    </div>
    <script>
    (function() {
        var el = document.getElementById('handoff-status');
        var attempts = 0;
        var maxAttempts = 20;

        function check() {
            attempts++;
            if (attempts > maxAttempts) {
                el.innerHTML = '<p><strong>Dashboard did not start automatically.</strong></p>' +
                    '<p style="font-size:14px;">Try rebooting the device, then revisit this page.</p>' +
                    '<p><a href="/status">View diagnostics</a></p>';
                return;
            }
            var xhr = new XMLHttpRequest();
            xhr.open('GET', '/api/edge/status', true);
            xhr.timeout = 2000;
            xhr.onload = function() {
                if (xhr.status === 200 || xhr.status === 302 || xhr.status === 303) {
                    el.innerHTML = '<p><strong>Dashboard is ready!</strong></p><p>Redirecting...</p>';
                    setTimeout(function() { window.location.href = '/'; }, 500);
                } else {
                    setTimeout(check, 2000);
                }
            };
            xhr.onerror = function() { setTimeout(check, 2000); };
            xhr.ontimeout = function() { setTimeout(check, 2000); };
            try { xhr.send(); } catch(e) { setTimeout(check, 2000); }
        }

        setTimeout(check, 4000);
    })();
    </script>
</body>
</html>
"""

STATUS_TEMPLATE = """
<!DOCTYPE html>
<html data-theme="argus-ds">
<head>
    <title>Edge Status</title>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta http-equiv="refresh" content="10">
    <style>
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: #0a0a0a;
            color: #fafafa;
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 20px;
        }
        .container {
            background: #171717;
            border-radius: 12px;
            border: 1px solid #404040;
            padding: 32px;
            max-width: 700px;
            width: 100%;
        }
        h1 { color: #fafafa; margin-bottom: 4px; font-size: 1.5rem; font-weight: 700; }
        .subtitle { color: #a3a3a3; margin-bottom: 24px; font-size: 0.875rem; }
        .vehicle-number {
            font-size: 3.5rem;
            font-weight: 700;
            color: #fafafa;
            margin: 16px 0;
        }
        .info-row {
            display: flex;
            justify-content: space-between;
            padding: 10px 0;
            border-bottom: 1px solid #262626;
            font-size: 0.875rem;
        }
        .info-row:last-child { border-bottom: none; }
        .label { color: #a3a3a3; }
        .value { font-weight: 600; color: #d4d4d4; word-break: break-all; }
        .status-badge {
            display: inline-block;
            padding: 3px 10px;
            border-radius: 20px;
            font-size: 0.7rem;
            font-weight: 600;
        }
        .status-ok { background: rgba(34, 197, 94, 0.1); color: #4ade80; border: 1px solid rgba(34, 197, 94, 0.2); }
        .status-error { background: rgba(239, 68, 68, 0.1); color: #f87171; border: 1px solid rgba(239, 68, 68, 0.2); }
        .status-pending { background: rgba(245, 158, 11, 0.1); color: #fbbf24; border: 1px solid rgba(245, 158, 11, 0.2); }
        .status-disabled { background: rgba(115, 115, 115, 0.1); color: #a3a3a3; border: 1px solid #404040; }
        .actions { margin-top: 24px; display: flex; flex-wrap: wrap; gap: 8px; justify-content: center; }
        .btn {
            display: inline-block;
            padding: 10px 20px;
            background: #2563eb;
            color: white;
            text-decoration: none;
            border-radius: 8px;
            font-weight: 600;
            font-size: 0.875rem;
        }
        .btn:hover { background: #3b82f6; }
        .btn-secondary { background: #262626; color: #d4d4d4; border: 1px solid #404040; }
        .btn-secondary:hover { background: #363636; }
        .services { margin-top: 20px; }
        .services h3 { margin-bottom: 10px; font-size: 0.875rem; font-weight: 600; color: #d4d4d4; }
        .service-item {
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding: 8px 12px;
            background: #0a0a0a;
            border: 1px solid #262626;
            border-radius: 6px;
            margin-bottom: 6px;
            font-size: 0.8rem;
        }
        .service-name { font-weight: 500; color: #d4d4d4; }
        .service-status { display: flex; gap: 6px; align-items: center; }
        .diag-section {
            margin-top: 20px;
            padding: 12px;
            background: #0a0a0a;
            border: 1px solid #262626;
            border-radius: 8px;
            font-size: 0.8rem;
        }
        .diag-section h4 { margin-bottom: 8px; color: #d4d4d4; font-size: 0.875rem; }
        .diag-item { display: flex; justify-content: space-between; padding: 4px 0; }
        .diag-ok { color: #4ade80; }
        .diag-warn { color: #fbbf24; }
        .diag-error { color: #f87171; }
        .help-text {
            margin-top: 16px;
            padding: 12px;
            background: rgba(245, 158, 11, 0.06);
            border: 1px solid rgba(245, 158, 11, 0.2);
            border-radius: 8px;
            font-size: 0.8rem;
            color: #fcd34d;
        }
        .help-text.error-box {
            background: rgba(239, 68, 68, 0.06);
            border-color: rgba(239, 68, 68, 0.2);
            color: #fca5a5;
        }
        .help-text code {
            background: #262626;
            padding: 2px 6px;
            border-radius: 4px;
            font-size: 0.75rem;
            color: #d4d4d4;
        }
        a { color: #60a5fa; }
        a:hover { color: #93c5fd; }
        @media (max-width: 480px) {
            body { padding: 8px; }
            .container { padding: 20px; }
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>Edge Status</h1>
        <p class="subtitle">Telemetry Unit Status</p>

        {% if not config.get('argus_vehicle_number') %}
        <div class="help-text error-box">
            <strong>NOT CONFIGURED</strong><br>
            No configuration found. <a href="/?reconfigure=1">Click here to configure</a> or run:
            <code>sudo /opt/argus/bin/activate-telemetry.sh</code>
        </div>
        {% else %}
        <div class="vehicle-number">#{{ config.get('argus_vehicle_number', '?') }}</div>

        <div class="info-row">
            <span class="label">Team</span>
            <span class="value">{{ config.get('argus_team_name', 'Not Set') }}</span>
        </div>
        <div class="info-row">
            <span class="label">Class</span>
            <span class="value">{{ config.get('argus_vehicle_class', 'Not Set') }}</span>
        </div>
        <div class="info-row">
            <span class="label">Cloud Server</span>
            <span class="value">{{ config.get('argus_cloud_url', 'Not Set') }}</span>
        </div>
        <div class="info-row">
            <span class="label">Device</span>
            <span class="value">{{ hostname }}</span>
        </div>
        {% endif %}

        <div class="services">
            <h3>Services</h3>
            {% for service, info in services.items() %}
            <div class="service-item">
                <span class="service-name">{{ service }}</span>
                <div class="service-status">
                    <span class="status-badge {{ 'status-ok' if info.active == 'active' else 'status-error' if info.active == 'failed' else 'status-pending' if info.active == 'activating' else 'status-disabled' }}">
                        {{ info.active }}
                    </span>
                    <span class="status-badge {{ 'status-ok' if info.enabled == 'enabled' else 'status-disabled' }}">
                        {{ info.enabled }}
                    </span>
                </div>
            </div>
            {% endfor %}
        </div>

        <div class="diag-section">
            <h4>Quick Diagnostics</h4>
            <div class="diag-item">
                <span>Config File</span>
                <span class="{{ 'diag-ok' if diag.config_exists else 'diag-error' }}">
                    {{ '✓ Found' if diag.config_exists else '✗ Missing' }}
                </span>
            </div>
            <div class="diag-item">
                <span>Provisioned Flag</span>
                <span class="{{ 'diag-ok' if diag.provisioned else 'diag-warn' }}">
                    {{ '✓ Set' if diag.provisioned else '○ Not set' }}
                </span>
            </div>
            <div class="diag-item">
                <span>Sudo Access</span>
                <span class="{{ 'diag-ok' if diag.sudo_ok else 'diag-error' }}">
                    {{ '✓ OK' if diag.sudo_ok else '✗ ' + diag.sudo_msg }}
                </span>
            </div>
        </div>

        {% if not diag.sudo_ok %}
        <div class="help-text">
            <strong>Sudo access issue detected</strong><br>
            Run as root: <code>sudo /opt/argus/bin/fix-sudoers.sh</code>
        </div>
        {% endif %}

        {% if diag.config_exists and not diag.provisioned %}
        <div class="help-text">
            <strong>Config exists but not activated</strong><br>
            Run: <code>sudo /opt/argus/bin/activate-telemetry.sh</code>
        </div>
        {% endif %}

        <div class="actions">
            <a href="/" class="btn">Open Pit Crew Dashboard</a>
            <a href="/status" class="btn btn-secondary">Refresh</a>
            <a href="/?reconfigure=1" class="btn btn-secondary">Reconfigure</a>
            <a href="/api/diagnose" class="btn btn-secondary">Full Diagnostic</a>
        </div>

        <p style="text-align: center; margin-top: 16px; color: #737373; font-size: 0.75rem;">
            Auto-refreshes every 10 seconds
        </p>
    </div>
</body>
</html>
"""

def get_hostname():
    return socket.gethostname()

def get_ip():
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except:
        return "unknown"

def load_config():
    config = {}
    if CONFIG_FILE.exists():
        for line in CONFIG_FILE.read_text().splitlines():
            if '=' in line and not line.startswith('#'):
                key, value = line.split('=', 1)
                config[key.strip().lower()] = value.strip()
    return config

def save_config(data):
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)

    config_content = f"""# Argus Edge Configuration
# Generated by provisioning server

# Vehicle Identity
ARGUS_VEHICLE_NUMBER={data['vehicle_number']}
ARGUS_VEHICLE_ID=truck_{data['vehicle_number']}
ARGUS_TEAM_NAME={data['team_name']}
ARGUS_VEHICLE_CLASS={data['vehicle_class']}

# Cloud Server
ARGUS_CLOUD_URL={data['cloud_url']}
ARGUS_TRUCK_TOKEN={data['truck_token']}

# Hardware (auto-detected)
ARGUS_GPS_DEVICE=/dev/argus_gps
ARGUS_CAN_INTERFACE=can0
ARGUS_CAN_BITRATE=500000

# Performance
ARGUS_GPS_HZ=10
ARGUS_TELEMETRY_HZ=10
ARGUS_UPLOAD_BATCH_SIZE=50

# Logging
ARGUS_LOG_LEVEL=INFO
"""
    CONFIG_FILE.write_text(config_content)
    os.chmod(CONFIG_FILE, 0o600)

def verify_sudo_access():
    """Check if we have passwordless sudo access for systemctl commands"""
    try:
        result = subprocess.run(
            ['sudo', '-n', 'systemctl', 'status', 'argus-provision'],
            capture_output=True, text=True, timeout=5
        )
        # -n flag means non-interactive, will fail if password needed
        # Return code 0 or 3 (unit not found) or 4 (unit inactive) are all OK
        # Only return code 1 with "password" in stderr indicates sudo failure
        if result.returncode == 1 and 'password' in result.stderr.lower():
            return False, "Sudoers not configured - passwordless sudo required"
        return True, "Sudo access OK"
    except subprocess.TimeoutExpired:
        return False, "Sudo command timed out"
    except Exception as e:
        return False, f"Sudo check failed: {str(e)}"

def run_systemctl(action, service):
    """Run systemctl command with error capture"""
    try:
        result = subprocess.run(
            ['sudo', '-n', 'systemctl', action, service],
            capture_output=True, text=True, timeout=30
        )
        if result.returncode != 0:
            return False, result.stderr.strip() or f"Exit code {result.returncode}"
        return True, result.stdout.strip()
    except subprocess.TimeoutExpired:
        return False, "Command timed out"
    except Exception as e:
        return False, str(e)

def schedule_service_handoff():
    """Spawn a detached process to swap provision server for dashboard.

    After a 3-second delay (so the HTTP success response is delivered),
    stops argus-provision (releases port 8080) then starts argus-dashboard.
    The child process is session-detached so it survives the provision
    server being killed by systemctl stop.
    """
    subprocess.Popen(
        ['bash', '-c',
         'sleep 3 '
         '&& sudo -n systemctl stop argus-provision 2>/dev/null '
         '&& sleep 1 '
         '&& sudo -n systemctl start argus-dashboard 2>/dev/null'],
        start_new_session=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )

def activate_telemetry():
    """Switch from provision mode to telemetry mode by enabling services for next boot

    Returns:
        tuple: (success: bool, message: str, errors: list)
    """
    errors = []

    # Verify sudo access first
    sudo_ok, sudo_msg = verify_sudo_access()
    if not sudo_ok:
        return False, f"Cannot activate: {sudo_msg}", [sudo_msg]

    # Ensure config directory exists before creating flag
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)

    # Verify config file exists (should have been saved before this call)
    if not CONFIG_FILE.exists():
        return False, "Config file not saved - cannot activate", ["config.env missing"]

    # Create provisioned flag
    PROVISION_COMPLETE_FLAG.touch()
    print(f"Created provisioned flag: {PROVISION_COMPLETE_FLAG}")

    # Disable provisioning service (won't run on next boot due to ConditionPathExists)
    success, msg = run_systemctl('disable', 'argus-provision')
    if not success:
        errors.append(f"disable argus-provision: {msg}")
        print(f"Warning: Failed to disable argus-provision: {msg}")

    # Enable and start telemetry services (these don't conflict with provision on port 8080)
    started_services = []
    for service in ['argus-gps', 'argus-can-setup', 'argus-can', 'argus-uplink', 'argus-ant', 'argus-video']:
        # Enable for next boot
        success, msg = run_systemctl('enable', service)
        if not success:
            errors.append(f"enable {service}: {msg}")
            print(f"Warning: Failed to enable {service}: {msg}")

        # Try to start now
        success, msg = run_systemctl('start', service)
        if success:
            started_services.append(service)
        else:
            # Non-critical - service may not have hardware available
            print(f"Note: {service} not started (may be normal): {msg}")

    print(f"Telemetry services enabled. Started: {started_services}")

    # Enable dashboard for next boot
    success, msg = run_systemctl('enable', 'argus-dashboard')
    if not success:
        errors.append(f"enable argus-dashboard: {msg}")
        print(f"Warning: Failed to enable argus-dashboard: {msg}")
    else:
        print("Dashboard enabled")

    # Schedule handoff: stop provision server → start dashboard (after HTTP response)
    schedule_service_handoff()
    print("Service handoff scheduled (3s delay)")

    # Return result
    if errors:
        return True, f"Activated with warnings ({len(errors)} issues)", errors
    return True, "Telemetry activated successfully", []

@app.route('/')
def index():
    # If already provisioned, redirect to status page (unless reconfigure requested)
    if PROVISION_COMPLETE_FLAG.exists() and not request.args.get('reconfigure'):
        return redirect('/status')

    config = load_config()
    return render_template_string(HTML_TEMPLATE,
                                  hostname=f"{get_hostname()} ({get_ip()})",
                                  config=config,
                                  error=None,
                                  success=None)

@app.route('/provision', methods=['POST'])
def provision():
    try:
        data = {
            'vehicle_number': request.form['vehicle_number'],
            'team_name': request.form.get('team_name', f"Team {request.form['vehicle_number']}"),
            'truck_token': request.form['truck_token'],
            'cloud_url': request.form['cloud_url'].rstrip('/'),
            'vehicle_class': request.form.get('vehicle_class', 'trophy_truck'),
        }

        # Validate
        if not data['vehicle_number'].isdigit():
            raise ValueError("Vehicle number must be numeric")
        if len(data['truck_token']) < 16:
            raise ValueError("Token must be at least 16 characters")
        if not data['cloud_url'].startswith(('http://', 'https://')):
            raise ValueError("Cloud URL must start with http:// or https://")

        # Save configuration FIRST
        save_config(data)
        print(f"Configuration saved to {CONFIG_FILE}")

        # Verify config was saved
        if not CONFIG_FILE.exists():
            raise ValueError("Failed to save configuration file")

        # Activate telemetry mode
        success, message, errors = activate_telemetry()

        if not success:
            # Activation failed - show error with details
            error_details = f"{message}"
            if errors:
                error_details += f" Errors: {'; '.join(errors)}"
            raise ValueError(error_details)

        # Show success page (with warnings if any)
        return render_template_string(SUCCESS_TEMPLATE,
                                      vehicle_number=data['vehicle_number'],
                                      team_name=data['team_name'],
                                      warnings=errors if errors else None)

    except Exception as e:
        config = load_config()
        return render_template_string(HTML_TEMPLATE,
                                      hostname=f"{get_hostname()} ({get_ip()})",
                                      config=config,
                                      error=str(e),
                                      success=None)

@app.route('/status')
def status():
    """Show current status and service health after provisioning"""
    # Allow viewing status page even if not fully provisioned (for debugging)
    config = load_config()

    # Check service statuses with more detail
    services = {}
    for service in ['argus-gps', 'argus-can-setup', 'argus-can', 'argus-uplink', 'argus-ant', 'argus-dashboard', 'argus-video', 'argus-cloudflared']:
        try:
            # Get active status
            active_result = subprocess.run(
                ['systemctl', 'is-active', service],
                capture_output=True, text=True, timeout=5
            )
            active = active_result.stdout.strip() or 'unknown'

            # Get enabled status
            enabled_result = subprocess.run(
                ['systemctl', 'is-enabled', service],
                capture_output=True, text=True, timeout=5
            )
            enabled = enabled_result.stdout.strip() or 'unknown'

            services[service] = {'active': active, 'enabled': enabled}
        except:
            services[service] = {'active': 'unknown', 'enabled': 'unknown'}

    # Quick diagnostics
    sudo_ok, sudo_msg = verify_sudo_access()
    diag = {
        'config_exists': CONFIG_FILE.exists(),
        'provisioned': PROVISION_COMPLETE_FLAG.exists(),
        'sudo_ok': sudo_ok,
        'sudo_msg': sudo_msg,
    }

    return render_template_string(STATUS_TEMPLATE,
                                  hostname=f"{get_hostname()} ({get_ip()})",
                                  config=config,
                                  services=services,
                                  diag=diag)

@app.route('/health')
def health():
    mode = 'telemetry' if PROVISION_COMPLETE_FLAG.exists() else 'provision'
    return jsonify({'status': 'ok', 'mode': mode, 'hostname': get_hostname()})

@app.route('/api/config', methods=['GET'])
def get_config_api():
    """API endpoint for automated provisioning"""
    config = load_config()
    # Don't expose the token
    config.pop('argus_truck_token', None)
    return jsonify(config)

@app.route('/api/provision', methods=['POST'])
def provision_api():
    """API endpoint for automated provisioning (headless)"""
    try:
        data = request.get_json()
        save_config(data)
        success, message, errors = activate_telemetry()
        if not success:
            return jsonify({'status': 'error', 'message': message, 'errors': errors}), 500
        return jsonify({
            'status': 'ok',
            'message': message,
            'warnings': errors if errors else []
        })
    except Exception as e:
        return jsonify({'status': 'error', 'message': str(e)}), 400

@app.route('/api/diagnose')
def diagnose():
    """Diagnostic endpoint to check system status"""
    diag = {
        'hostname': get_hostname(),
        'ip': get_ip(),
        'provisioned': PROVISION_COMPLETE_FLAG.exists(),
        'config_exists': CONFIG_FILE.exists(),
        'config_dir_exists': CONFIG_DIR.exists(),
        'sudo_check': {},
        'services': {},
        'files': {},
    }

    # Check sudo access
    sudo_ok, sudo_msg = verify_sudo_access()
    diag['sudo_check'] = {'ok': sudo_ok, 'message': sudo_msg}

    # Check service statuses
    for service in ['argus-provision', 'argus-gps', 'argus-can-setup', 'argus-can', 'argus-uplink', 'argus-ant', 'argus-dashboard', 'argus-video', 'argus-cloudflared']:
        try:
            result = subprocess.run(
                ['systemctl', 'is-active', service],
                capture_output=True, text=True, timeout=5
            )
            status = result.stdout.strip() or 'unknown'

            # Also check if enabled
            enabled_result = subprocess.run(
                ['systemctl', 'is-enabled', service],
                capture_output=True, text=True, timeout=5
            )
            enabled = enabled_result.stdout.strip() or 'unknown'

            diag['services'][service] = {'active': status, 'enabled': enabled}
        except Exception as e:
            diag['services'][service] = {'active': 'error', 'enabled': 'error', 'error': str(e)}

    # Check important files
    files_to_check = [
        '/etc/argus/config.env',
        '/etc/argus/.provisioned',
        '/etc/sudoers.d/argus',
        '/opt/argus/bin/gps_service.py',
        '/opt/argus/bin/pit_crew_dashboard.py',
        '/opt/argus/venv/bin/python',
    ]
    for f in files_to_check:
        diag['files'][f] = os.path.exists(f)

    return jsonify(diag)

@app.route('/api/activate', methods=['POST'])
def manual_activate():
    """Manual activation endpoint for recovery"""
    # Verify config exists first
    if not CONFIG_FILE.exists():
        return jsonify({
            'status': 'error',
            'message': 'Config file does not exist. Please provision first.'
        }), 400

    success, message, errors = activate_telemetry()

    if not success:
        return jsonify({
            'status': 'error',
            'message': message,
            'errors': errors
        }), 500

    return jsonify({
        'status': 'ok',
        'message': message,
        'warnings': errors if errors else []
    })

@app.route('/api/fix-sudoers', methods=['POST'])
def fix_sudoers():
    """Attempt to diagnose sudoers issue (read-only, just reports)"""
    # This is informational only - can't fix without root
    sudoers_file = '/etc/sudoers.d/argus'
    result = {
        'sudoers_exists': os.path.exists(sudoers_file),
        'sudo_check': verify_sudo_access(),
        'instructions': []
    }

    if not result['sudoers_exists']:
        result['instructions'].append(
            "Sudoers file missing. Run as root: sudo /opt/argus/bin/fix-sudoers.sh"
        )
    elif not result['sudo_check'][0]:
        result['instructions'].append(
            "Sudoers exists but not working. Check permissions: ls -la /etc/sudoers.d/argus"
        )
        result['instructions'].append(
            "Should be: -r--r----- root root /etc/sudoers.d/argus"
        )
        result['instructions'].append(
            "Fix with: sudo chmod 0440 /etc/sudoers.d/argus && sudo chown root:root /etc/sudoers.d/argus"
        )

    return jsonify(result)

if __name__ == '__main__':
    # Check if already provisioned
    if PROVISION_COMPLETE_FLAG.exists():
        print("Device already provisioned. Serving status page...")
        print(f"To reconfigure, visit: http://{get_ip()}:8080/?reconfigure=1")
    else:
        print(f"Starting Argus Provisioning Server on port 8080...")
        print(f"Connect to: http://{get_ip()}:8080")

    app.run(host='0.0.0.0', port=8080, debug=False)
PROVISION_EOF

    chmod +x "$ARGUS_HOME/provision/server.py"
    chown -R "$ARGUS_USER:$ARGUS_USER" "$ARGUS_HOME/provision"

    log_success "Provisioning server created"
}

create_recovery_scripts() {
    log_info "Creating recovery scripts..."

    # Fix sudoers script
    cat > "$ARGUS_HOME/bin/fix-sudoers.sh" << 'RECOVERY_SUDOERS_EOF'
#!/bin/bash
# Argus - Fix Sudoers Configuration
# Run as root: sudo /opt/argus/bin/fix-sudoers.sh

if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root (use sudo)"
    exit 1
fi

SUDOERS_FILE="/etc/sudoers.d/argus"

echo "Creating/fixing argus sudoers configuration..."

cat > "$SUDOERS_FILE" << 'EOF'
# Argus Timing System - Allow argus user to manage argus services
argus ALL=(ALL) NOPASSWD: /usr/bin/systemctl enable argus-*
argus ALL=(ALL) NOPASSWD: /usr/bin/systemctl disable argus-*
argus ALL=(ALL) NOPASSWD: /usr/bin/systemctl start argus-*
argus ALL=(ALL) NOPASSWD: /usr/bin/systemctl stop argus-*
argus ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart argus-*
argus ALL=(ALL) NOPASSWD: /usr/bin/systemctl status argus-*
argus ALL=(ALL) NOPASSWD: /usr/bin/journalctl -u argus-*
argus ALL=(ALL) NOPASSWD: /usr/bin/mkdir -p /etc/cloudflared
argus ALL=(ALL) NOPASSWD: /usr/bin/tee /etc/cloudflared/config.yml
argus ALL=(ALL) NOPASSWD: /usr/bin/systemctl daemon-reload
EOF

chmod 0440 "$SUDOERS_FILE"
chown root:root "$SUDOERS_FILE"

if visudo -c -f "$SUDOERS_FILE"; then
    echo "✓ Sudoers configured successfully"
else
    echo "✗ Sudoers validation failed"
    rm -f "$SUDOERS_FILE"
    exit 1
fi

# Test it
echo "Testing sudo access for argus user..."
if sudo -u argus sudo -n systemctl status argus-provision >/dev/null 2>&1; then
    echo "✓ Sudo access working for argus user"
else
    echo "? Sudo test returned non-zero (may be normal if service not running)"
fi
RECOVERY_SUDOERS_EOF

    # Manual activation script
    cat > "$ARGUS_HOME/bin/activate-telemetry.sh" << 'RECOVERY_ACTIVATE_EOF'
#!/bin/bash
# Argus - Manual Telemetry Activation
# Run as root: sudo /opt/argus/bin/activate-telemetry.sh

if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root (use sudo)"
    exit 1
fi

CONFIG_FILE="/etc/argus/config.env"
PROVISION_FLAG="/etc/argus/.provisioned"

echo "=== Argus Manual Activation ==="

# Check config exists
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "✗ Config file not found: $CONFIG_FILE"
    echo "  You must provision the device first via the web interface"
    echo "  or create the config file manually."
    exit 1
fi

echo "✓ Config file found"

# Create provisioned flag
touch "$PROVISION_FLAG"
echo "✓ Created provisioned flag"

# Stop provision server
echo "Stopping provision server..."
systemctl stop argus-provision 2>/dev/null || true
systemctl disable argus-provision 2>/dev/null || true

# Enable and start telemetry services
echo "Enabling telemetry services..."
for service in argus-gps argus-can-setup argus-can argus-uplink argus-ant argus-video; do
    systemctl enable "$service" 2>/dev/null
    systemctl start "$service" 2>/dev/null
    status=$(systemctl is-active "$service" 2>/dev/null || echo "unknown")
    if [[ "$status" == "active" ]]; then
        echo "  ✓ $service: running"
    else
        echo "  - $service: $status (may need hardware)"
    fi
done

# Enable dashboard
echo "Enabling pit crew dashboard..."
systemctl enable argus-dashboard
systemctl start argus-dashboard
dashboard_status=$(systemctl is-active argus-dashboard 2>/dev/null || echo "unknown")
echo "  Dashboard: $dashboard_status"

echo ""
echo "=== Activation Complete ==="
echo "Dashboard URL: http://$(hostname -I | awk '{print $1}'):8080"
echo ""
echo "To check status: systemctl status argus-dashboard"
echo "To view logs: journalctl -u argus-dashboard -f"
RECOVERY_ACTIVATE_EOF

    # Diagnostic script
    cat > "$ARGUS_HOME/bin/diagnose.sh" << 'RECOVERY_DIAG_EOF'
#!/bin/bash
# Argus - System Diagnostic
# Run: /opt/argus/bin/diagnose.sh

echo "=== Argus Edge Diagnostic ==="
echo ""
echo "System:"
echo "  Hostname: $(hostname)"
echo "  IP: $(hostname -I | awk '{print $1}')"
echo ""

echo "Configuration:"
if [[ -f /etc/argus/config.env ]]; then
    echo "  ✓ config.env exists"
    grep -E "^ARGUS_(VEHICLE_NUMBER|TEAM_NAME|CLOUD_URL)=" /etc/argus/config.env | sed 's/^/    /'
else
    echo "  ✗ config.env MISSING"
fi

if [[ -f /etc/argus/.provisioned ]]; then
    echo "  ✓ .provisioned flag exists"
else
    echo "  ✗ .provisioned flag MISSING"
fi
echo ""

echo "Sudoers:"
if [[ -f /etc/sudoers.d/argus ]]; then
    echo "  ✓ sudoers file exists"
    perms=$(stat -c "%a %U:%G" /etc/sudoers.d/argus 2>/dev/null || stat -f "%Lp %Su:%Sg" /etc/sudoers.d/argus 2>/dev/null)
    echo "    Permissions: $perms (should be 440 root:root)"
else
    echo "  ✗ sudoers file MISSING"
fi
echo ""

echo "Services:"
for service in argus-provision argus-gps argus-can-setup argus-can argus-uplink argus-ant argus-dashboard argus-video argus-cloudflared; do
    active=$(systemctl is-active "$service" 2>/dev/null || echo "unknown")
    enabled=$(systemctl is-enabled "$service" 2>/dev/null || echo "unknown")
    printf "  %-20s active=%-10s enabled=%s\n" "$service" "$active" "$enabled"
done
echo ""

echo "Cloudflare Tunnel:"
if command -v cloudflared >/dev/null 2>&1; then
    echo "  ✓ cloudflared installed ($(cloudflared --version 2>&1 | head -1))"
else
    echo "  ✗ cloudflared NOT installed"
fi
if [[ -f /etc/cloudflared/config.yml ]]; then
    echo "  ✓ Tunnel config exists"
else
    echo "  ○ No tunnel config (set via Pit Crew Dashboard setup)"
fi
echo ""

echo "Key Files:"
for f in /opt/argus/bin/gps_service.py /opt/argus/bin/pit_crew_dashboard.py /opt/argus/venv/bin/python; do
    if [[ -f "$f" ]]; then
        echo "  ✓ $f"
    else
        echo "  ✗ $f MISSING"
    fi
done
echo ""

echo "Network Ports:"
ss -tlnp 2>/dev/null | grep -E ":(8080|5556|5557|5558)\s" | sed 's/^/  /' || echo "  (no listening ports found)"
echo ""

echo "=== End Diagnostic ==="
RECOVERY_DIAG_EOF

    # Full repair script - fixes all common issues
    cat > "$ARGUS_HOME/bin/repair.sh" << 'RECOVERY_REPAIR_EOF'
#!/bin/bash
# Argus - Full System Repair
# Fixes all common installation issues
# Run as root: sudo /opt/argus/bin/repair.sh
#
# Usage with credentials:
#   sudo /opt/argus/bin/repair.sh --token TOKEN --vehicle 42 --team "Team Name" --cloud-url http://192.168.0.19
#
# Usage for directory/dependency repair only:
#   sudo /opt/argus/bin/repair.sh --fix-deps

set -e

if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root (use sudo)"
    exit 1
fi

# Parse arguments
TRUCK_TOKEN=""
VEHICLE_NUMBER=""
TEAM_NAME=""
CLOUD_URL=""
VEHICLE_CLASS="trophy_truck"
FIX_DEPS_ONLY=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --token)
            TRUCK_TOKEN="$2"
            shift 2
            ;;
        --vehicle)
            VEHICLE_NUMBER="$2"
            shift 2
            ;;
        --team)
            TEAM_NAME="$2"
            shift 2
            ;;
        --cloud-url)
            CLOUD_URL="$2"
            shift 2
            ;;
        --class)
            VEHICLE_CLASS="$2"
            shift 2
            ;;
        --fix-deps)
            FIX_DEPS_ONLY=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 --token TOKEN --vehicle NUM --team NAME --cloud-url URL"
            exit 1
            ;;
    esac
done

echo "=== Argus System Repair ==="
echo ""

# Step 1: Fix directories
echo "Step 1: Ensuring directories exist..."
mkdir -p /opt/argus/{bin,logs,data,config,provision,state}
mkdir -p /opt/argus/cache/screenshots
mkdir -p /etc/argus
chown -R argus:argus /opt/argus
chown -R argus:argus /etc/argus
chmod 755 /opt/argus/cache/screenshots
echo "  ✓ Directories created and permissions set"

# Step 2: Fix missing Python dependencies
echo "Step 2: Checking Python dependencies..."
if [[ -f /opt/argus/venv/bin/pip ]]; then
    # Install missing packages
    /opt/argus/venv/bin/pip install --quiet gpxpy httpx 2>/dev/null || true
    echo "  ✓ Python dependencies installed"
else
    echo "  ✗ Python venv not found - run full installer"
fi

# Step 3: Install missing system packages
echo "Step 3: Checking system packages..."
if ! command -v v4l2-ctl &> /dev/null; then
    apt-get update -qq && apt-get install -y -qq v4l-utils 2>/dev/null || true
    echo "  ✓ v4l-utils installed"
else
    echo "  ✓ v4l-utils already installed"
fi

if [[ "$FIX_DEPS_ONLY" == "true" ]]; then
    echo ""
    echo "=== Dependencies Fixed ==="
    echo "Run with --token, --vehicle, --team, --cloud-url to create config"
    exit 0
fi

# Step 4: Create config file
if [[ -z "$TRUCK_TOKEN" || -z "$VEHICLE_NUMBER" || -z "$CLOUD_URL" ]]; then
    echo ""
    echo "Step 4: SKIPPED - Missing required parameters"
    echo "  To create config, provide: --token, --vehicle, --team, --cloud-url"
    echo ""
else
    echo "Step 4: Creating configuration..."

    if [[ -z "$TEAM_NAME" ]]; then
        TEAM_NAME="Team $VEHICLE_NUMBER"
    fi

    cat > /etc/argus/config.env << CONFIGEOF
# Argus Edge Configuration
# Generated by repair script

# Vehicle Identity
ARGUS_VEHICLE_NUMBER=${VEHICLE_NUMBER}
ARGUS_VEHICLE_ID=truck_${VEHICLE_NUMBER}
ARGUS_TEAM_NAME=${TEAM_NAME}
ARGUS_VEHICLE_CLASS=${VEHICLE_CLASS}

# Cloud Server
ARGUS_CLOUD_URL=${CLOUD_URL}
ARGUS_TRUCK_TOKEN=${TRUCK_TOKEN}

# Hardware (auto-detected)
ARGUS_GPS_DEVICE=/dev/argus_gps
ARGUS_CAN_INTERFACE=can0
ARGUS_CAN_BITRATE=500000

# Performance
ARGUS_GPS_HZ=10
ARGUS_TELEMETRY_HZ=10
ARGUS_UPLOAD_BATCH_SIZE=50

# Logging
ARGUS_LOG_LEVEL=INFO
CONFIGEOF

    chmod 600 /etc/argus/config.env
    chown argus:argus /etc/argus/config.env
    echo "  ✓ Configuration saved to /etc/argus/config.env"

    # Create provisioned flag
    touch /etc/argus/.provisioned
    chown argus:argus /etc/argus/.provisioned
    echo "  ✓ Provisioned flag created"
fi

# Step 5: Fix sudoers
echo "Step 5: Fixing sudoers..."
cat > /etc/sudoers.d/argus << 'SUDOERSEOF'
# Argus Timing System - Allow argus user to manage argus services
argus ALL=(ALL) NOPASSWD: /usr/bin/systemctl enable argus-*
argus ALL=(ALL) NOPASSWD: /usr/bin/systemctl disable argus-*
argus ALL=(ALL) NOPASSWD: /usr/bin/systemctl start argus-*
argus ALL=(ALL) NOPASSWD: /usr/bin/systemctl stop argus-*
argus ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart argus-*
argus ALL=(ALL) NOPASSWD: /usr/bin/systemctl status argus-*
argus ALL=(ALL) NOPASSWD: /usr/bin/journalctl -u argus-*
SUDOERSEOF
chmod 0440 /etc/sudoers.d/argus
chown root:root /etc/sudoers.d/argus
echo "  ✓ Sudoers configured"

# Step 6: Restart services
if [[ -f /etc/argus/.provisioned ]]; then
    echo "Step 6: Restarting services..."

    # Stop provisioning service
    systemctl stop argus-provision 2>/dev/null || true
    systemctl disable argus-provision 2>/dev/null || true

    # Reload systemd
    systemctl daemon-reload

    # Enable and start telemetry services
    for service in argus-gps argus-can-setup argus-can argus-uplink argus-ant argus-video argus-dashboard; do
        systemctl enable "$service" 2>/dev/null || true
        systemctl restart "$service" 2>/dev/null || true
        status=$(systemctl is-active "$service" 2>/dev/null || echo "inactive")
        if [[ "$status" == "active" ]]; then
            echo "  ✓ $service: running"
        else
            echo "  - $service: $status"
        fi
    done
else
    echo "Step 6: SKIPPED - No config/provisioned flag"
fi

echo ""
echo "=== Repair Complete ==="
IP=$(hostname -I | awk '{print $1}')
echo "Dashboard URL: http://${IP}:8080"
echo ""
echo "To view dashboard logs: journalctl -u argus-dashboard -f"
echo "To view uplink logs: journalctl -u argus-uplink -f"
RECOVERY_REPAIR_EOF

    chmod +x "$ARGUS_HOME/bin/fix-sudoers.sh"
    chmod +x "$ARGUS_HOME/bin/activate-telemetry.sh"
    chmod +x "$ARGUS_HOME/bin/diagnose.sh"
    chmod +x "$ARGUS_HOME/bin/repair.sh"
    chown -R "$ARGUS_USER:$ARGUS_USER" "$ARGUS_HOME/bin"

    log_success "Recovery scripts created"
}

configure_udev_rules() {
    log_info "Configuring udev rules..."

    cat > /etc/udev/rules.d/99-argus.rules << 'UDEV_EOF'
# Argus Timing System - USB Device Rules
# Auto-generated by installer

# GPS Devices
SUBSYSTEM=="tty", ATTRS{idVendor}=="1546", ATTRS{idProduct}=="01a*", SYMLINK+="argus_gps", MODE="0666"
SUBSYSTEM=="tty", ATTRS{idVendor}=="067b", ATTRS{idProduct}=="2303", SYMLINK+="argus_gps", MODE="0666"
SUBSYSTEM=="tty", ATTRS{idVendor}=="067b", ATTRS{idProduct}=="23*", SYMLINK+="argus_gps", MODE="0666"
SUBSYSTEM=="tty", ATTRS{idVendor}=="0403", ATTRS{idProduct}=="6001", SYMLINK+="argus_gps", MODE="0666"
SUBSYSTEM=="tty", ATTRS{idVendor}=="10c4", ATTRS{idProduct}=="ea60", SYMLINK+="argus_gps", MODE="0666"

# ANT+ USB Dongles
SUBSYSTEM=="usb", ATTRS{idVendor}=="0fcf", ATTRS{idProduct}=="1008", SYMLINK+="argus_ant", MODE="0666"
SUBSYSTEM=="usb", ATTRS{idVendor}=="0fcf", ATTRS{idProduct}=="1009", SYMLINK+="argus_ant", MODE="0666"

# CAN Bus Adapters
SUBSYSTEM=="usb", ATTRS{idVendor}=="0c72", ATTRS{idProduct}=="000c", SYMLINK+="argus_can", MODE="0666"
SUBSYSTEM=="tty", ATTRS{idVendor}=="1d50", ATTRS{idProduct}=="606f", SYMLINK+="argus_can", MODE="0666"
UDEV_EOF

    udevadm control --reload-rules
    udevadm trigger

    log_success "udev rules configured"
}

install_systemd_services() {
    log_info "Installing systemd services..."

    # Provisioning Service (enabled by default)
    cat > /etc/systemd/system/argus-provision.service << EOF
[Unit]
Description=Argus Edge Provisioning Server
After=network-online.target
Wants=network-online.target
ConditionPathExists=!/etc/argus/.provisioned

[Service]
Type=simple
User=${ARGUS_USER}
WorkingDirectory=${ARGUS_HOME}/provision
ExecStart=${ARGUS_HOME}/venv/bin/python ${ARGUS_HOME}/provision/server.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    # GPS Service (disabled until provisioned)
    # EDGE-3: Added ExecStartPre device-wait and StartLimit to prevent thrash
    cat > /etc/systemd/system/argus-gps.service << EOF
[Unit]
Description=Argus GPS Service
After=network.target
ConditionPathExists=/etc/argus/.provisioned
Before=argus-uplink.service
# EDGE-3: If service crashes 3 times in 60s, stop trying (not hardware-missing)
StartLimitIntervalSec=60
StartLimitBurst=3

[Service]
Type=simple
User=${ARGUS_USER}
WorkingDirectory=${ARGUS_HOME}
EnvironmentFile=${CONFIG_FILE}
# EDGE-3: Wait for GPS device before starting (prefix '-' = don't fail if wait times out)
ExecStartPre=-${ARGUS_HOME}/bin/device-wait.sh serial /dev/argus_gps 60
ExecStart=${ARGUS_HOME}/venv/bin/python ${ARGUS_HOME}/bin/gps_service.py
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    # CAN Bus Interface Setup (oneshot — runs before argus-can)
    # EDGE-2: Brings up can0 with correct bitrate on boot
    cat > /etc/systemd/system/argus-can-setup.service << EOF
[Unit]
Description=Argus CAN Bus Interface Setup
After=network.target sys-subsystem-net-devices-can0.device
DefaultDependencies=yes
ConditionPathExists=/etc/argus/.provisioned

[Service]
Type=oneshot
RemainAfterExit=yes
EnvironmentFile=${CONFIG_FILE}
ExecStart=${ARGUS_HOME}/bin/can-setup.sh
SuccessExitStatus=0 1

[Install]
WantedBy=multi-user.target
EOF

    # CAN Telemetry Service (disabled until provisioned)
    # EDGE-2: Now depends on argus-can-setup instead of raw device node
    # EDGE-3: Added StartLimit to prevent thrash on service crash
    cat > /etc/systemd/system/argus-can.service << EOF
[Unit]
Description=Argus CAN Telemetry Service
After=network.target argus-can-setup.service
Wants=argus-can-setup.service
ConditionPathExists=/etc/argus/.provisioned
Before=argus-uplink.service
# EDGE-3: If service crashes 3 times in 60s, stop trying
StartLimitIntervalSec=60
StartLimitBurst=3

[Service]
Type=simple
User=${ARGUS_USER}
WorkingDirectory=${ARGUS_HOME}
EnvironmentFile=${CONFIG_FILE}
ExecStart=${ARGUS_HOME}/venv/bin/python ${ARGUS_HOME}/bin/can_telemetry.py
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    # Uplink Service (disabled until provisioned)
    # EDGE-7: Changed Requires= to Wants= so uplink runs even if GPS is missing.
    # The uplink ZMQ subscriber silently waits for GPS data; no crash on absence.
    # After= preserved so GPS starts first when both are enabled.
    cat > /etc/systemd/system/argus-uplink.service << EOF
[Unit]
Description=Argus Uplink Service
After=network-online.target argus-gps.service argus-can.service argus-ant.service
Wants=network-online.target argus-gps.service argus-can.service argus-ant.service
ConditionPathExists=/etc/argus/.provisioned
# CODEX-P0-2: If service crashes 3 times in 60s, stop trying (matches GPS/CAN/ANT pattern)
StartLimitIntervalSec=60
StartLimitBurst=3

[Service]
Type=simple
User=${ARGUS_USER}
WorkingDirectory=${ARGUS_HOME}
EnvironmentFile=${CONFIG_FILE}
ExecStart=${ARGUS_HOME}/venv/bin/python ${ARGUS_HOME}/bin/uplink_service.py
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    # ANT+ Heart Rate Service (disabled until provisioned)
    # EDGE-3: Added ExecStartPre device-wait and StartLimit to prevent thrash
    cat > /etc/systemd/system/argus-ant.service << EOF
[Unit]
Description=Argus ANT+ Heart Rate Service
After=network.target
ConditionPathExists=/etc/argus/.provisioned
Before=argus-uplink.service
# EDGE-3: If service crashes 3 times in 60s, stop trying
StartLimitIntervalSec=60
StartLimitBurst=3

[Service]
Type=simple
User=${ARGUS_USER}
WorkingDirectory=${ARGUS_HOME}
EnvironmentFile=${CONFIG_FILE}
# EDGE-3: Wait for ANT+ USB stick (Dynastream vendor 0fcf)
ExecStartPre=-${ARGUS_HOME}/bin/device-wait.sh usb 0fcf: 60
ExecStart=${ARGUS_HOME}/venv/bin/python ${ARGUS_HOME}/bin/ant_heart_rate.py
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    # EDGE-SETUP-1: Pit Crew Dashboard Service (starts immediately after install)
    # This is the ONLY first-install UI - serves /setup for password configuration
    # No ConditionPathExists - dashboard always starts and handles setup internally
    cat > /etc/systemd/system/argus-dashboard.service << EOF
[Unit]
Description=Argus Pit Crew Dashboard
After=network-online.target
Wants=network-online.target
# Note: No ConditionPathExists - dashboard always starts and redirects to /setup if unconfigured
# EDGE-CLOUD-3: Uses network-online.target because dashboard sends heartbeats to cloud

[Service]
Type=simple
User=${ARGUS_USER}
WorkingDirectory=${ARGUS_HOME}
# EnvironmentFile is optional (may not exist on first install)
EnvironmentFile=-${CONFIG_FILE}
ExecStart=${ARGUS_HOME}/venv/bin/python ${ARGUS_HOME}/bin/pit_crew_dashboard.py --port 8080
Restart=always
RestartSec=5
# Dashboard config stored separately from main config
Environment="ARGUS_PIT_CONFIG=/opt/argus/config/pit_dashboard.json"

[Install]
WantedBy=multi-user.target
EOF

    # ADDED: Video Director Service (disabled until provisioned)
    # Handles camera switching commands from cloud production
    # EDGE-3: Added ExecStartPre device-wait and StartLimit to prevent thrash
    cat > /etc/systemd/system/argus-video.service << EOF
[Unit]
Description=Argus Video Director Service
After=network-online.target
Wants=network-online.target
ConditionPathExists=/etc/argus/.provisioned
# EDGE-3: If service crashes 3 times in 120s, stop trying
StartLimitIntervalSec=120
StartLimitBurst=3

[Service]
Type=simple
User=${ARGUS_USER}
WorkingDirectory=${ARGUS_HOME}
EnvironmentFile=${CONFIG_FILE}
# EDGE-3: Wait for at least one camera device
ExecStartPre=-${ARGUS_HOME}/bin/device-wait.sh video /dev/video0 60
ExecStart=${ARGUS_HOME}/venv/bin/python ${ARGUS_HOME}/bin/video_director.py
Restart=on-failure
RestartSec=15

[Install]
WantedBy=multi-user.target
EOF

    # EDGE-4: Readiness Aggregation — Boot Timing Service (oneshot)
    # Runs edge_readiness_wait.sh on boot to capture boot-to-operational timing.
    # Waits for all Tier 1 services to report OPERATIONAL for 10 consecutive seconds.
    cat > /etc/systemd/system/argus-readiness.service << EOF
[Unit]
Description=Argus Edge Readiness Wait
After=argus-gps.service argus-uplink.service argus-dashboard.service
Wants=argus-gps.service argus-uplink.service argus-dashboard.service
ConditionPathExists=/etc/argus/.provisioned

[Service]
Type=oneshot
User=${ARGUS_USER}
WorkingDirectory=${ARGUS_HOME}
EnvironmentFile=${CONFIG_FILE}
ExecStart=${ARGUS_HOME}/scripts/edge_readiness_wait.sh 180 10
TimeoutStartSec=200
RemainAfterExit=yes
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    # Cloudflare Tunnel Service (CGNAT-proof external access)
    # Uses token-based auth — config is written at runtime by setup wizard
    # when the pit crew enters their Cloudflare tunnel token.
    cat > /etc/systemd/system/argus-cloudflared.service << EOF
[Unit]
Description=Argus Cloudflare Tunnel
After=network-online.target
Wants=network-online.target
# Only start if tunnel config has been written by the setup wizard
ConditionPathExists=/etc/cloudflared/config.yml

[Service]
Type=simple
# Resolve cloudflared path — may be /usr/bin (apt) or /usr/local/bin (binary download)
ExecStartPre=/bin/sh -c 'command -v cloudflared >/dev/null 2>&1 || test -x /usr/local/bin/cloudflared || (echo "cloudflared not installed" && exit 1)'
ExecStart=/bin/sh -c 'exec \$(command -v cloudflared || echo /usr/local/bin/cloudflared) --no-autoupdate --config /etc/cloudflared/config.yml tunnel run'
Restart=always
RestartSec=10
# Longer start limit — tunnel may take time on first auth
StartLimitIntervalSec=300
StartLimitBurst=5
# Log tunnel errors for diagnostics
StandardOutput=journal
StandardError=journal
SyslogIdentifier=cloudflared

[Install]
WantedBy=multi-user.target
EOF

    # Reload systemd
    systemctl daemon-reload

    # EDGE-SETUP-1: Create .provisioned flag immediately
    # This allows telemetry services to start on boot (they'll wait for hardware)
    touch "$CONFIG_DIR/.provisioned"
    chown "$ARGUS_USER:$ARGUS_USER" "$CONFIG_DIR/.provisioned"
    log_success "Created provisioned flag"

    # EDGE-SETUP-1: Disable old provision server (not used anymore)
    systemctl disable argus-provision 2>/dev/null || true
    systemctl stop argus-provision 2>/dev/null || true

    # EDGE-SETUP-1: Enable and start pit crew dashboard immediately
    # This is the ONLY first-install UI - it handles setup at /setup
    systemctl enable argus-dashboard
    systemctl start argus-dashboard
    log_info "Starting pit crew dashboard..."

    # Wait for dashboard to be ready (up to 60 seconds)
    local max_attempts=30
    local attempt=0
    while [[ $attempt -lt $max_attempts ]]; do
        if curl -fsS http://127.0.0.1:8080/health >/dev/null 2>&1; then
            log_success "Pit crew dashboard is ready on port 8080"
            break
        fi
        attempt=$((attempt + 1))
        sleep 2
    done

    if [[ $attempt -ge $max_attempts ]]; then
        log_warn "Dashboard not responding after 60 seconds - running self-healing..."
        # EDGE-SETUP-2: Auto-recover instead of showing manual steps
        if ! validate_and_recover; then
            log_error "Self-healing failed. Dashboard logs:"
            journalctl -u argus-dashboard --no-pager -n 30 || true
            echo
            log_error "Installation completed but dashboard is not responding."
            log_error "Please report this issue with the logs above."
            # Set a flag so print_completion knows to show troubleshooting
            INSTALL_HAD_ERRORS=true
        fi
    fi

    # Enable telemetry services for boot (they'll start when hardware is available)
    systemctl enable argus-gps 2>/dev/null || true
    systemctl enable argus-can-setup 2>/dev/null || true
    systemctl enable argus-can 2>/dev/null || true
    systemctl enable argus-uplink 2>/dev/null || true
    systemctl enable argus-ant 2>/dev/null || true
    systemctl enable argus-video 2>/dev/null || true
    # EDGE-4: Enable readiness service
    systemctl enable argus-readiness 2>/dev/null || true

    log_success "Systemd services installed"
}

create_default_config() {
    log_info "Creating default config directory..."

    mkdir -p "$CONFIG_DIR"

    # Don't create config.env - that's done during provisioning
    # Just ensure directory exists with correct permissions

    chown -R "$ARGUS_USER:$ARGUS_USER" "$CONFIG_DIR"

    log_success "Config directory ready"
}

configure_sudoers() {
    log_info "Configuring sudoers for argus service management..."

    # Allow argus user to manage argus-* services without password
    # This is needed because the provision server runs as argus user
    # but needs to enable/disable/start services after provisioning
    cat > /etc/sudoers.d/argus << 'SUDOERS_EOF'
# Argus Timing System - Allow argus user to manage argus services
# This file is auto-generated by the Argus installer

# Allow managing argus-* systemd services
argus ALL=(ALL) NOPASSWD: /usr/bin/systemctl enable argus-*
argus ALL=(ALL) NOPASSWD: /usr/bin/systemctl disable argus-*
argus ALL=(ALL) NOPASSWD: /usr/bin/systemctl start argus-*
argus ALL=(ALL) NOPASSWD: /usr/bin/systemctl stop argus-*
argus ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart argus-*
argus ALL=(ALL) NOPASSWD: /usr/bin/systemctl status argus-*

# Allow reading system logs for diagnostics
argus ALL=(ALL) NOPASSWD: /usr/bin/journalctl -u argus-*

# Allow writing Cloudflare Tunnel config (setup wizard writes /etc/cloudflared/config.yml)
argus ALL=(ALL) NOPASSWD: /usr/bin/mkdir -p /etc/cloudflared
argus ALL=(ALL) NOPASSWD: /usr/bin/tee /etc/cloudflared/config.yml
argus ALL=(ALL) NOPASSWD: /usr/bin/systemctl daemon-reload
SUDOERS_EOF

    # Set correct permissions (sudoers files must be 0440)
    chmod 0440 /etc/sudoers.d/argus

    # Validate sudoers file
    if visudo -c -f /etc/sudoers.d/argus; then
        log_success "Sudoers configured for argus user"
    else
        log_error "Sudoers file validation failed, removing..."
        rm -f /etc/sudoers.d/argus
    fi
}

# EDGE-5: Disk/Log Reliability — journald limits, log rotation, boot history cap
configure_log_limits() {
    log_info "Configuring disk/log reliability (EDGE-5)..."

    # ---- 1. Journald size limits ----
    # Cap systemd journal to 100M persistent + 50M runtime.
    # Prevents journald from filling disk during long races.
    mkdir -p /etc/systemd/journald.conf.d
    cat > /etc/systemd/journald.conf.d/argus-limits.conf << 'JOURNALD_EOF'
# Argus EDGE-5: Bounded journal storage
# Prevents disk-full during long races or restart storms.
[Journal]
SystemMaxUse=100M
SystemKeepFree=200M
SystemMaxFileSize=25M
RuntimeMaxUse=50M
MaxRetentionSec=7day
JOURNALD_EOF

    # Restart journald to apply (non-destructive — existing logs trimmed gradually)
    systemctl restart systemd-journald 2>/dev/null || true
    log_success "Journald capped at 100M persistent / 50M runtime"

    # ---- 2. Logrotate for boot_history.log ----
    # boot_history.log is append-only (one line per boot). Cap at 50KB (~500 boots).
    cat > /etc/logrotate.d/argus << 'LOGROTATE_EOF'
/opt/argus/state/boot_history.log {
    size 50k
    rotate 2
    compress
    missingok
    notifempty
    copytruncate
}
LOGROTATE_EOF
    log_success "Logrotate configured for boot_history.log"

    # ---- 3. Screenshot cache cleanup cron ----
    # Screenshots are overwritten per-camera, but stale files from removed cameras
    # could linger. Clean files older than 1 day.
    cat > /etc/cron.d/argus-cache-cleanup << 'CRON_EOF'
# EDGE-5: Remove stale screenshot cache files (older than 1 day)
0 */6 * * * root find /opt/argus/cache/screenshots -name '*.jpg' -mmin +1440 -delete 2>/dev/null
CRON_EOF
    chmod 644 /etc/cron.d/argus-cache-cleanup
    log_success "Screenshot cache cleanup cron installed"

    log_success "Disk/log reliability configured (EDGE-5)"
}

# EDGE-SETUP-2: Self-healing diagnostics and recovery
# Called automatically if dashboard fails to start - no manual intervention needed
validate_and_recover() {
    local recovery_attempted=false
    local issues_found=0

    log_info "Running self-healing diagnostics..."

    # ── 1. Check sudoers configuration ──
    if ! sudo -u "$ARGUS_USER" sudo -n systemctl status argus-dashboard >/dev/null 2>&1; then
        log_warn "Sudoers not working - auto-fixing..."
        issues_found=$((issues_found + 1))

        # Re-run configure_sudoers
        cat > /etc/sudoers.d/argus << 'SUDOERS_EOF'
# Argus Timing System - Allow argus user to manage argus services
argus ALL=(ALL) NOPASSWD: /usr/bin/systemctl enable argus-*
argus ALL=(ALL) NOPASSWD: /usr/bin/systemctl disable argus-*
argus ALL=(ALL) NOPASSWD: /usr/bin/systemctl start argus-*
argus ALL=(ALL) NOPASSWD: /usr/bin/systemctl stop argus-*
argus ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart argus-*
argus ALL=(ALL) NOPASSWD: /usr/bin/systemctl status argus-*
argus ALL=(ALL) NOPASSWD: /usr/bin/journalctl -u argus-*
argus ALL=(ALL) NOPASSWD: /usr/bin/mkdir -p /etc/cloudflared
argus ALL=(ALL) NOPASSWD: /usr/bin/tee /etc/cloudflared/config.yml
argus ALL=(ALL) NOPASSWD: /usr/bin/systemctl daemon-reload
SUDOERS_EOF
        chmod 0440 /etc/sudoers.d/argus
        chown root:root /etc/sudoers.d/argus

        if visudo -c -f /etc/sudoers.d/argus >/dev/null 2>&1; then
            log_success "Sudoers auto-fixed"
            recovery_attempted=true
        else
            log_error "Sudoers auto-fix failed"
        fi
    fi

    # ── 2. Check .provisioned flag ──
    if [[ ! -f "$CONFIG_DIR/.provisioned" ]]; then
        log_warn ".provisioned flag missing - auto-creating..."
        issues_found=$((issues_found + 1))
        touch "$CONFIG_DIR/.provisioned"
        chown "$ARGUS_USER:$ARGUS_USER" "$CONFIG_DIR/.provisioned"
        log_success ".provisioned flag created"
        recovery_attempted=true
    fi

    # ── 3. Check directory permissions ──
    if [[ ! -w "$ARGUS_HOME/config" ]] || [[ "$(stat -c '%U' "$ARGUS_HOME/config" 2>/dev/null)" != "$ARGUS_USER" ]]; then
        log_warn "Directory permissions incorrect - auto-fixing..."
        issues_found=$((issues_found + 1))
        chown -R "$ARGUS_USER:$ARGUS_USER" "$ARGUS_HOME"
        chown -R "$ARGUS_USER:$ARGUS_USER" "$CONFIG_DIR"
        chmod 755 "$ARGUS_HOME/cache/screenshots" 2>/dev/null || true
        log_success "Directory permissions fixed"
        recovery_attempted=true
    fi

    # ── 4. Check Python dependencies ──
    if ! "$ARGUS_HOME/venv/bin/python" -c "import aiohttp; import gpxpy" >/dev/null 2>&1; then
        log_warn "Missing Python dependencies - auto-installing..."
        issues_found=$((issues_found + 1))
        "$ARGUS_HOME/venv/bin/pip" install --quiet aiohttp gpxpy httpx 2>/dev/null || true
        log_success "Python dependencies installed"
        recovery_attempted=true
    fi

    # ── 5. Retry dashboard start if recovery was attempted ──
    if $recovery_attempted; then
        log_info "Recovery completed - restarting dashboard..."
        systemctl daemon-reload
        systemctl restart argus-dashboard

        # Wait for health check again
        local attempt=0
        local max_attempts=15
        while [[ $attempt -lt $max_attempts ]]; do
            if curl -fsS http://127.0.0.1:8080/health >/dev/null 2>&1; then
                log_success "Dashboard started after recovery!"
                return 0
            fi
            attempt=$((attempt + 1))
            sleep 2
        done

        # Still failed after recovery
        log_error "Dashboard still not responding after recovery attempt"
        return 1
    fi

    # No recovery needed but dashboard still not up - check logs
    if ! curl -fsS http://127.0.0.1:8080/health >/dev/null 2>&1; then
        log_error "Dashboard not responding - no recoverable issues found"
        return 1
    fi

    if [[ $issues_found -eq 0 ]]; then
        log_success "Self-healing check: no issues found"
    fi
    return 0
}

get_device_ip() {
    # Try to get the primary IP address
    ip route get 1 2>/dev/null | awk '{print $7; exit}' || hostname -I | awk '{print $1}' || echo "unknown"
}

print_completion() {
    local IP=$(get_device_ip)

    echo
    # EDGE-SETUP-2: Show different banner depending on success/failure
    if $INSTALL_HAD_ERRORS; then
        echo -e "${YELLOW}╔═══════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${YELLOW}║       ARGUS EDGE INSTALLATION COMPLETED WITH ISSUES           ║${NC}"
        echo -e "${YELLOW}╚═══════════════════════════════════════════════════════════════╝${NC}"
    else
        echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║           ARGUS EDGE INSTALLATION COMPLETE                    ║${NC}"
        echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    fi
    echo
    echo -e "  ${BLUE}Installation Summary:${NC}"
    echo "  ─────────────────────────────────────────────────"
    echo "  Install Path:     $ARGUS_HOME"
    echo "  Config Directory: $CONFIG_DIR"
    echo "  User:             $ARGUS_USER"
    echo "  ─────────────────────────────────────────────────"
    echo
    echo -e "  ${YELLOW}NEXT STEP: Complete Setup${NC}"
    echo "  ─────────────────────────────────────────────────"
    echo
    echo "  Open a browser and go to:"
    echo -e "       ${GREEN}http://${IP}:8080${NC}"
    echo
    echo "  You will see the Pit Crew Dashboard Setup page."
    echo "  1. Create a dashboard password (share with pit crew)"
    echo "  2. Optionally enter vehicle number, cloud URL, token"
    echo "  3. Click 'Complete Setup'"
    echo
    echo "  That's it! No reboot required."
    echo "  ─────────────────────────────────────────────────"
    echo
    echo -e "  ${BLUE}Services:${NC}"
    echo "  ─────────────────────────────────────────────────"
    echo "    • argus-dashboard  - Pit crew web interface (port 8080)"
    echo "    • argus-cloudflared - Cloudflare Tunnel (after setup)"
    echo "    • argus-gps        - GPS telemetry (when hardware available)"
    echo "    • argus-uplink     - Cloud data upload"
    echo "  ─────────────────────────────────────────────────"

    # EDGE-SETUP-2: Only show troubleshooting section if there were errors
    if $INSTALL_HAD_ERRORS; then
        echo
        echo -e "  ${RED}Troubleshooting:${NC}"
        echo "  ─────────────────────────────────────────────────"
        echo "  The dashboard did not start automatically."
        echo "  Self-healing was attempted but the issue persists."
        echo
        echo "  Please try these steps:"
        echo
        echo "  1. Reboot the device:"
        echo "       sudo reboot"
        echo
        echo "  2. If still not working, run diagnostics:"
        echo "       /opt/argus/bin/diagnose.sh"
        echo
        echo "  3. Full repair (requires cloud credentials):"
        echo "       sudo /opt/argus/bin/repair.sh --fix-deps"
        echo "  ─────────────────────────────────────────────────"
    fi
    echo
}

# ============ Main ============

main() {
    echo
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}         ARGUS EDGE INSTALLER v${ARGUS_VERSION} (Headless)${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo

    check_root

    # Clean up any prior installation first (fresh install every time)
    cleanup_prior_installation

    install_system_deps
    install_cloudflared
    create_user
    create_directories
    setup_python_env
    install_edge_scripts
    create_provision_server
    create_recovery_scripts
    configure_udev_rules
    install_systemd_services
    create_default_config
    configure_sudoers
    configure_log_limits

    print_completion
}

main "$@"
