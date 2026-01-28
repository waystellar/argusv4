#!/bin/bash
#
# Argus Timing System v4.0 - Cloud Server Installer (Headless)
#
# NON-INTERACTIVE installer that sets up the cloud server in "Setup Mode".
# After installation, visit the server IP to complete configuration via web UI.
#
# Usage:
#   sudo ./install/install_cloud.sh           # Standard install
#   sudo ./install/install_cloud.sh --clean   # Uninstall first, then fresh install
#   sudo ./install/install_cloud.sh --nuke    # Remove everything including images, then fresh install
#

set -e

# ============================================
# Argument Parsing
# ============================================

CLEAN_INSTALL=false
NUKE_INSTALL=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --clean)
            CLEAN_INSTALL=true
            shift
            ;;
        --nuke)
            NUKE_INSTALL=true
            CLEAN_INSTALL=true
            shift
            ;;
        -h|--help)
            echo "Usage: sudo ./install/install_cloud.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --clean    Remove existing installation before installing (recommended for testing)"
            echo "  --nuke     Remove everything including Docker images, then fresh install"
            echo "  -h, --help Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use -h or --help for usage information"
            exit 1
            ;;
    esac
done

# ============================================
# Colors and Formatting
# ============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

print_banner() {
    echo -e "${CYAN}"
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║                                                               ║"
    echo "║     █████╗ ██████╗  ██████╗ ██╗   ██╗███████╗               ║"
    echo "║    ██╔══██╗██╔══██╗██╔════╝ ██║   ██║██╔════╝               ║"
    echo "║    ███████║██████╔╝██║  ███╗██║   ██║███████╗               ║"
    echo "║    ██╔══██║██╔══██╗██║   ██║██║   ██║╚════██║               ║"
    echo "║    ██║  ██║██║  ██║╚██████╔╝╚██████╔╝███████║               ║"
    echo "║    ╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝  ╚═════╝ ╚══════╝               ║"
    echo "║                                                               ║"
    echo "║         CLOUD SERVER INSTALLER v4.0 (Headless)               ║"
    echo "║                                                               ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_step() {
    echo -e "\n${BLUE}==>${NC} ${BOLD}$1${NC}"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

# ============================================
# Configuration
# ============================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INSTALL_DIR="/opt/argus-cloud"
API_PORT=8000
WEB_PORT=80

# ============================================
# System Detection
# ============================================

detect_system() {
    print_step "Detecting system..."

    OS_TYPE=$(uname -s)

    case "$OS_TYPE" in
        Darwin)
            OS_NAME="macOS"
            PACKAGE_MANAGER="brew"
            ;;
        Linux)
            if [ -f /etc/os-release ]; then
                . /etc/os-release
                OS_NAME="$NAME"
                OS_VERSION="$VERSION_ID"
            else
                OS_NAME="Linux"
            fi

            if command -v apt-get &> /dev/null; then
                PACKAGE_MANAGER="apt"
            elif command -v dnf &> /dev/null; then
                PACKAGE_MANAGER="dnf"
            elif command -v yum &> /dev/null; then
                PACKAGE_MANAGER="yum"
            else
                PACKAGE_MANAGER="unknown"
            fi
            ;;
        *)
            print_error "Unsupported operating system: $OS_TYPE"
            exit 1
            ;;
    esac

    print_success "OS: $OS_NAME ${OS_VERSION:-}"
    print_success "Package Manager: $PACKAGE_MANAGER"
}

# ============================================
# Root Check
# ============================================

check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "This script must be run as root (sudo)"
        echo "  Usage: sudo ./install/install_cloud.sh"
        exit 1
    fi
}

# ============================================
# Install Docker (Non-Interactive)
# ============================================

