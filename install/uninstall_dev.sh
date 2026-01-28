#!/bin/bash
#
# Argus Development Environment Cleaner
# Removes all development artifacts for a fresh start
#
# Usage:
#   ./install/uninstall_dev.sh             # Standard cleanup
#   ./install/uninstall_dev.sh --deep      # Also remove node_modules, __pycache__
#   ./install/uninstall_dev.sh --nuke      # Remove EVERYTHING including .git ignored files
#

set -e

# ============ Configuration ============

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

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

DEEP_CLEAN=false
NUKE_MODE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --deep)
            DEEP_CLEAN=true
            shift
            ;;
        --nuke)
            NUKE_MODE=true
            DEEP_CLEAN=true
            shift
            ;;
        -h|--help)
            echo "Usage: ./uninstall_dev.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --deep     Deep clean: also remove node_modules, __pycache__, tool caches"
            echo "  --nuke     Nuclear option: remove everything including Docker, all caches"
            echo "  -h, --help Show this help message"
            echo ""
            echo "What gets removed:"
            echo "  Standard:  .venv, test/, *.db files, .env files, generated configs"
            echo "  Deep:      + node_modules, __pycache__, .pytest_cache, .mypy_cache,"
            echo "             .ruff_cache, .coverage, htmlcov, build artifacts"
            echo "  Nuke:      + Docker containers/volumes/images, all git-ignored files"
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
    echo "║              ARGUS DEV ENVIRONMENT CLEANER                    ║"
    echo "║                                                               ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

show_cleanup_plan() {
    echo
    echo -e "${YELLOW}Cleanup Plan:${NC}"
    echo
    echo "  Standard cleanup:"
    echo "    - Python virtual environment (.venv/)"
    echo "    - Test directory and configs (test/)"
    echo "    - SQLite database files (*.db, *.db-wal, *.db-shm)"
    echo "    - Generated .env files"

    if [ "$DEEP_CLEAN" = true ]; then
        echo
        echo "  Deep clean (--deep):"
        echo "    - Node modules (web/node_modules/)"
        echo "    - Python cache (__pycache__/, *.pyc)"
        echo "    - Pytest cache (.pytest_cache/)"
        echo "    - Tool caches (.mypy_cache, .ruff_cache, .coverage, htmlcov)"
        echo "    - Build artifacts (dist/, build/, *.egg-info)"
    fi

    if [ "$NUKE_MODE" = true ]; then
        echo
        echo -e "  ${RED}Nuclear clean (--nuke):${NC}"
        echo "    - Docker containers, volumes, images"
        echo "    - All git-ignored files"
        echo "    - Package lock files"
    fi

    echo
}

confirm_uninstall() {
    show_cleanup_plan

    local prompt="Proceed with cleanup?"
    if [ "$NUKE_MODE" = true ]; then
        prompt="This will remove A LOT of files. Are you sure?"
    fi

    read -p "$prompt [y/N] " confirm
    if [[ ! "$confirm" =~ ^[Yy] ]]; then
        echo "Cleanup cancelled."
        exit 0
    fi
}

remove_venv() {
    log_info "Removing Python virtual environment..."

    if [ -d "$PROJECT_ROOT/.venv" ]; then
        rm -rf "$PROJECT_ROOT/.venv"
        log_success "Removed .venv/"
    else
        log_warn ".venv/ not found"
    fi
}

remove_test_dir() {
    log_info "Removing test directory..."

    if [ -d "$PROJECT_ROOT/test" ]; then
        rm -rf "$PROJECT_ROOT/test"
        log_success "Removed test/"
    else
        log_warn "test/ not found"
    fi
}

remove_database_files() {
    log_info "Removing database files..."

    local count=0

    # Find and remove all .db files
    while IFS= read -r -d '' file; do
        rm -f "$file"
        log_success "Removed $(basename "$file")"
        ((count++))
    done < <(find "$PROJECT_ROOT" -name "*.db" -type f -print0 2>/dev/null)

    # Remove WAL and SHM files
    while IFS= read -r -d '' file; do
        rm -f "$file"
        ((count++))
    done < <(find "$PROJECT_ROOT" -name "*.db-wal" -o -name "*.db-shm" -type f -print0 2>/dev/null)

    if [ $count -eq 0 ]; then
        log_warn "No database files found"
    fi
}

