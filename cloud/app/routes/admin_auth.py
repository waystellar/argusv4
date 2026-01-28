"""
Admin Authentication Routes for Argus Timing System.

Provides secure login/logout for the web admin console.
Uses bcrypt for password hashing and JWT for session tokens.
"""
from datetime import datetime, timedelta
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Request, Response
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field
import jwt
import bcrypt

from app.config import get_settings

settings = get_settings()
router = APIRouter(prefix="/api/v1/admin/auth", tags=["admin-auth"])

# JWT settings
JWT_ALGORITHM = "HS256"
JWT_EXPIRY_HOURS = 24


# ============================================
# Schemas
# ============================================

class AdminLoginRequest(BaseModel):
    """Admin login credentials."""
    password: str = Field(..., min_length=1)


class AdminLoginResponse(BaseModel):
    """Successful login response."""
    access_token: str
    token_type: str = "bearer"
    expires_in: int  # seconds
    message: str = "Login successful"


class AdminSession(BaseModel):
    """Current admin session info."""
    authenticated: bool
    expires_at: Optional[str] = None


# ============================================
# Helper Functions
# ============================================

def hash_password(password: str) -> str:
    """Hash a password using bcrypt."""
    salt = bcrypt.gensalt(rounds=12)
    return bcrypt.hashpw(password.encode('utf-8'), salt).decode('utf-8')


def verify_password(password: str, hashed: str) -> bool:
    """Verify a password against its hash."""
    try:
        return bcrypt.checkpw(password.encode('utf-8'), hashed.encode('utf-8'))
    except Exception:
        return False


def create_admin_token() -> str:
    """Create a JWT token for admin session."""
    expiry = datetime.utcnow() + timedelta(hours=JWT_EXPIRY_HOURS)
    payload = {
        "sub": "admin",
        "type": "admin_session",
        "exp": expiry,
        "iat": datetime.utcnow(),
    }
    return jwt.encode(payload, settings.secret_key, algorithm=JWT_ALGORITHM)


def verify_admin_token(token: str) -> bool:
    """Verify an admin JWT token is valid."""
    try:
        payload = jwt.decode(token, settings.secret_key, algorithms=[JWT_ALGORITHM])
        return payload.get("type") == "admin_session"
    except jwt.ExpiredSignatureError:
        return False
    except jwt.InvalidTokenError:
        return False


def get_admin_token_from_request(request: Request) -> Optional[str]:
    """Extract admin token from request (header or cookie)."""
    # Check Authorization header first
    auth_header = request.headers.get("Authorization", "")
    if auth_header.startswith("Bearer "):
        return auth_header[7:]

    # Check cookie
    return request.cookies.get("argus_admin_token")


# ============================================
# Dependency: Require Admin Auth
# ============================================

async def require_admin_auth(request: Request) -> bool:
    """
    Dependency that requires valid admin authentication.
    Use this to protect admin-only routes.
    """
    # Check if admin auth is configured
    if not settings.admin_password_hash:
        # No password set - allow access (first-time setup or dev mode)
        return True

    token = get_admin_token_from_request(request)
    if not token:
        raise HTTPException(
            status_code=401,
            detail="Admin authentication required",
            headers={"WWW-Authenticate": "Bearer"},
        )

    if not verify_admin_token(token):
        raise HTTPException(
            status_code=401,
            detail="Invalid or expired admin session",
            headers={"WWW-Authenticate": "Bearer"},
        )

    return True


# ============================================
# Endpoints
# ============================================

@router.get("/status")
async def auth_status(request: Request):
    """
    Check if admin authentication is required and current session status.
    Frontend uses this to determine if login is needed.
    """
    # Check if password is configured
    auth_required = bool(settings.admin_password_hash)

    if not auth_required:
        return {
            "auth_required": False,
            "authenticated": True,
            "message": "No admin password configured - access granted"
        }

    # Check if current request has valid token
    token = get_admin_token_from_request(request)
    authenticated = bool(token and verify_admin_token(token))

    return {
        "auth_required": True,
        "authenticated": authenticated,
        "message": "Login required" if not authenticated else "Authenticated"
    }


@router.post("/login", response_model=AdminLoginResponse)
async def admin_login(credentials: AdminLoginRequest, response: Response):
    """
    Authenticate admin user and create session.
    Returns JWT token on success.
    """
    # Check if password is configured
    if not settings.admin_password_hash:
        raise HTTPException(
            status_code=400,
            detail="Admin password not configured. Run setup wizard."
        )

    # Verify password
    if not verify_password(credentials.password, settings.admin_password_hash):
        raise HTTPException(
            status_code=401,
            detail="Invalid password"
        )

    # Create JWT token
    token = create_admin_token()
    expires_in = JWT_EXPIRY_HOURS * 3600

    # Set HTTP-only cookie for security
    response.set_cookie(
        key="argus_admin_token",
        value=token,
        httponly=True,
        secure=False,  # Set to True in production with HTTPS
        samesite="lax",
        max_age=expires_in,
    )

    return AdminLoginResponse(
        access_token=token,
        expires_in=expires_in,
    )


@router.post("/logout")
async def admin_logout(response: Response):
    """
    Log out admin user and clear session.
    """
    response.delete_cookie(
        key="argus_admin_token",
        httponly=True,
        samesite="lax",
    )
    return {"message": "Logged out successfully"}


@router.get("/verify")
async def verify_session(request: Request):
    """
    Verify if current session is valid.
    Returns 401 if not authenticated.
    """
    # Check if password is configured
    if not settings.admin_password_hash:
        return {"valid": True, "message": "No password configured"}

    token = get_admin_token_from_request(request)
    if not token:
        raise HTTPException(status_code=401, detail="No session token")

    if not verify_admin_token(token):
        raise HTTPException(status_code=401, detail="Invalid or expired session")

    return {"valid": True, "message": "Session valid"}


# ============================================
# Utility: Generate Password Hash (for setup)
# ============================================

@router.post("/hash-password")
async def generate_password_hash(password: str):
    """
    Generate a bcrypt hash for a password.
    Used by setup wizard to create ADMIN_PASSWORD_HASH.
    Only works in setup mode.
    """
    if settings.setup_completed:
        raise HTTPException(
            status_code=403,
            detail="Only available during setup"
        )

    hashed = hash_password(password)
    return {"hash": hashed}