install_docker() {
    print_step "Checking Docker installation..."

    # ============================================
    # PODMAN AUTO-REPLACEMENT
    # ============================================
    # Podman emulates Docker CLI but has incompatible UID namespace behavior.
    # This script requires real Docker - automatically replace Podman if found.
    if command -v docker &> /dev/null; then
        if docker --version 2>&1 | grep -qi "podman"; then
            print_warning "Podman detected (incompatible) - replacing with Docker..."

            case "$PACKAGE_MANAGER" in
                apt)
                    # Remove Podman and related packages
                    export DEBIAN_FRONTEND=noninteractive
                    apt-get remove -y podman podman-docker docker-compose containernetworking-plugins 2>/dev/null || true
                    apt-get autoremove -y 2>/dev/null || true

                    # Clean up any leftover docker aliases
                    rm -f /etc/containers/nodocker 2>/dev/null || true
                    rm -f /usr/local/bin/docker-compose 2>/dev/null || true

                    # Install real Docker
                    print_step "Installing Docker Engine..."
                    curl -fsSL https://get.docker.com | sh

                    # Verify installation
                    if docker --version 2>&1 | grep -qi "podman"; then
                        print_error "Failed to replace Podman with Docker"
                        exit 1
                    fi
                    print_success "Docker installed successfully (replaced Podman)"
                    ;;
                *)
                    print_error "Cannot auto-replace Podman on this system."
                    echo "  Please manually remove Podman and install Docker:"
                    echo "  https://docs.docker.com/get-docker/"
                    exit 1
                    ;;
            esac
        else
            print_success "Docker $(docker --version | cut -d' ' -f3 | tr -d ',') already installed"
        fi
    else
        print_warning "Docker not found, installing..."

        case "$PACKAGE_MANAGER" in
            apt)
                # Install Docker using official script (non-interactive)
                export DEBIAN_FRONTEND=noninteractive
                curl -fsSL https://get.docker.com | sh
                ;;
            brew)
                print_error "On macOS, please install Docker Desktop manually from:"
                echo "  https://docs.docker.com/desktop/install/mac-install/"
                exit 1
                ;;
            *)
                print_error "Cannot auto-install Docker on this system."
                echo "  Please install Docker manually: https://docs.docker.com/get-docker/"
                exit 1
                ;;
        esac

        print_success "Docker installed"
    fi

    # Ensure Docker service is running first
    if systemctl is-active --quiet docker 2>/dev/null; then
        print_success "Docker service is running"
    else
        print_warning "Starting Docker service..."
        systemctl start docker 2>/dev/null || true
        systemctl enable docker 2>/dev/null || true
        sleep 2  # Give Docker time to fully start
    fi

    # Check Docker Compose V2 (plugin) - we do NOT support legacy docker-compose
    if docker compose version &> /dev/null 2>&1; then
        print_success "Docker Compose $(docker compose version --short 2>/dev/null) available"
    else
        print_warning "Docker Compose plugin not working, attempting to fix..."

        if [ "$PACKAGE_MANAGER" = "apt" ]; then
            # Remove any broken installation
            apt-get remove -y docker-compose-plugin 2>/dev/null || true

            # Method 1: Install via apt
            apt-get update
            apt-get install -y docker-compose-plugin

            # Restart Docker to pick up the plugin
            systemctl restart docker
            sleep 2

            # Verify it works now
            if ! docker compose version &> /dev/null 2>&1; then
                print_warning "apt package didn't work, trying direct download..."

                # Method 2: Direct binary download
                COMPOSE_VERSION="v2.27.0"
                COMPOSE_URL="https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-linux-x86_64"

                mkdir -p /usr/local/lib/docker/cli-plugins
                curl -SL "$COMPOSE_URL" -o /usr/local/lib/docker/cli-plugins/docker-compose
                chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

                # Also try the standard location
                mkdir -p /usr/lib/docker/cli-plugins
                cp /usr/local/lib/docker/cli-plugins/docker-compose /usr/lib/docker/cli-plugins/docker-compose

                # Final verification
                if ! docker compose version &> /dev/null 2>&1; then
                    print_error "Failed to install Docker Compose plugin"
                    echo "  Debug info:"
                    echo "    docker --version: $(docker --version)"
                    echo "    Plugin locations checked:"
                    ls -la /usr/lib/docker/cli-plugins/ 2>/dev/null || echo "      /usr/lib/docker/cli-plugins/ not found"
                    ls -la /usr/local/lib/docker/cli-plugins/ 2>/dev/null || echo "      /usr/local/lib/docker/cli-plugins/ not found"
                    exit 1
                fi
            fi

            print_success "Docker Compose $(docker compose version --short 2>/dev/null) installed"
        else
            print_error "Please install Docker Compose plugin manually"
            exit 1
        fi
    fi
}

# ============================================
# Create Installation Directory
# ============================================