remove_env_files() {
    log_info "Removing generated .env files..."

    local env_files=(
        "$PROJECT_ROOT/web/.env"
        "$PROJECT_ROOT/cloud/.env"
        "$PROJECT_ROOT/.env"
    )

    for file in "${env_files[@]}"; do
        if [ -f "$file" ]; then
            rm -f "$file"
            log_success "Removed $(basename "$file")"
        fi
    done
}

# ============ Deep Clean Functions ============

remove_node_modules() {
    log_info "Removing node_modules..."

    if [ -d "$PROJECT_ROOT/web/node_modules" ]; then
        rm -rf "$PROJECT_ROOT/web/node_modules"
        log_success "Removed web/node_modules/"
    else
        log_warn "web/node_modules/ not found"
    fi
}

remove_python_cache() {
    log_info "Removing Python cache..."

    local count=0

    # Remove __pycache__ directories
    while IFS= read -r -d '' dir; do
        rm -rf "$dir"
        ((count++))
    done < <(find "$PROJECT_ROOT" -name "__pycache__" -type d -print0 2>/dev/null)

    # Remove .pyc files
    while IFS= read -r -d '' file; do
        rm -f "$file"
        ((count++))
    done < <(find "$PROJECT_ROOT" -name "*.pyc" -type f -print0 2>/dev/null)

    # Remove .pyo files
    while IFS= read -r -d '' file; do
        rm -f "$file"
        ((count++))
    done < <(find "$PROJECT_ROOT" -name "*.pyo" -type f -print0 2>/dev/null)

    if [ $count -gt 0 ]; then
        log_success "Removed $count Python cache items"
    else
        log_warn "No Python cache found"
    fi
}

remove_pytest_cache() {
    log_info "Removing pytest cache..."

    local count=0

    while IFS= read -r -d '' dir; do
        rm -rf "$dir"
        ((count++))
    done < <(find "$PROJECT_ROOT" -name ".pytest_cache" -type d -print0 2>/dev/null)

    if [ $count -gt 0 ]; then
        log_success "Removed $count pytest cache directories"
    else
        log_warn "No pytest cache found"
    fi
}

remove_tool_caches() {
    log_info "Removing tool caches (mypy, ruff, coverage)..."

    local cache_dirs=(
        ".mypy_cache"
        ".ruff_cache"
        ".coverage"
        "htmlcov"
        ".hypothesis"
        ".tox"
        ".nox"
    )

    local count=0
    for cache_name in "${cache_dirs[@]}"; do
        while IFS= read -r -d '' dir; do
            rm -rf "$dir"
            ((count++))
        done < <(find "$PROJECT_ROOT" -name "$cache_name" -type d -print0 2>/dev/null)
    done

    # Also remove coverage files
    while IFS= read -r -d '' file; do
        rm -f "$file"
        ((count++))
    done < <(find "$PROJECT_ROOT" -name ".coverage*" -type f -print0 2>/dev/null)

    if [ $count -gt 0 ]; then
        log_success "Removed $count tool cache items"
    fi
}

remove_build_artifacts() {
    log_info "Removing build artifacts..."

    local dirs=(
        "$PROJECT_ROOT/cloud/dist"
        "$PROJECT_ROOT/cloud/build"
        "$PROJECT_ROOT/web/dist"
        "$PROJECT_ROOT/web/build"
        "$PROJECT_ROOT/edge/dist"
        "$PROJECT_ROOT/edge/build"
    )

    for dir in "${dirs[@]}"; do
        if [ -d "$dir" ]; then
            rm -rf "$dir"
            log_success "Removed $dir"
        fi
    done

    # Remove egg-info directories
    while IFS= read -r -d '' dir; do
        rm -rf "$dir"
        log_success "Removed $(basename "$dir")"
    done < <(find "$PROJECT_ROOT" -name "*.egg-info" -type d -print0 2>/dev/null)
}

# ============ Nuke Functions ============

