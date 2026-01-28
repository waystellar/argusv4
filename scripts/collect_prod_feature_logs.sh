#!/usr/bin/env bash
# collect_prod_feature_logs.sh — Collect diagnostic logs for featured camera debugging
#
# Outputs plain text logs from:
#   1. Docker compose API container (last N minutes)
#   2. Docker compose Web container (last N minutes)
#   3. Redis featured-camera state (if redis-cli available)
#   4. Edge logs (if EDGE_HOST configured, via ssh)
#
# No secrets are printed. Admin tokens and passwords are redacted.
#
# Usage:
#   bash scripts/collect_prod_feature_logs.sh [minutes] [event_id] [vehicle_id]
#
# Defaults: 5 minutes, no event/vehicle filter
set -uo pipefail

MINUTES="${1:-5}"
EVENT_ID="${2:-}"
VEHICLE_ID="${3:-}"
EDGE_HOST="${EDGE_HOST:-}"
COMPOSE_DIR="${COMPOSE_DIR:-}"

PREFIX="[log-collect]"

log()  { echo "$PREFIX $*"; }
sep()  { echo ""; echo "══════════════════════════════════════════════════════════════"; echo "$PREFIX $*"; echo "══════════════════════════════════════════════════════════════"; }

# ── Find docker-compose directory ──────────────────────────────────
if [ -z "$COMPOSE_DIR" ]; then
  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
  REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
  if [ -f "$REPO_ROOT/deploy/docker-compose.yml" ]; then
    COMPOSE_DIR="$REPO_ROOT/deploy"
  elif [ -f "$REPO_ROOT/docker-compose.yml" ]; then
    COMPOSE_DIR="$REPO_ROOT"
  fi
fi

# ── Redact secrets from output ─────────────────────────────────────
redact() {
  sed -E \
    -e 's/(ADMIN_TOKEN[S]?=)[^ ]*/\1[REDACTED]/gi' \
    -e 's/(X-Admin-Token: )[^ ]*/\1[REDACTED]/gi' \
    -e 's/(Authorization: Bearer )[^ ]*/\1[REDACTED]/gi' \
    -e 's/(SECRET_KEY=)[^ ]*/\1[REDACTED]/gi' \
    -e 's/(PASSWORD=)[^ ]*/\1[REDACTED]/gi' \
    -e 's/(password=)[^ ]*/\1[REDACTED]/gi'
}

echo ""
log "Featured Camera Log Collection"
log "Time window: last ${MINUTES} minutes"
[ -n "$EVENT_ID" ] && log "Event filter: $EVENT_ID"
[ -n "$VEHICLE_ID" ] && log "Vehicle filter: $VEHICLE_ID"
log "Timestamp: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"

# ── 1. API container logs ──────────────────────────────────────────
sep "1. API Container Logs (argus-api)"

if command -v docker >/dev/null 2>&1; then
  # Try docker compose first, then docker logs
  API_LOGS=""
  if [ -n "$COMPOSE_DIR" ] && [ -f "$COMPOSE_DIR/docker-compose.yml" ]; then
    API_LOGS=$(cd "$COMPOSE_DIR" && docker compose logs api --since "${MINUTES}m" --no-color 2>&1) || true
  fi

  # Fallback: direct container name
  if [ -z "$API_LOGS" ]; then
    API_LOGS=$(docker logs argus-api --since "${MINUTES}m" --no-color 2>&1) || true
  fi

  if [ -n "$API_LOGS" ]; then
    # Filter for featured-camera related lines if event/vehicle provided
    if [ -n "$EVENT_ID" ] || [ -n "$VEHICLE_ID" ]; then
      FILTER_PATTERN="${EVENT_ID:-.*}"
      [ -n "$VEHICLE_ID" ] && FILTER_PATTERN="$FILTER_PATTERN\|$VEHICLE_ID"
      FILTER_PATTERN="$FILTER_PATTERN\|featured\|camera\|command\|edge"
      echo "$API_LOGS" | grep -i "$FILTER_PATTERN" | redact | tail -100
    else
      echo "$API_LOGS" | grep -i "featured\|camera\|command\|edge\|error\|warn" | redact | tail -100
    fi
    echo ""
    log "Total API log lines (last ${MINUTES}m): $(echo "$API_LOGS" | wc -l | tr -d ' ')"
  else
    log "No API logs found (container may not be running)"
  fi