setup_install_dir() {
    print_step "Setting up installation directory..."

    mkdir -p "$INSTALL_DIR"

    # Copy cloud app source code
    if [ -d "$PROJECT_ROOT/cloud" ]; then
        cp -r "$PROJECT_ROOT/cloud" "$INSTALL_DIR/"
        print_success "Copied cloud app to $INSTALL_DIR/cloud"
    else
        print_error "Cloud source not found at $PROJECT_ROOT/cloud"
        exit 1
    fi

    # Copy web app source code
    if [ -d "$PROJECT_ROOT/web" ]; then
        cp -r "$PROJECT_ROOT/web" "$INSTALL_DIR/"
        print_success "Copied web app to $INSTALL_DIR/web"
    else
        print_warning "Web source not found at $PROJECT_ROOT/web (optional)"
    fi
}

# ============================================
# Generate Setup Mode Environment
# ============================================

generate_setup_env() {
    print_step "Generating setup mode configuration..."

    # Create .env file with SETUP_COMPLETED=false
    # Database and Redis connect to Docker containers
    cat > "$INSTALL_DIR/.env" << 'EOF'
# Argus Cloud Configuration
# ===========================
# This file puts the server in SETUP MODE.
# Visit http://<server-ip>:8000/setup to complete configuration.

# Setup mode flag - web wizard will set this to true after configuration
SETUP_COMPLETED=false

# Temporary defaults for setup mode (will be overwritten by wizard)
DEBUG=true
LOG_LEVEL=INFO

# Database - connects to PostgreSQL container
DATABASE_URL=postgresql+asyncpg://argus:argus_dev_password@postgres:5432/argus

# Redis - connects to Redis container
REDIS_URL=redis://redis:6379

# Placeholder tokens (setup wizard generates real ones)
AUTH_TOKENS=setup_mode_token
ADMIN_TOKENS=setup_mode_admin

# Default CORS (wide open for setup, wizard will restrict)
CORS_ORIGINS=["*"]

# Rate limiting
RATE_LIMIT_PUBLIC=100
RATE_LIMIT_TRUCKS=1000
EOF

    # CRITICAL: Container runs as UID 1000 (argus user) and needs to WRITE this file
    # during setup wizard completion. File must be writable by container user.
    chown 1000:1000 "$INSTALL_DIR/.env"
    chmod 644 "$INSTALL_DIR/.env"
    print_success "Setup mode .env created (owned by container user UID 1000)"
}

# ============================================
# Generate Docker Compose
# ============================================

generate_docker_compose() {
    print_step "Generating Docker Compose configuration..."

    cat > "$INSTALL_DIR/docker-compose.yml" << EOF
# Argus Timing System v4.0 - Setup Mode
# Generated: $(date)
#
# This configuration runs in SETUP MODE.
# Visit http://<server-ip>:${API_PORT}/setup to complete configuration.

services:
  # PostgreSQL Database
  postgres:
    image: postgres:16-alpine
    container_name: argus-postgres
    environment:
      POSTGRES_USER: argus
      POSTGRES_PASSWORD: argus_dev_password
      POSTGRES_DB: argus
    volumes:
      - postgres-data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U argus -d argus"]
      interval: 5s
      timeout: 5s
      retries: 5
    restart: unless-stopped

  # Redis Cache (for SSE pub/sub and caching)
  redis:
    image: redis:7-alpine
    container_name: argus-redis
    volumes:
      - redis-data:/data
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      timeout: 5s
      retries: 5
    restart: unless-stopped

  # Argus API Server (internal - accessed via web nginx proxy)
  api:
    build:
      context: ./cloud
      dockerfile: Dockerfile
    container_name: argus-api
    # Run as root inside container to avoid UID namespace issues
    user: "0:0"
    # NOTE: We do NOT use env_file here. Pydantic reads the mounted .env directly.
    # This allows the setup wizard to update .env and have changes take effect on restart.
    # API is not exposed externally - web service proxies to it
    expose:
      - "8000"
    volumes:
      - argus-data:/data
      - ./cloud/app:/app/app:ro
      # CRITICAL: .env must be WRITABLE for setup wizard to save configuration
      # Pydantic-settings reads this file directly (not via Docker env_file)
      - ./.env:/app/.env:rw
    command: ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--reload"]
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8000/health"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 30s

  # Argus Web Frontend (nginx serving React + proxying API)
  web:
    build:
      context: ./web
      dockerfile: Dockerfile.prod
    container_name: argus-web
    ports:
      - "${WEB_PORT}:80"
    depends_on:
      api:
        condition: service_healthy
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-sf", "http://localhost/health-check"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 10s

volumes:
  argus-data:
  postgres-data:
  redis-data:

networks:
  default:
    name: argus-network
EOF

    print_success "Docker Compose configuration generated"
}

