#!/bin/bash
#
# Argus Timing System v4.0 - Development Environment Setup
#
# Interactive setup for local development and virtual testing
#
# Usage:
#   ./install/install_dev.sh
#

set -e

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
    echo "║          DEVELOPMENT ENVIRONMENT SETUP v4.0                   ║"
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

prompt_input() {
    local prompt="$1"
    local default="$2"
    local var_name="$3"

    if [ -n "$default" ]; then
        read -p "$(echo -e "${CYAN}?${NC} ${prompt} [${default}]: ")" input
        eval "$var_name=\"${input:-$default}\""
    else
        read -p "$(echo -e "${CYAN}?${NC} ${prompt}: ")" input
        eval "$var_name=\"$input\""
    fi
}

prompt_yes_no() {
    local prompt="$1"
    local default="$2"

    if [ "$default" = "y" ]; then
        read -p "$(echo -e "${CYAN}?${NC} ${prompt} [Y/n]: ")" input
        input="${input:-y}"
    else
        read -p "$(echo -e "${CYAN}?${NC} ${prompt} [y/N]: ")" input
        input="${input:-n}"
    fi

    [[ "$input" =~ ^[Yy] ]]
}

# ============================================
# System Detection
# ============================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

detect_system() {
    print_step "Detecting system..."

    OS_TYPE=$(uname -s)

    case "$OS_TYPE" in
        Darwin)
            OS_NAME="macOS"
            PACKAGE_MANAGER="brew"
            ;;
        Linux)
            OS_NAME="Linux"
            if command -v apt-get &> /dev/null; then
                PACKAGE_MANAGER="apt"
            elif command -v dnf &> /dev/null; then
                PACKAGE_MANAGER="dnf"
            else
                PACKAGE_MANAGER="unknown"
            fi
            ;;
        *)
            print_error "Unsupported operating system: $OS_TYPE"
            exit 1
            ;;
    esac

    echo "  OS: $OS_NAME"
    echo "  Package Manager: $PACKAGE_MANAGER"
    echo "  Project Root: $PROJECT_ROOT"
}

# ============================================
# Check Prerequisites
# ============================================

check_prerequisites() {
    print_step "Checking prerequisites..."

    local missing=()

    # Python 3.10+
    if command -v python3 &> /dev/null; then
        PY_VERSION=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
        PY_MAJOR=$(echo $PY_VERSION | cut -d. -f1)
        PY_MINOR=$(echo $PY_VERSION | cut -d. -f2)

        if [ "$PY_MAJOR" -ge 3 ] && [ "$PY_MINOR" -ge 10 ]; then
            print_success "Python $PY_VERSION"
        else
            missing+=("python3.10+")
        fi
    else
        missing+=("python3")
    fi

    # Node.js 18+
    if command -v node &> /dev/null; then
        NODE_VERSION=$(node --version | sed 's/v//' | cut -d. -f1)
        if [ "$NODE_VERSION" -ge 18 ]; then
            print_success "Node.js $(node --version)"
        else
            missing+=("node18+")
        fi
    else
        missing+=("node")
    fi

    # npm
    if command -v npm &> /dev/null; then
        print_success "npm $(npm --version)"
    else
        missing+=("npm")
    fi

    # Git
    if command -v git &> /dev/null; then
        print_success "Git $(git --version | cut -d' ' -f3)"
    else
        missing+=("git")
    fi

    # Docker (optional)
    if command -v docker &> /dev/null; then
        print_success "Docker $(docker --version | cut -d' ' -f3 | tr -d ',')"
        HAS_DOCKER=true
    else
        print_warning "Docker not found (optional, for full stack testing)"
        HAS_DOCKER=false
    fi

    # Handle missing dependencies
    if [ ${#missing[@]} -gt 0 ]; then
        print_warning "Missing dependencies: ${missing[*]}"
        echo

        if prompt_yes_no "Attempt to install missing dependencies?" "y"; then
            install_missing_deps "${missing[@]}"
        else
            print_error "Cannot continue without required dependencies"
            exit 1
        fi
    fi
}

install_missing_deps() {
    local deps=("$@")

    case "$PACKAGE_MANAGER" in
        brew)
            for dep in "${deps[@]}"; do
                case "$dep" in
                    python*) brew install python@3.11 ;;
                    node*) brew install node@18 ;;
                    npm) brew install node@18 ;;
                    git) brew install git ;;
                esac
            done
            ;;
        apt)
            sudo apt-get update
            for dep in "${deps[@]}"; do
                case "$dep" in
                    python*) sudo apt-get install -y python3.11 python3.11-venv python3-pip ;;
                    node*)
                        curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
                        sudo apt-get install -y nodejs
                        ;;
                    npm) sudo apt-get install -y npm ;;
                    git) sudo apt-get install -y git ;;
                esac
            done
            ;;
        *)
            print_error "Cannot auto-install on this system. Please install manually."
            exit 1
            ;;
    esac
}

