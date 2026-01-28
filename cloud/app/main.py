"""
Argus Timing System v4.0 - FastAPI Application

FIXED: Added rate limiting to prevent API abuse (Issue #3 from audit).
"""
from contextlib import asynccontextmanager
import structlog

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, RedirectResponse
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded
from slowapi.middleware import SlowAPIMiddleware

from app.config import get_settings
from app.database import init_db
from app import redis_client
from app.routes import events, vehicles, telemetry, stream, leaderboard, team, production, subscriptions, auth, setup, admin, admin_auth, stream_control

# Configure structured logging
structlog.configure(
    processors=[
        structlog.stdlib.filter_by_level,
        structlog.stdlib.add_logger_name,
        structlog.stdlib.add_log_level,
        structlog.stdlib.PositionalArgumentsFormatter(),
        structlog.processors.TimeStamper(fmt="iso"),
        structlog.processors.StackInfoRenderer(),
        structlog.processors.format_exc_info,
        structlog.processors.UnicodeDecoder(),
        structlog.processors.JSONRenderer(),
    ],
    wrapper_class=structlog.stdlib.BoundLogger,
    context_class=dict,
    logger_factory=structlog.stdlib.LoggerFactory(),
    cache_logger_on_first_use=True,
)

logger = structlog.get_logger()
settings = get_settings()

# FIXED: Initialize rate limiter to prevent API abuse
# Public endpoints: 100 req/min, Truck endpoints: 1000 req/min
limiter = Limiter(
    key_func=get_remote_address,
    default_limits=[f"{settings.rate_limit_public}/minute"],
    storage_uri=settings.redis_url,  # Use Redis for distributed rate limiting
)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifecycle: startup and shutdown."""
    # Startup
    logger.info("Starting Argus Timing System", version=settings.app_version)
    await init_db()
    logger.info("Database initialized")

    yield

    # Shutdown
    logger.info("Shutting down Argus Timing System")
    await redis_client.close_redis()


app = FastAPI(
    title=settings.app_name,
    version=settings.app_version,
    description="Live off-road racing timing and telemetry platform",
    lifespan=lifespan,
)

# FIXED: Register rate limiter with app state
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)
app.add_middleware(SlowAPIMiddleware)

# Session middleware for OAuth (required by authlib)
from starlette.middleware.sessions import SessionMiddleware
app.add_middleware(SessionMiddleware, secret_key=settings.secret_key)

# CORS middleware
# FIXED: Restricted methods to only those needed (was allow_methods=["*"])
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type", "X-Requested-With", "X-Truck-Token", "X-Admin-Token", "Stripe-Signature"],
)


# ============================================
# Setup Enforcement Middleware
# ============================================
# When SETUP_COMPLETED=false, redirect all traffic to /setup
# EXCEPT: /health (Docker healthchecks), /setup/* (wizard itself)
#
# PR-1 SECURITY: Removed /api/* bypass to prevent API access before setup.

@app.middleware("http")
async def setup_enforcement_middleware(request: Request, call_next):
    """
    Redirect all traffic to setup wizard when not configured.

    PR-1 SECURITY: Strict allowlist - only essential paths are permitted.

    Allows through:
    - /health (Docker healthchecks must pass or container restarts)
    - /setup/* (the wizard itself must be accessible)
    - /favicon.ico (browser requests this automatically)

    BLOCKED (redirected to /setup):
    - /api/* (no API access before setup completes)
    - /docs, /openapi.json (API docs expose endpoint structure)
    - All other paths
    """
    # If setup is complete, pass through normally
    if settings.setup_completed:
        return await call_next(request)

    path = request.url.path
    method = request.method

    # PR-1 SECURITY: Strict allowlist - only what's absolutely necessary
    allowed_paths = (
        "/health",      # Docker healthcheck - CRITICAL for orchestration
        "/setup",       # Setup wizard and its API endpoints
        "/favicon.ico", # Browser automatically requests this
    )

    if path.startswith(allowed_paths):
        return await call_next(request)

    # Log blocked access attempts (potential probing)
    logger.warning(
        "[SETUP MODE] Blocked request",
        method=method,
        path=path,
        client=request.client.host if request.client else "unknown",
    )

    # Redirect everything else to setup wizard
    return RedirectResponse(url="/setup", status_code=307)


# Include routers
app.include_router(events.router)
app.include_router(vehicles.router)
app.include_router(telemetry.router)
app.include_router(stream.router)
app.include_router(leaderboard.router)
app.include_router(team.router)
app.include_router(production.router)  # ADDED: Camera switching API
app.include_router(production.events_router)  # ADDED: Edge-compatible production status
app.include_router(subscriptions.router)  # ADDED: Stripe subscription endpoints
app.include_router(auth.router)  # ADDED: OAuth2 team login
app.include_router(setup.router)  # ADDED: Web-based setup wizard
app.include_router(admin.router)  # ADDED: Admin dashboard API
app.include_router(admin_auth.router)  # ADDED: Admin authentication
app.include_router(stream_control.router)  # ADDED: Unified stream control state machine


@app.get("/health")
async def health_check():
    """Health check endpoint for load balancers."""
    return {
        "status": "healthy",
        "version": settings.app_version,
    }


@app.get("/")
async def root():
    """Root endpoint with API info."""
    return {
        "name": settings.app_name,
        "version": settings.app_version,
        "docs": "/docs",
        "health": "/health",
    }


@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    """Global exception handler to prevent secret leakage."""
    logger.exception("Unhandled exception", path=request.url.path)
    return JSONResponse(
        status_code=500,
        content={"detail": "Internal server error"},
    )


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        "app.main:app",
        host="0.0.0.0",
        port=8000,
        reload=settings.debug,
    )