# ============================================
# Build and Start Containers
# ============================================

build_and_start() {
    print_step "Building and starting containers..."

    cd "$INSTALL_DIR"

    # Verify docker compose works before attempting to use it
    if ! docker compose version &> /dev/null; then
        print_error "docker compose is not working!"
        echo "  Debug info:"
        echo "    docker --version: $(docker --version 2>&1)"
        echo "    docker compose version: $(docker compose version 2>&1 || echo 'FAILED')"
        echo
        echo "  Try running: systemctl restart docker"
        exit 1
    fi

    print_success "Docker Compose $(docker compose version --short) verified"

    # Stop any existing containers first (for clean rebuild)
    print_step "Stopping existing containers (if any)..."
    docker compose down -v 2>/dev/null || true

    # Force rebuild to pick up any dependency changes (e.g., requirements.txt)
    print_step "Building container images..."
    docker compose build
    local build_exit=$?

    if [ $build_exit -ne 0 ]; then
        print_error "docker compose build failed with exit code: $build_exit"
        echo
        echo "  To debug manually, run:"
        echo "    cd $INSTALL_DIR"
        echo "    docker compose build"
        echo
        exit $build_exit
    fi

    print_success "Container images built"

    # Start containers
    print_step "Starting containers..."
    docker compose up -d
    local exit_code=$?

    if [ $exit_code -ne 0 ]; then
        print_error "docker compose up -d failed with exit code: $exit_code"
        echo
        echo "  To debug manually, run:"
        echo "    cd $INSTALL_DIR"
        echo "    docker compose up"
        echo
        exit $exit_code
    fi

    print_success "Containers started"

    # Wait for database to be ready first
    print_step "Waiting for database to be ready..."
    for i in {1..30}; do
        if docker compose exec -T postgres pg_isready -U argus -d argus &> /dev/null; then
            print_success "PostgreSQL is ready"
            break
        fi
        sleep 1
    done

    # Wait for API to be ready
    echo -n "  Waiting for API to be ready"
    local api_ready=false
    for i in {1..45}; do
        if docker compose exec -T api curl -sf http://localhost:8000/health > /dev/null 2>&1; then
            echo
            print_success "API is ready"
            api_ready=true
            break
        fi
        echo -n "."
        sleep 2
    done

    if [ "$api_ready" = false ]; then
        echo
        print_error "API failed to start within timeout!"
        echo
        echo -e "${RED}═══════════════════════════════════════════════════════════════${NC}"
        echo -e "${RED}                    CONTAINER LOGS (argus-api)                  ${NC}"
        echo -e "${RED}═══════════════════════════════════════════════════════════════${NC}"
        echo
        # Show last 50 lines of API container logs
        docker logs argus-api --tail 50 2>&1
        echo
        echo -e "${RED}═══════════════════════════════════════════════════════════════${NC}"
        echo
        echo "  Troubleshooting steps:"
        echo "    1. Check full logs: docker logs argus-api"
        echo "    2. Check container status: docker compose ps"
        echo "    3. Check PostgreSQL: docker logs argus-postgres"
        echo "    4. Check Redis: docker logs argus-redis"
        echo "    5. Try manual start: cd $INSTALL_DIR && docker compose up"
        echo
        exit 1
    fi

    # Wait for Web frontend to be ready
    echo -n "  Waiting for web frontend to be ready"
    local web_ready=false
    for i in {1..30}; do
        if curl -s "http://localhost:${WEB_PORT}/health-check" > /dev/null 2>&1; then
            echo
            print_success "Web frontend is ready"
            web_ready=true
            break
        fi
        echo -n "."
        sleep 2
    done

    if [ "$web_ready" = false ]; then
        echo
        print_error "Web frontend failed to start within timeout!"
        echo
        docker logs argus-web --tail 30 2>&1
        echo
        echo "  Troubleshooting: docker logs argus-web"
        exit 1
    fi
}

# ============================================
# Create Management Scripts
# ============================================