# ============================================
# Configuration
# ============================================

collect_configuration() {
    print_step "Test Configuration"
    echo

    prompt_input "Number of simulated vehicles" "5" NUM_VEHICLES
    prompt_input "Test event name" "Dev Test Race" EVENT_NAME
    prompt_input "API server port" "8000" API_PORT
    prompt_input "Frontend port" "5173" WEB_PORT

    echo
    echo -e "  ${BOLD}Configuration:${NC}"
    echo "  ─────────────────────────────────────────────────"
    echo "  Vehicles:      $NUM_VEHICLES"
    echo "  Event:         $EVENT_NAME"
    echo "  API Port:      $API_PORT"
    echo "  Frontend Port: $WEB_PORT"
    echo "  ─────────────────────────────────────────────────"
    echo

    if ! prompt_yes_no "Continue with this configuration?" "y"; then
        exit 1
    fi
}

# ============================================
# Setup Python Environment
# ============================================

setup_python_env() {
    print_step "Setting up Python virtual environment..."

    # Create venv in project root
    if [ ! -d "$PROJECT_ROOT/.venv" ]; then
        python3 -m venv "$PROJECT_ROOT/.venv"
        print_success "Created virtual environment"
    else
        print_warning "Virtual environment already exists"
    fi

    # Activate and install
    source "$PROJECT_ROOT/.venv/bin/activate"

    # Upgrade pip
    pip install --upgrade pip --quiet

    # Install cloud requirements
    if [ -f "$PROJECT_ROOT/cloud/requirements.txt" ]; then
        print_step "Installing cloud dependencies..."
        pip install -r "$PROJECT_ROOT/cloud/requirements.txt" --quiet
        print_success "Cloud dependencies installed"
    fi

    # Install edge requirements
    if [ -f "$PROJECT_ROOT/edge/requirements.txt" ]; then
        print_step "Installing edge dependencies..."
        pip install -r "$PROJECT_ROOT/edge/requirements.txt" --quiet
        print_success "Edge dependencies installed"
    fi

    # Install additional dev dependencies
    pip install --quiet \
        pytest \
        pytest-asyncio \
        httpx \
        aiohttp

    print_success "Python environment ready"
}

# ============================================
# Setup Frontend
# ============================================

setup_frontend() {
    print_step "Setting up frontend..."

    if [ -d "$PROJECT_ROOT/web" ]; then
        cd "$PROJECT_ROOT/web"

        # Install dependencies
        npm install --silent 2>/dev/null || npm install

        # Create .env if not exists
        if [ ! -f "$PROJECT_ROOT/web/.env" ]; then
            echo "VITE_API_URL=http://localhost:$API_PORT" > "$PROJECT_ROOT/web/.env"
            print_success "Created frontend .env"
        fi

        print_success "Frontend dependencies installed"
    else
        print_warning "Frontend directory not found"
    fi

    cd "$PROJECT_ROOT"
}

# ============================================
# Create Test Configuration
# ============================================

create_test_config() {
    print_step "Creating test configuration..."

    mkdir -p "$PROJECT_ROOT/test"

    # Test environment file
    cat > "$PROJECT_ROOT/test/.env.test" << EOF
# Test Configuration
# Generated: $(date)

# Server
DEBUG=true
LOG_LEVEL=DEBUG

# Authentication (test tokens)
AUTH_TOKENS=test_truck_001,test_truck_002,test_truck_003,test_truck_004,test_truck_005
ADMIN_TOKENS=test_admin_token

# CORS (allow all for testing)
CORS_ORIGINS=*

# Database (SQLite for testing)
TIMING_DB_PATH=$PROJECT_ROOT/test/timing.db

# Rate Limiting (relaxed for testing)
RATE_LIMIT_PUBLIC=1000
RATE_LIMIT_TRUCKS=5000
EOF

    # Simulator config
    cat > "$PROJECT_ROOT/test/simulator_config.json" << EOF
{
    "api_url": "http://localhost:${API_PORT}",
    "num_vehicles": ${NUM_VEHICLES},
    "event_name": "${EVENT_NAME}",
    "auth_tokens": ["test_truck_001", "test_truck_002", "test_truck_003", "test_truck_004", "test_truck_005"],
    "update_interval_ms": 200,
    "course": {
        "type": "circuit",
        "center_lat": 33.0,
        "center_lon": -116.0,
        "radius_km": 5
    }
}
EOF

    print_success "Test configuration created"
}

