#!/bin/bash
#
# Argus Edge Uninstaller
# Cleanly removes all Argus components from edge device
#
# Usage:
#   sudo ./edge/uninstall.sh
#   sudo ./edge/uninstall.sh --keep-data   # Preserve queue database
#

set -e

# ============ Configuration ============

ARGUS_HOME="/opt/argus"
ARGUS_USER="argus"
CONFIG_FILE="/etc/argus/config.env"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
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

# ============ Parse Arguments ============

KEEP_DATA=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --keep-data)
            KEEP_DATA=true
            shift
            ;;
        -h|--help)
            echo "Usage: sudo ./uninstall.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --keep-data    Preserve data files (queue database, logs)"
            echo "  -h, --help     Show this help message"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# ============ Main Uninstall ============

print_banner() {
    echo -e "${RED}"
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║                                                               ║"
    echo "║              ARGUS EDGE UNINSTALLER                           ║"
    echo "║                                                               ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

confirm_uninstall() {
    echo
    echo -e "${YELLOW}WARNING: This will remove all Argus components:${NC}"
    echo "  - Stop and disable all Argus services"
    echo "  - Remove systemd service files"
    echo "  - Remove udev rules"
    echo "  - Remove $ARGUS_HOME directory"
    echo "  - Remove $CONFIG_FILE"
    if [ "$KEEP_DATA" = true ]; then
        echo -e "  ${GREEN}- Data files will be PRESERVED${NC}"
    else
        echo "  - Remove all data files (queue, logs)"
    fi
    echo

    read -p "Are you sure you want to uninstall Argus? [y/N] " confirm
    if [[ ! "$confirm" =~ ^[Yy] ]]; then
        echo "Uninstall cancelled."
        exit 0
    fi
}

stop_services() {
    log_info "Stopping Argus services..."

    local services=("argus-uplink" "argus-gps" "argus-can" "argus-ant" "argus-video")

    for service in "${services[@]}"; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            systemctl stop "$service" 2>/dev/null || true
            log_success "Stopped $service"
        fi
    done
}

disable_services() {
    log_info "Disabling Argus services..."

    local services=("argus-uplink" "argus-gps" "argus-can" "argus-ant" "argus-video")

    for service in "${services[@]}"; do
        if systemctl is-enabled --quiet "$service" 2>/dev/null; then
            systemctl disable "$service" 2>/dev/null || true
            log_success "Disabled $service"
        fi
    done
}

remove_service_files() {
    log_info "Removing systemd service files..."

    local service_files=(
        "/etc/systemd/system/argus-uplink.service"
        "/etc/systemd/system/argus-gps.service"
        "/etc/systemd/system/argus-can.service"
        "/etc/systemd/system/argus-ant.service"
        "/etc/systemd/system/argus-video.service"
    )

    for file in "${service_files[@]}"; do
        if [ -f "$file" ]; then
            rm -f "$file"
            log_success "Removed $file"
        fi
    done

    systemctl daemon-reload
    log_success "Reloaded systemd daemon"
}

remove_udev_rules() {
    log_info "Removing udev rules..."

    local udev_files=(
        "/etc/udev/rules.d/99-argus.rules"
        "/etc/udev/rules.d/99-argus-custom.rules"
    )

    for file in "${udev_files[@]}"; do
        if [ -f "$file" ]; then
            rm -f "$file"
            log_success "Removed $file"
        fi
    done

    # Reload udev rules
    udevadm control --reload-rules 2>/dev/null || true
    udevadm trigger 2>/dev/null || true
    log_success "Reloaded udev rules"
}

remove_config() {
    log_info "Removing configuration..."

    if [ -f "$CONFIG_FILE" ]; then
        rm -f "$CONFIG_FILE"
        log_success "Removed $CONFIG_FILE"
    fi

    if [ -d "/etc/argus" ]; then
        rmdir /etc/argus 2>/dev/null || log_warn "/etc/argus not empty, keeping"
    fi
}

remove_installation() {
    log_info "Removing installation directory..."

    if [ -d "$ARGUS_HOME" ]; then
        if [ "$KEEP_DATA" = true ]; then
            # Keep data directory
            log_info "Preserving data directory..."

            # Remove everything except data
            find "$ARGUS_HOME" -mindepth 1 -maxdepth 1 ! -name 'data' ! -name 'logs' -exec rm -rf {} \;
            log_success "Removed installation (preserved data)"
        else
            rm -rf "$ARGUS_HOME"
            log_success "Removed $ARGUS_HOME"
        fi
    fi
}

remove_can_config() {
    log_info "Removing CAN interface configuration..."

    if [ -f "/etc/network/interfaces.d/can0" ]; then
        rm -f "/etc/network/interfaces.d/can0"
        log_success "Removed CAN interface config"
    fi
}

remove_user() {
    log_info "Checking argus user..."

    if id "$ARGUS_USER" &>/dev/null; then
        echo
        read -p "Remove argus user? [y/N] " confirm
        if [[ "$confirm" =~ ^[Yy] ]]; then
            userdel -r "$ARGUS_USER" 2>/dev/null || userdel "$ARGUS_USER" 2>/dev/null || true
            log_success "Removed user $ARGUS_USER"
        else
            log_warn "Kept user $ARGUS_USER"
        fi
    fi
}

print_summary() {
    echo
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║           ARGUS EDGE UNINSTALL COMPLETE                       ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo
    echo "  Removed:"
    echo "  - Argus systemd services"
    echo "  - udev rules"
    echo "  - Configuration files"
    if [ "$KEEP_DATA" = true ]; then
        echo -e "  ${GREEN}- Data files preserved at $ARGUS_HOME/data${NC}"
    else
        echo "  - Installation directory"
    fi
    echo
    echo "  To reinstall:"
    echo "    sudo ./edge/install.sh"
    echo
}

main() {
    check_root
    print_banner
    confirm_uninstall

    stop_services
    disable_services
    remove_service_files
    remove_udev_rules
    remove_can_config
    remove_config
    remove_installation
    remove_user

    print_summary
}

main "$@"