create_management_scripts() {
    print_step "Creating management scripts..."

    # Start script
    cat > "$INSTALL_DIR/start.sh" << 'SCRIPT'
#!/bin/bash
cd "$(dirname "$0")"
docker compose up -d
SERVER_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "localhost")
echo "Argus started. Visit http://${SERVER_IP}"
echo "  Dashboard:  http://${SERVER_IP}"
echo "  Setup:      http://${SERVER_IP}/setup"
echo "  API Docs:   http://${SERVER_IP}/docs"
echo
echo "Check status: docker compose ps"
SCRIPT
    chmod +x "$INSTALL_DIR/start.sh"

    # Stop script
    cat > "$INSTALL_DIR/stop.sh" << 'SCRIPT'
#!/bin/bash
cd "$(dirname "$0")"
docker compose down
echo "Argus stopped."
SCRIPT
    chmod +x "$INSTALL_DIR/stop.sh"

    # Logs script
    cat > "$INSTALL_DIR/logs.sh" << 'SCRIPT'
#!/bin/bash
cd "$(dirname "$0")"
# Default to api, but allow specifying other services (postgres, redis)
docker compose logs -f "${1:-api}"
SCRIPT
    chmod +x "$INSTALL_DIR/logs.sh"

    # Status script
    cat > "$INSTALL_DIR/status.sh" << 'SCRIPT'
#!/bin/bash
cd "$(dirname "$0")"
echo "=== Container Status ==="
docker compose ps
echo
echo "=== Health Checks ==="
echo -n "Web:      "
curl -sf --max-time 5 http://localhost/health-check &>/dev/null && echo "OK" || echo "FAILED"
echo -n "API:      "
timeout 5 docker compose exec -T api curl -sf --max-time 3 http://localhost:8000/health &>/dev/null && echo "OK" || echo "FAILED"
echo -n "Postgres: "
timeout 5 docker compose exec -T postgres pg_isready -U argus -d argus &>/dev/null && echo "OK" || echo "FAILED"
echo -n "Redis:    "
timeout 5 docker compose exec -T redis redis-cli ping &>/dev/null && echo "OK" || echo "FAILED"
echo
SERVER_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "localhost")
echo "=== Access URLs ==="
echo "  Dashboard:  http://${SERVER_IP}"
echo "  Setup:      http://${SERVER_IP}/setup"
echo "  API Docs:   http://${SERVER_IP}/docs"
SCRIPT
    chmod +x "$INSTALL_DIR/status.sh"

    # Rebuild script
    cat > "$INSTALL_DIR/rebuild.sh" << 'SCRIPT'
#!/bin/bash
cd "$(dirname "$0")"
echo "Stopping containers..."
docker compose down
echo "Removing old images to force rebuild..."
docker rmi argus-cloud-api argus-cloud-web 2>/dev/null || true
echo "Building and starting..."
docker compose build
docker compose up -d
echo
echo "Waiting for services to be ready..."
sleep 10
./status.sh
SCRIPT
    chmod +x "$INSTALL_DIR/rebuild.sh"

    print_success "Management scripts created (start, stop, logs, status, rebuild)"
}

# ============================================
# Get Server IP
# ============================================

get_server_ip() {
    # Try to get the primary IP address
    if command -v hostname &> /dev/null; then
        SERVER_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
    fi

    if [ -z "$SERVER_IP" ]; then
        SERVER_IP=$(ip route get 1 2>/dev/null | awk '{print $7; exit}')
    fi

    if [ -z "$SERVER_IP" ]; then
        SERVER_IP="localhost"
    fi

    echo "$SERVER_IP"
}

# ============================================
# Print Summary
# ============================================