# ============================================
# Create Test Runner Scripts
# ============================================

create_test_scripts() {
    print_step "Creating test runner scripts..."

    mkdir -p "$PROJECT_ROOT/test"

    # Test 1: Run with Docker
    cat > "$PROJECT_ROOT/test/run_docker_stack.sh" << 'EOF'
#!/bin/bash
#
# Run full stack with Docker
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Running Argus Full Stack with Docker                      ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo

cd "$PROJECT_ROOT/deploy"

# Start all services
docker compose up -d

echo
echo "Services starting..."
echo "  API:      http://localhost:8000"
echo "  Frontend: http://localhost:5173"
echo "  Postgres: localhost:5432"
echo "  Redis:    localhost:6379"
echo
echo "To view logs: docker compose logs -f"
echo "To stop:      docker compose down"
EOF
    chmod +x "$PROJECT_ROOT/test/run_docker_stack.sh"

    # Test 2: Run simulator only
    cat > "$PROJECT_ROOT/test/run_simulator.sh" << EOF
#!/bin/bash
#
# Run simulator against local or remote API
#

set -e

SCRIPT_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="\$(cd "\$SCRIPT_DIR/.." && pwd)"

source "\$PROJECT_ROOT/.venv/bin/activate"

API_URL="\${1:-http://localhost:${API_PORT}}"
NUM_VEHICLES="\${2:-${NUM_VEHICLES}}"

echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Running Argus Simulator                                   ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo
echo "  API URL:    \$API_URL"
echo "  Vehicles:   \$NUM_VEHICLES"
echo

cd "\$PROJECT_ROOT/edge"
python simulator.py --api-url "\$API_URL" --vehicles "\$NUM_VEHICLES"
EOF
    chmod +x "$PROJECT_ROOT/test/run_simulator.sh"

    # Test 3: Load test
    cat > "$PROJECT_ROOT/test/run_load_test.sh" << EOF
#!/bin/bash
#
# Run load test with 50 concurrent vehicles
#

set -e

SCRIPT_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="\$(cd "\$SCRIPT_DIR/.." && pwd)"

source "\$PROJECT_ROOT/.venv/bin/activate"

API_URL="\${1:-http://localhost:${API_PORT}}"

echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Running Argus Load Test (50 Vehicles)                     ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo
echo "  API URL:    \$API_URL"
echo "  Vehicles:   50"
echo "  Mode:       Load Test"
echo

cd "\$PROJECT_ROOT/edge"
python simulator.py --api-url "\$API_URL" --vehicles 50 --load-test
EOF
    chmod +x "$PROJECT_ROOT/test/run_load_test.sh"

    # Test 4: Run local API without Docker
    cat > "$PROJECT_ROOT/test/run_local_api.sh" << EOF
#!/bin/bash
#
# Run API locally without Docker
#

set -e

SCRIPT_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="\$(cd "\$SCRIPT_DIR/.." && pwd)"

source "\$PROJECT_ROOT/.venv/bin/activate"

echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Running Argus API (Local)                                 ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo

# Load test environment
export \$(cat "\$PROJECT_ROOT/test/.env.test" | grep -v '^#' | xargs)

cd "\$PROJECT_ROOT/cloud"
uvicorn app.main:app --host 0.0.0.0 --port ${API_PORT} --reload
EOF
    chmod +x "$PROJECT_ROOT/test/run_local_api.sh"

    # Test 5: Run frontend dev server
    cat > "$PROJECT_ROOT/test/run_frontend.sh" << EOF
#!/bin/bash
#
# Run frontend development server
#

set -e

SCRIPT_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="\$(cd "\$SCRIPT_DIR/.." && pwd)"

echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Running Argus Frontend (Dev Server)                       ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo

cd "\$PROJECT_ROOT/web"
npm run dev -- --port ${WEB_PORT}
EOF
    chmod +x "$PROJECT_ROOT/test/run_frontend.sh"

    # All-in-one development script
    cat > "$PROJECT_ROOT/test/run_dev.sh" << EOF
#!/bin/bash
#
# Run complete development environment
# Starts API, frontend, and simulator
#

set -e

SCRIPT_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="\$(cd "\$SCRIPT_DIR/.." && pwd)"

echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Starting Argus Development Environment                    ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo

# Function to cleanup on exit
cleanup() {
    echo
    echo "Stopping services..."
    kill \$API_PID 2>/dev/null || true
    kill \$WEB_PID 2>/dev/null || true
    kill \$SIM_PID 2>/dev/null || true
    echo "Done."
}
trap cleanup EXIT

source "\$PROJECT_ROOT/.venv/bin/activate"

# Load test environment
export \$(cat "\$PROJECT_ROOT/test/.env.test" | grep -v '^#' | xargs)

# Start API
echo "Starting API on port ${API_PORT}..."
cd "\$PROJECT_ROOT/cloud"
uvicorn app.main:app --host 0.0.0.0 --port ${API_PORT} &
API_PID=\$!
sleep 3

# Start frontend
echo "Starting frontend on port ${WEB_PORT}..."
cd "\$PROJECT_ROOT/web"
npm run dev -- --port ${WEB_PORT} &
WEB_PID=\$!
sleep 3

# Start simulator
echo "Starting simulator with ${NUM_VEHICLES} vehicles..."
cd "\$PROJECT_ROOT/edge"
python simulator.py --api-url http://localhost:${API_PORT} --vehicles ${NUM_VEHICLES} &
SIM_PID=\$!

echo
echo "════════════════════════════════════════════════════════════"
echo "  Development environment running!"
echo
echo "  API:        http://localhost:${API_PORT}"
echo "  Frontend:   http://localhost:${WEB_PORT}"
echo "  Simulator:  ${NUM_VEHICLES} vehicles"
echo
echo "  Press Ctrl+C to stop all services"
echo "════════════════════════════════════════════════════════════"
echo

wait
EOF
    chmod +x "$PROJECT_ROOT/test/run_dev.sh"

    print_success "Test runner scripts created"
}