nuke_docker() {
    log_info "Nuking Docker resources..."

    # Stop and remove containers
    local containers=$(docker ps -a --filter "name=argus" --format "{{.Names}}" 2>/dev/null || true)
    if [ -n "$containers" ]; then
        for container in $containers; do
            docker stop "$container" 2>/dev/null || true
            docker rm "$container" 2>/dev/null || true
            log_success "Removed container: $container"
        done
    fi

    # Remove volumes
    local volumes=$(docker volume ls --filter "name=argus" --format "{{.Name}}" 2>/dev/null || true)
    if [ -n "$volumes" ]; then
        for volume in $volumes; do
            docker volume rm "$volume" 2>/dev/null || true
            log_success "Removed volume: $volume"
        done
    fi

    # Remove images
    local images=$(docker images --filter "reference=*argus*" --format "{{.Repository}}:{{.Tag}}" 2>/dev/null || true)
    if [ -n "$images" ]; then
        for image in $images; do
            docker rmi "$image" 2>/dev/null || true
            log_success "Removed image: $image"
        done
    fi

    # Remove network
    docker network rm argus-network 2>/dev/null || true

    # Prune dangling images
    docker image prune -f 2>/dev/null || true
}

nuke_git_ignored() {
    log_info "Removing git-ignored files (excluding .git)..."

    if command -v git &> /dev/null && [ -d "$PROJECT_ROOT/.git" ]; then
        cd "$PROJECT_ROOT"
        # Use git clean to remove all ignored files, but be careful
        git clean -fdX 2>/dev/null || log_warn "git clean failed"
        log_success "Removed git-ignored files"
    else
        log_warn "Git not available or not a git repo"
    fi
}

remove_lock_files() {
    log_info "Removing lock files..."

    local lock_files=(
        "$PROJECT_ROOT/web/package-lock.json"
        "$PROJECT_ROOT/web/yarn.lock"
        "$PROJECT_ROOT/web/pnpm-lock.yaml"
    )

    for file in "${lock_files[@]}"; do
        if [ -f "$file" ]; then
            rm -f "$file"
            log_success "Removed $(basename "$file")"
        fi
    done
}

# ============ Verification ============

verify_cleanup() {
    log_info "Verifying cleanup..."

    local has_remnants=false

    # Check for venv
    if [ -d "$PROJECT_ROOT/.venv" ]; then
        log_warn "Virtual environment still exists: .venv/"
        has_remnants=true
    fi

    # Check for database files
    local db_count=$(find "$PROJECT_ROOT" -name "*.db" -type f 2>/dev/null | wc -l)
    if [ "$db_count" -gt 0 ]; then
        log_warn "Database files still exist: $db_count file(s)"
        has_remnants=true
    fi

    # Check for node_modules (if deep clean)
    if [ "$DEEP_CLEAN" = true ] && [ -d "$PROJECT_ROOT/web/node_modules" ]; then
        log_warn "node_modules still exists"
        has_remnants=true
    fi

    if [ "$has_remnants" = false ]; then
        log_success "Development environment is clean!"
    fi
}

# ============ Summary ============

print_summary() {
    echo
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║           DEV ENVIRONMENT CLEANUP COMPLETE                    ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo
    echo "  Your development environment has been cleaned."
    echo
    echo "  To set up fresh:"
    echo "    ./install/install_dev.sh"
    echo
    if [ "$DEEP_CLEAN" = true ]; then
        echo "  Note: node_modules was removed. Run 'npm install' in web/ to restore."
    fi
    echo
}

# ============ Main ============

main() {
    print_banner
    confirm_uninstall

    echo
    log_info "Starting cleanup..."
    echo

    # Standard cleanup
    remove_venv
    remove_test_dir
    remove_database_files
    remove_env_files

    # Deep clean
    if [ "$DEEP_CLEAN" = true ]; then
        echo
        log_info "Deep cleaning..."
        echo
        remove_node_modules
        remove_python_cache
        remove_pytest_cache
        remove_tool_caches
        remove_build_artifacts
    fi

    # Nuclear option
    if [ "$NUKE_MODE" = true ]; then
        echo
        log_info "Nuclear cleaning..."
        echo
        nuke_docker
        remove_lock_files
        nuke_git_ignored
    fi

    echo
    verify_cleanup
    print_summary
}

main "$@"
