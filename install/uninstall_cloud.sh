#!/bin/bash
#
# Argus Cloud Uninstaller
# Cleanly removes all Argus cloud components
#
# Usage:
#   ./install/uninstall_cloud.sh
#   ./install/uninstall_cloud.sh --keep-data    # Preserve database volumes
#   ./install/uninstall_cloud.sh --nuke         # Remove EVERYTHING including images
#

set -e

# ============ Configuration ============

INSTALL_DIR="/opt/argus-cloud"

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

# ============ Parse Arguments ============

KEEP_DATA=false
NUKE_MODE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --keep-data)
            KEEP_DATA=true
            shift
            ;;
        --nuke)
            NUKE_MODE=true
            shift
            ;;
        -h|--help)
            echo "Usage: ./uninstall_cloud.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --keep-data    Preserve Docker volumes (database data)"
            echo "  --nuke         Remove everything including Docker images"
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
    echo "║              ARGUS CLOUD UNINSTALLER                          ║"
    echo "║                                                               ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

confirm_uninstall() {
    echo
    echo -e "${YELLOW}WARNING: This will remove Argus cloud components:${NC}"
    echo "  - Stop and remove Docker containers"
    if [ "$KEEP_DATA" = true ]; then
        echo -e "  ${GREEN}- Docker volumes will be PRESERVED${NC}"
    else
        echo "  - Remove Docker volumes (database data)"
    fi
    if [ "$NUKE_MODE" = true ]; then
        echo -e "  ${RED}- Remove Docker images (full cleanup)${NC}"
    fi
    echo "  - Remove $INSTALL_DIR directory"
    echo

    read -p "Are you sure you want to uninstall Argus Cloud? [y/N] " confirm
    if [[ ! "$confirm" =~ ^[Yy] ]]; then
        echo "Uninstall cancelled."
        exit 0
    fi
}

stop_containers() {
    log_info "Stopping Docker containers..."

    # Check if docker compose is available
    if docker compose version &> /dev/null 2>&1; then
        COMPOSE_CMD="docker compose"
    elif command -v docker-compose &> /dev/null; then
        COMPOSE_CMD="docker-compose"
    else
        log_warn "Docker Compose not found, trying direct docker commands"
        COMPOSE_CMD=""
    fi

    # Try to stop via compose file first
    if [ -n "$COMPOSE_CMD" ] && [ -f "$INSTALL_DIR/docker-compose.yml" ]; then
        cd "$INSTALL_DIR"
        $COMPOSE_CMD down --remove-orphans 2>/dev/null || true
        log_success "Stopped containers via docker-compose"
    fi

    # Also check project root deploy directory
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

    local compose_files=(
        "$PROJECT_ROOT/deploy/docker-compose.yml"
        "$PROJECT_ROOT/deploy/docker-compose.prod.yml"
        "$PROJECT_ROOT/docker-compose.yml"
    )

    for compose_file in "${compose_files[@]}"; do
        if [ -n "$COMPOSE_CMD" ] && [ -f "$compose_file" ]; then
            cd "$(dirname "$compose_file")"
            $COMPOSE_CMD -f "$(basename "$compose_file")" down --remove-orphans 2>/dev/null || true
            log_success "Stopped containers from $compose_file"
        fi
    done

    # Comprehensive container name patterns
    local container_patterns=(
        "argus"
        "postgres"
        "redis"
    )

    for pattern in "${container_patterns[@]}"; do
        local containers=$(docker ps -a --filter "name=$pattern" --format "{{.Names}}" 2>/dev/null || true)
        if [ -n "$containers" ]; then
            for container in $containers; do
                # Only remove if it looks like an argus-related container
                if [[ "$container" == *argus* ]] || [[ "$container" == *postgres* && "$container" != *other* ]] || [[ "$container" == *redis* && "$container" != *other* ]]; then
                    docker stop "$container" 2>/dev/null || true
                    docker rm -f "$container" 2>/dev/null || true
                    log_success "Removed container: $container"
                fi
            done
        fi
    done
}

remove_volumes() {
    if [ "$KEEP_DATA" = true ]; then
        log_info "Preserving Docker volumes..."
        return
    fi

    log_info "Removing Docker volumes..."

    # Comprehensive volume patterns to catch all compose naming variations
    local volume_patterns=(
        "argus"
        "opt_argus"
        "deploy_"
        "argus-cloud"
        "pgdata"
    )

    for pattern in "${volume_patterns[@]}"; do
        local volumes=$(docker volume ls --filter "name=$pattern" --format "{{.Name}}" 2>/dev/null || true)
        if [ -n "$volumes" ]; then
            for volume in $volumes; do
                docker volume rm "$volume" 2>/dev/null || true
                log_success "Removed volume: $volume"
            done
        fi
    done

    # Also try to remove any orphaned volumes from our project
    if [ -d "$INSTALL_DIR" ]; then
        cd "$INSTALL_DIR"
        if [ -n "$COMPOSE_CMD" ]; then
            $COMPOSE_CMD down -v 2>/dev/null || true
        fi
    fi
}