else
  log "Docker not available — skipping container logs"

  # Try reading log files directly (non-Docker deployment)
  if [ -n "$COMPOSE_DIR" ]; then
    REPO_ROOT="$(cd "$COMPOSE_DIR/.." && pwd 2>/dev/null || echo "")"
  fi
  for logfile in /var/log/argus/api.log /tmp/argus-api.log; do
    if [ -f "$logfile" ]; then
      log "Reading $logfile..."
      tail -200 "$logfile" | grep -i "featured\|camera\|command\|edge\|error" | redact | tail -50
    fi
  done
fi

# ── 2. Web container logs ─────────────────────────────────────────
sep "2. Web Container Logs (argus-web)"

if command -v docker >/dev/null 2>&1; then
  WEB_LOGS=""
  if [ -n "$COMPOSE_DIR" ] && [ -f "$COMPOSE_DIR/docker-compose.yml" ]; then
    WEB_LOGS=$(cd "$COMPOSE_DIR" && docker compose logs web --since "${MINUTES}m" --no-color 2>&1) || true
  fi

  if [ -z "$WEB_LOGS" ]; then
    WEB_LOGS=$(docker logs argus-web --since "${MINUTES}m" --no-color 2>&1) || true
  fi

  if [ -n "$WEB_LOGS" ]; then
    echo "$WEB_LOGS" | grep -i "error\|warn\|fail" | redact | tail -50
    echo ""
    log "Total web log lines (last ${MINUTES}m): $(echo "$WEB_LOGS" | wc -l | tr -d ' ')"
  else
    log "No web logs found (container may not be running)"
  fi
else
  log "Docker not available — skipping web logs"
fi

# ── 3. Redis state debug ──────────────────────────────────────────
sep "3. Redis Featured Camera State"

REDIS_AVAILABLE=false
if command -v redis-cli >/dev/null 2>&1; then
  REDIS_AVAILABLE=true
  REDIS_CMD="redis-cli"
elif command -v docker >/dev/null 2>&1; then
  # Try redis inside docker
  if docker exec argus-redis redis-cli ping >/dev/null 2>&1; then
    REDIS_AVAILABLE=true
    REDIS_CMD="docker exec argus-redis redis-cli"
  fi
fi

if [ "$REDIS_AVAILABLE" = true ]; then
  if [ -n "$EVENT_ID" ] && [ -n "$VEHICLE_ID" ]; then
    KEY="featured_camera:${EVENT_ID}:${VEHICLE_ID}"
    log "Checking key: $KEY"
    STATE=$($REDIS_CMD GET "$KEY" 2>/dev/null || echo "(not found)")
    if [ -n "$STATE" ] && [ "$STATE" != "(nil)" ] && [ "$STATE" != "(not found)" ]; then
      echo "$STATE" | redact
    else
      log "No state found for $KEY"
    fi
  else
    # List all featured_camera keys
    KEYS=$($REDIS_CMD KEYS "featured_camera:*" 2>/dev/null || echo "")
    if [ -n "$KEYS" ]; then
      log "Featured camera keys in Redis:"
      echo "$KEYS" | head -20
      KEY_COUNT=$(echo "$KEYS" | wc -l | tr -d ' ')
      log "Total keys: $KEY_COUNT"
    else
      log "No featured_camera keys found in Redis"
    fi
  fi

  # Also check edge command keys
  EDGE_KEYS=$($REDIS_CMD KEYS "edge_command:*" 2>/dev/null || echo "")
  if [ -n "$EDGE_KEYS" ]; then
    log "Active edge command keys:"
    echo "$EDGE_KEYS" | head -10
  fi
else
  log "Redis not reachable — skipping state debug"
fi

# ── 4. Edge logs (optional, via SSH) ──────────────────────────────
sep "4. Edge Device Logs"

if [ -n "$EDGE_HOST" ]; then
  log "Fetching edge logs from $EDGE_HOST..."
  EDGE_LOG=$(ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$EDGE_HOST" \
    "journalctl -u argus-edge --since '${MINUTES} min ago' --no-pager 2>/dev/null || \
     tail -100 /var/log/argus/edge.log 2>/dev/null || \
     tail -100 /tmp/pit_crew_dashboard.log 2>/dev/null || \
     echo 'No edge logs found'" 2>&1) || true

  if [ -n "$EDGE_LOG" ]; then
    echo "$EDGE_LOG" | grep -i "camera-switch\|edge-cmd\|edge-ack\|stream\|error\|warn" | redact | tail -50
  else
    log "Could not retrieve edge logs"
  fi
else
  log "EDGE_HOST not set — skipping edge logs"
  log "Set EDGE_HOST=user@ip to enable (e.g. EDGE_HOST=pi@192.168.0.10)"
fi

# ── Summary ────────────────────────────────────────────────────────
sep "Log Collection Complete"
log "Collected at: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
log "To expand time window: bash $0 15  (for 15 minutes)"
