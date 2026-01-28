#!/bin/bash
#
# Argus Timing System v4.0 - Run All Services
#
# Starts the complete stack via docker-compose
# Usage: ./scripts/run_all.sh [--rebuild]
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DEPLOY_DIR="$PROJECT_ROOT/deploy"

echo "============================================"
echo "  Argus Timing System v4.0 - Startup"
echo "============================================"
echo ""
echo "Project: $PROJECT_ROOT"
echo ""

# Check Docker
if ! command -v docker &> /dev/null; then
    echo "ERROR: Docker is not installed"
    exit 1
fi

if ! docker info &> /dev/null; then
    echo "ERROR: Docker daemon is not running"
    exit 1
fi

cd "$DEPLOY_DIR"

# Option: rebuild images
if [ "$1" = "--rebuild" ]; then
    echo "[1/3] Rebuilding Docker images..."
    docker compose build --no-cache
else
    echo "[1/3] Building Docker images (use --rebuild for fresh build)..."
    docker compose build
fi

# Stop any existing containers
echo "[2/3] Stopping any existing containers..."
docker compose down --remove-orphans 2>/dev/null || true

# Start services
echo "[3/3] Starting services..."
docker compose up -d

# Wait for services to be healthy
echo ""
echo "Waiting for services to be healthy..."
MAX_WAIT=60
WAITED=0
while [ $WAITED -lt $MAX_WAIT ]; do
    # Check postgres health
    PG_HEALTHY=$(docker inspect argus-postgres --format='{{.State.Health.Status}}' 2>/dev/null || echo "unknown")
    # Check redis health
    REDIS_HEALTHY=$(docker inspect argus-redis --format='{{.State.Health.Status}}' 2>/dev/null || echo "unknown")
    # Check API running
    API_RUNNING=$(docker inspect argus-api --format='{{.State.Running}}' 2>/dev/null || echo "false")
    # Check web running
    WEB_RUNNING=$(docker inspect argus-web --format='{{.State.Running}}' 2>/dev/null || echo "false")

    if [ "$PG_HEALTHY" = "healthy" ] && [ "$REDIS_HEALTHY" = "healthy" ] && \
       [ "$API_RUNNING" = "true" ] && [ "$WEB_RUNNING" = "true" ]; then
        break
    fi

    sleep 2
    WAITED=$((WAITED + 2))
    echo "  Waiting... ($WAITED/${MAX_WAIT}s)"
done

# Final status check
echo ""
echo "============================================"
echo "  Service Status"
echo "============================================"
docker compose ps

echo ""
echo "============================================"
echo "  Endpoints"
echo "============================================"
echo ""
echo "  API:       http://localhost:8000"
echo "  API Docs:  http://localhost:8000/docs"
echo "  Health:    http://localhost:8000/health"
echo "  Frontend:  http://localhost:5173"
echo ""
echo "============================================"
echo "  Quick Commands"
echo "============================================"
echo ""
echo "  View logs:      cd deploy && docker compose logs -f"
echo "  Stop services:  cd deploy && docker compose down"
echo "  Health check:   ./scripts/health_check.sh"
echo "  Collect logs:   ./scripts/collect_logs.sh"
echo ""