remove_network() {
    log_info "Removing Docker networks..."

    # Comprehensive network patterns
    local network_patterns=(
        "argus"
        "deploy_"
        "argus-cloud"
    )

    for pattern in "${network_patterns[@]}"; do
        local networks=$(docker network ls --filter "name=$pattern" --format "{{.Name}}" 2>/dev/null || true)
        if [ -n "$networks" ]; then
            for network in $networks; do
                # Don't try to remove default networks
                if [[ "$network" != "bridge" && "$network" != "host" && "$network" != "none" ]]; then
                    docker network rm "$network" 2>/dev/null || true
                    log_success "Removed network: $network"
                fi
            done
        fi
    done
}

remove_images() {
    if [ "$NUKE_MODE" != true ]; then
        return
    fi

    log_info "Removing Docker images..."

    local images=$(docker images --filter "reference=*argus*" --format "{{.Repository}}:{{.Tag}}" 2>/dev/null || true)
    if [ -n "$images" ]; then
        for image in $images; do
            docker rmi "$image" 2>/dev/null || true
            log_success "Removed image: $image"
        done
    fi

    # Also remove any dangling images from argus builds
    docker image prune -f 2>/dev/null || true
}

remove_install_dir() {
    log_info "Removing installation directory..."

    if [ -d "$INSTALL_DIR" ]; then
        rm -rf "$INSTALL_DIR"
        log_success "Removed $INSTALL_DIR"
    fi
}

remove_deploy_volumes() {
    # Check for local SQLite databases in deploy directory
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

    if [ "$KEEP_DATA" = true ]; then
        return
    fi

    log_info "Checking for local database files..."

    local db_files=(
        "$PROJECT_ROOT/cloud/timing.db"
        "$PROJECT_ROOT/cloud/timing.db-wal"
        "$PROJECT_ROOT/cloud/timing.db-shm"
        "$PROJECT_ROOT/test/timing.db"
        "$PROJECT_ROOT/test/timing.db-wal"
        "$PROJECT_ROOT/test/timing.db-shm"
    )

    for file in "${db_files[@]}"; do
        if [ -f "$file" ]; then
            rm -f "$file"
            log_success "Removed $file"
        fi
    done
}

verify_cleanup() {
    log_info "Verifying cleanup..."

    local has_remnants=false

    # Check for remaining containers
    local remaining_containers=$(docker ps -a --filter "name=argus" --format "{{.Names}}" 2>/dev/null || true)
    if [ -n "$remaining_containers" ]; then
        log_warn "Remaining containers found:"
        echo "$remaining_containers" | while read -r c; do echo "    - $c"; done
        has_remnants=true
    fi

    # Check for remaining volumes
    local remaining_volumes=$(docker volume ls --format "{{.Name}}" 2>/dev/null | grep -E "(argus|pgdata)" || true)
    if [ -n "$remaining_volumes" ]; then
        log_warn "Remaining volumes found:"
        echo "$remaining_volumes" | while read -r v; do echo "    - $v"; done
        has_remnants=true
    fi

    # Check for remaining networks
    local remaining_networks=$(docker network ls --format "{{.Name}}" 2>/dev/null | grep -E "argus" || true)
    if [ -n "$remaining_networks" ]; then
        log_warn "Remaining networks found:"
        echo "$remaining_networks" | while read -r n; do echo "    - $n"; done
        has_remnants=true
    fi

    if [ "$has_remnants" = false ]; then
        log_success "Docker environment is clean!"
    else
        echo
        log_warn "Some Docker resources remain. To force remove:"
        echo "    docker rm -f \$(docker ps -aq --filter 'name=argus')"
        echo "    docker volume rm \$(docker volume ls -q | grep -E 'argus|pgdata')"
        echo "    docker network rm \$(docker network ls -q --filter 'name=argus')"
    fi
}

print_summary() {
    echo
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║           ARGUS CLOUD UNINSTALL COMPLETE                      ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo
    echo "  Removed:"
    echo "  - Docker containers"
    if [ "$KEEP_DATA" = true ]; then
        echo -e "  ${GREEN}- Volumes preserved (database data intact)${NC}"
    else
        echo "  - Docker volumes"
    fi
    if [ "$NUKE_MODE" = true ]; then
        echo "  - Docker images"
    fi
    echo "  - Installation directory"
    echo
    echo "  To reinstall:"
    echo "    ./install/install_cloud.sh"
    echo
    if [ "$KEEP_DATA" = true ]; then
        echo "  Note: Your database data is preserved in Docker volumes."
        echo "  To fully clean up data, run:"
        echo "    docker volume ls | grep argus"
        echo "    docker volume rm <volume_name>"
    fi
    echo
}

main() {
    print_banner
    confirm_uninstall

    stop_containers
    remove_volumes
    remove_network
    remove_images
    remove_install_dir
    remove_deploy_volumes

    echo
    verify_cleanup
    print_summary
}

main "$@"