print_summary() {
    local server_ip=$(get_server_ip)
    local web_url="http://${server_ip}"
    if [ "${WEB_PORT}" != "80" ]; then
        web_url="http://${server_ip}:${WEB_PORT}"
    fi

    echo
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║           CLOUD INSTALLATION COMPLETE!                        ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo
    echo -e "  ${BOLD}Server is running in SETUP MODE${NC}"
    echo
    echo "  ─────────────────────────────────────────────────"
    echo
    echo -e "  ${CYAN}▶ Complete setup at:${NC}"
    echo
    echo -e "    ${BOLD}${web_url}/setup${NC}"
    echo
    echo -e "  ${CYAN}▶ After setup, access the dashboard:${NC}"
    echo
    echo -e "    ${BOLD}${web_url}${NC}"
    echo
    echo "  ─────────────────────────────────────────────────"
    echo
    echo -e "  ${BOLD}Available Dashboards:${NC}"
    echo "    • Admin Dashboard: ${web_url}/"
    echo "    • Fan View:        ${web_url}/events/<event-id>"
    echo "    • Team Login:      ${web_url}/team/login"
    echo "    • Team Dashboard:  ${web_url}/team/dashboard"
    echo "    • API Docs:        ${web_url}/docs"
    echo
    echo "  ─────────────────────────────────────────────────"
    echo
    echo -e "  ${BOLD}Running Services:${NC}"
    echo "    • Web Frontend (nginx + React) - port ${WEB_PORT}"
    echo "    • API Server (FastAPI) - internal"
    echo "    • PostgreSQL Database - internal"
    echo "    • Redis Cache - internal"
    echo
    echo "  ─────────────────────────────────────────────────"
    echo
    echo -e "  ${BOLD}Management Commands:${NC}"
    echo "    Start:    $INSTALL_DIR/start.sh"
    echo "    Stop:     $INSTALL_DIR/stop.sh"
    echo "    Status:   $INSTALL_DIR/status.sh"
    echo "    Logs:     $INSTALL_DIR/logs.sh [api|web|postgres|redis]"
    echo "    Rebuild:  $INSTALL_DIR/rebuild.sh"
    echo
    echo "  ─────────────────────────────────────────────────"
    echo
    echo -e "  ${BOLD}Quick Check:${NC}"
    echo "    curl ${web_url}/health"
    echo "    $INSTALL_DIR/status.sh"
    echo
}

# ============================================
# Clean Install (Uninstall First)
# ============================================

perform_cleanup() {
    if [ "$CLEAN_INSTALL" != true ]; then
        return
    fi

    print_step "Performing clean uninstall before installation..."

    # Stop containers if compose file exists
    if [ -f "$INSTALL_DIR/docker-compose.yml" ]; then
        cd "$INSTALL_DIR"
        docker compose down -v 2>/dev/null || true
        print_success "Stopped and removed containers"
    fi

    # Stop any argus containers directly
    local containers=$(docker ps -a --filter "name=argus" --format "{{.Names}}" 2>/dev/null || true)
    if [ -n "$containers" ]; then
        for container in $containers; do
            docker stop "$container" 2>/dev/null || true
            docker rm "$container" 2>/dev/null || true
        done
        print_success "Removed argus containers"
    fi

    # Remove volumes
    local volumes=$(docker volume ls --filter "name=argus" --format "{{.Name}}" 2>/dev/null || true)
    if [ -n "$volumes" ]; then
        for volume in $volumes; do
            docker volume rm "$volume" 2>/dev/null || true
        done
        print_success "Removed Docker volumes"
    fi

    # Also check for compose-created volumes (with directory prefix)
    local compose_volumes=$(docker volume ls --format "{{.Name}}" 2>/dev/null | grep -E "(argus|opt.*argus)" || true)
    if [ -n "$compose_volumes" ]; then
        for volume in $compose_volumes; do
            docker volume rm "$volume" 2>/dev/null || true
        done
    fi

    # Remove network
    docker network rm argus-network 2>/dev/null || true

    # Remove images if nuke mode
    if [ "$NUKE_INSTALL" = true ]; then
        print_step "Removing Docker images (nuke mode)..."
        local images=$(docker images --format "{{.Repository}}:{{.Tag}}" 2>/dev/null | grep -E "(argus)" || true)
        if [ -n "$images" ]; then
            for image in $images; do
                docker rmi "$image" 2>/dev/null || true
            done
            print_success "Removed argus images"
        fi
        # Clean up dangling images
        docker image prune -f 2>/dev/null || true
    fi

    # Remove install directory
    if [ -d "$INSTALL_DIR" ]; then
        rm -rf "$INSTALL_DIR"
        print_success "Removed $INSTALL_DIR"
    fi

    print_success "Clean uninstall complete, proceeding with fresh installation..."
    echo
}

# ============================================
# Main
# ============================================

main() {
    print_banner
    check_root
    detect_system
    perform_cleanup
    install_docker
    setup_install_dir
    generate_setup_env
    generate_docker_compose
    build_and_start
    create_management_scripts
    print_summary
}

main "$@"
