"""
Application configuration using pydantic-settings.
Loads from environment variables with sensible defaults.

FIXED: Added production CORS domains and secret key validation (Issues #7, #8 from audit).
"""
from functools import lru_cache
from pydantic import model_validator
from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    """Application settings with production-safe defaults."""

    # Setup mode flag - when false, server shows setup wizard
    setup_completed: bool = True

    # Server settings (set by setup wizard)
    server_host: str = "localhost"
    api_port: int = 8000
    deployment_mode: str = "local"  # local, production, aws

    # Application
    app_name: str = "Argus Timing System"
    app_version: str = "4.0.0"
    debug: bool = False
    log_level: str = "INFO"

    # Database
    database_url: str = "postgresql+asyncpg://argus:argus@localhost:5432/argus"
    db_pool_size: int = 5
    db_max_overflow: int = 10

    # Redis
    redis_url: str = "redis://localhost:6379"

    # Security
    secret_key: str = "CHANGE-ME-IN-PRODUCTION-USE-SECRETS-MANAGER"
    admin_token_hash: str = ""  # bcrypt hash of admin token
    admin_password_hash: str = ""  # bcrypt hash of admin password for web console
    auth_tokens: str = ""  # Comma-separated truck authentication tokens
    admin_tokens: str = ""  # Comma-separated admin authentication tokens
    # FIXED: Added production domains (Issue #7 from audit)
    cors_origins: list[str] = [
        "http://localhost:5173",
        "http://localhost:3000",
        "https://administrativeresults.com",
        "https://www.administrativeresults.com",
    ]

    # Rate Limiting (requests per minute)
    rate_limit_public: int = 100
    rate_limit_trucks: int = 1000

    # GPS Processing
    checkpoint_radius_m: float = 50.0
    max_speed_mps: float = 90.0  # ~200 mph, for outlier rejection
    position_batch_max_age_s: int = 60  # Reject batches older than this

    # SSE
    sse_keepalive_s: int = 15
    sse_retry_ms: int = 3000

    # FIXED: Validate secret key in production (Issue #8 from audit)
    @model_validator(mode='after')
    def check_production_security(self):
        """Ensure secret key is changed in production (skipped in setup mode)."""
        # Skip validation in setup mode - temporary security is expected
        if not self.setup_completed:
            return self
        if not self.debug and "CHANGE-ME" in self.secret_key:
            raise ValueError(
                "SECURITY ERROR: Must set SECRET_KEY environment variable for production! "
                "Generate a secure key with: python -c \"import secrets; print(secrets.token_hex(32))\""
            )
        return self

    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"


@lru_cache()
def get_settings() -> Settings:
    """Cached settings instance."""
    return Settings()