# ============================================
# Print Summary
# ============================================

print_summary() {
    echo
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║           DEVELOPMENT SETUP COMPLETE!                         ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo
    echo -e "  ${BOLD}Project Structure:${NC}"
    echo "  ─────────────────────────────────────────────────"
    echo "  $PROJECT_ROOT/"
    echo "  ├── .venv/          # Python virtual environment"
    echo "  ├── cloud/          # FastAPI backend"
    echo "  ├── edge/           # Edge services & simulator"
    echo "  ├── web/            # React frontend"
    echo "  └── test/           # Test scripts"
    echo "      ├── run_dev.sh          # All-in-one dev"
    echo "      ├── run_local_api.sh    # API only"
    echo "      ├── run_frontend.sh     # Frontend only"
    echo "      ├── run_simulator.sh    # Simulator only"
    echo "      ├── run_load_test.sh    # 50-vehicle load test"
    echo "      └── run_docker_stack.sh # Full Docker stack"
    echo "  ─────────────────────────────────────────────────"
    echo
    echo -e "  ${BOLD}Quick Start:${NC}"
    echo "  ─────────────────────────────────────────────────"
    echo "  # Option 1: All-in-one (API + Frontend + Simulator)"
    echo "  ./test/run_dev.sh"
    echo
    echo "  # Option 2: Docker full stack"
    echo "  ./test/run_docker_stack.sh"
    echo
    echo "  # Option 3: Manual (3 terminals)"
    echo "  Terminal 1: ./test/run_local_api.sh"
    echo "  Terminal 2: ./test/run_frontend.sh"
    echo "  Terminal 3: ./test/run_simulator.sh"
    echo "  ─────────────────────────────────────────────────"
    echo
    echo -e "  ${BOLD}URLs:${NC}"
    echo "  ─────────────────────────────────────────────────"
    echo "  API:      http://localhost:${API_PORT}"
    echo "  Frontend: http://localhost:${WEB_PORT}"
    echo "  Health:   http://localhost:${API_PORT}/health"
    echo "  Docs:     http://localhost:${API_PORT}/docs"
    echo "  ─────────────────────────────────────────────────"
    echo
    echo -e "  ${BOLD}Test Tokens:${NC}"
    echo "  ─────────────────────────────────────────────────"
    echo "  Truck tokens: test_truck_001 through test_truck_005"
    echo "  Admin token:  test_admin_token"
    echo "  ─────────────────────────────────────────────────"
    echo
}

# ============================================
# Main
# ============================================

main() {
    print_banner

    detect_system

    echo
    if ! prompt_yes_no "Set up development environment?" "y"; then
        echo "Setup cancelled."
        exit 0
    fi

    check_prerequisites
    collect_configuration
    setup_python_env
    setup_frontend
    create_test_config
    create_test_scripts
    print_summary
}

main "$@"
