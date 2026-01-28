"""
OAuth2 Authentication routes - Google, Facebook, etc.

Provides OAuth2 login for team dashboards as an alternative to truck token auth.
This allows team members to log in with their existing social accounts.

Missing feature implementation from Product Vision - Team Dashboard Auth.

Dependencies:
    pip install authlib itsdangerous

Environment variables:
    GOOGLE_CLIENT_ID: Google OAuth2 client ID
    GOOGLE_CLIENT_SECRET: Google OAuth2 client secret
    OAUTH_REDIRECT_URI: Base redirect URI for OAuth callbacks
"""
import os
from datetime import datetime, timedelta
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import RedirectResponse
from pydantic import BaseModel, EmailStr
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
import jwt

from app.database import get_session
from app.models import Vehicle
from app.config import get_settings

settings = get_settings()
router = APIRouter(prefix="/api/v1/auth", tags=["auth"])

# OAuth configuration
GOOGLE_CLIENT_ID = os.environ.get("GOOGLE_CLIENT_ID", "")
GOOGLE_CLIENT_SECRET = os.environ.get("GOOGLE_CLIENT_SECRET", "")
OAUTH_REDIRECT_URI = os.environ.get("OAUTH_REDIRECT_URI", "http://localhost:8000/api/v1/auth/callback/google")

# Try to import authlib
try:
    from authlib.integrations.starlette_client import OAuth
    from starlette.config import Config

    config = Config(environ={
        "GOOGLE_CLIENT_ID": GOOGLE_CLIENT_ID,
        "GOOGLE_CLIENT_SECRET": GOOGLE_CLIENT_SECRET,
    })

    oauth = OAuth(config)

    # Register Google OAuth provider
    if GOOGLE_CLIENT_ID:
        oauth.register(
            name="google",
            server_metadata_url="https://accounts.google.com/.well-known/openid-configuration",
            client_kwargs={"scope": "openid email profile"},
        )
        OAUTH_AVAILABLE = True
    else:
        OAUTH_AVAILABLE = False

except ImportError:
    OAUTH_AVAILABLE = False
    oauth = None


# ============ Team Account Model ============
# In production, add this to models.py

from sqlalchemy import Column, String, DateTime, ForeignKey
from app.models import Base


class TeamAccount(Base):
    """OAuth-linked team account."""
    __tablename__ = "team_accounts"

    account_id = Column(String, primary_key=True)
    email = Column(String, nullable=False, unique=True, index=True)
    name = Column(String)
    oauth_provider = Column(String, nullable=False)  # google, facebook, etc.
    oauth_id = Column(String, nullable=False)  # Provider's user ID
    vehicle_id = Column(String, ForeignKey("vehicles.vehicle_id"), nullable=True)
    created_at = Column(DateTime(timezone=True), default=datetime.utcnow)
    last_login = Column(DateTime(timezone=True))


# ============ Schemas ============

class OAuthLoginResponse(BaseModel):
    """OAuth login redirect URL."""
    auth_url: str


class TokenResponse(BaseModel):
    """JWT token response after OAuth login."""
    access_token: str
    token_type: str = "bearer"
    expires_in: int
    email: str
    name: Optional[str]
    vehicle_id: Optional[str]
    vehicle_number: Optional[str]


class LinkVehicleRequest(BaseModel):
    """Request to link OAuth account to a vehicle."""
    vehicle_number: str
    truck_token: str


# ============ Helper Functions ============

def create_oauth_token(email: str, name: str, vehicle_id: Optional[str] = None) -> str:
    """Create JWT token for OAuth-authenticated user."""
    payload = {
        "sub": email,
        "name": name,
        "vehicle_id": vehicle_id,
        "type": "oauth_team",
        "exp": datetime.utcnow() + timedelta(hours=24),
        "iat": datetime.utcnow(),
    }
    return jwt.encode(payload, settings.secret_key, algorithm="HS256")


# ============ Endpoints ============

@router.get("/providers")
async def list_auth_providers():
    """
    List available OAuth providers.
    Frontend uses this to show login buttons.
    """
    providers = []

    if GOOGLE_CLIENT_ID:
        providers.append({
            "name": "google",
            "display_name": "Google",
            "login_url": "/api/v1/auth/login/google",
            "available": OAUTH_AVAILABLE,
        })

    # Add more providers as needed (Facebook, Apple, etc.)

    return {
        "providers": providers,
        "oauth_available": OAUTH_AVAILABLE,
    }


@router.get("/login/{provider}")
async def oauth_login(
    provider: str,
    request: Request,
):
    """
    Initiate OAuth login flow.
    Redirects to provider's login page.
    """
    if not OAUTH_AVAILABLE:
        raise HTTPException(
            status_code=503,
            detail="OAuth not configured. Set GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET."
        )

    if provider not in ["google"]:
        raise HTTPException(status_code=400, detail=f"Unknown provider: {provider}")

    redirect_uri = f"{OAUTH_REDIRECT_URI.rstrip('/')}/callback/{provider}"

    if provider == "google":
        return await oauth.google.authorize_redirect(request, redirect_uri)

    raise HTTPException(status_code=400, detail="Provider not implemented")


@router.get("/callback/{provider}")
async def oauth_callback(
    provider: str,
    request: Request,
    db: AsyncSession = Depends(get_session),
):
    """
    Handle OAuth callback from provider.
    Creates or updates team account and returns JWT.
    """
    if not OAUTH_AVAILABLE:
        raise HTTPException(status_code=503, detail="OAuth not configured")

    try:
        if provider == "google":
            token = await oauth.google.authorize_access_token(request)
            user_info = token.get("userinfo")
            if not user_info:
                user_info = await oauth.google.userinfo(token=token)
        else:
            raise HTTPException(status_code=400, detail="Unknown provider")

        email = user_info.get("email")
        name = user_info.get("name", email.split("@")[0])
        oauth_id = user_info.get("sub")

        if not email:
            raise HTTPException(status_code=400, detail="Email not provided by OAuth")

        # Find or create team account
        result = await db.execute(
            select(TeamAccount).where(TeamAccount.email == email)
        )
        account = result.scalar_one_or_none()

        from app.models import generate_id

        if not account:
            account = TeamAccount(
                account_id=generate_id("acc"),
                email=email,
                name=name,
                oauth_provider=provider,
                oauth_id=oauth_id,
            )
            db.add(account)

        account.last_login = datetime.utcnow()
        await db.commit()

        # Get linked vehicle info if any
        vehicle_number = None
        if account.vehicle_id:
            result = await db.execute(
                select(Vehicle).where(Vehicle.vehicle_id == account.vehicle_id)
            )
            vehicle = result.scalar_one_or_none()
            if vehicle:
                vehicle_number = vehicle.vehicle_number

        # Create JWT token
        access_token = create_oauth_token(email, name, account.vehicle_id)

        # Redirect to frontend with token
        # In production, use a more secure method (e.g., HTTP-only cookie)
        frontend_url = os.environ.get("FRONTEND_URL", "http://localhost:5173")
        return RedirectResponse(
            url=f"{frontend_url}/auth/callback?token={access_token}&email={email}"
        )

    except Exception as e:
        raise HTTPException(status_code=400, detail=f"OAuth error: {str(e)}")


@router.post("/link-vehicle", response_model=TokenResponse)
async def link_vehicle_to_account(
    data: LinkVehicleRequest,
    request: Request,
    db: AsyncSession = Depends(get_session),
):
    """
    Link an OAuth account to a vehicle using the truck token.
    This allows OAuth-authenticated users to manage their team's settings.
    """
    # Get authorization header
    auth_header = request.headers.get("Authorization", "")
    if not auth_header.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing authorization")

    token = auth_header[7:]

    try:
        payload = jwt.decode(token, settings.secret_key, algorithms=["HS256"])
        if payload.get("type") != "oauth_team":
            raise HTTPException(status_code=401, detail="Invalid token type")
        email = payload["sub"]
    except jwt.InvalidTokenError:
        raise HTTPException(status_code=401, detail="Invalid token")

    # Find vehicle by number and token
    result = await db.execute(
        select(Vehicle).where(
            Vehicle.vehicle_number == data.vehicle_number,
            Vehicle.truck_token == data.truck_token,
        )
    )
    vehicle = result.scalar_one_or_none()

    if not vehicle:
        raise HTTPException(status_code=401, detail="Invalid vehicle credentials")

    # Find team account
    result = await db.execute(
        select(TeamAccount).where(TeamAccount.email == email)
    )
    account = result.scalar_one_or_none()

    if not account:
        raise HTTPException(status_code=404, detail="Account not found")

    # Link vehicle to account
    account.vehicle_id = vehicle.vehicle_id
    await db.commit()

    # Generate new token with vehicle_id
    access_token = create_oauth_token(email, account.name, vehicle.vehicle_id)

    return TokenResponse(
        access_token=access_token,
        expires_in=86400,
        email=email,
        name=account.name,
        vehicle_id=vehicle.vehicle_id,
        vehicle_number=vehicle.vehicle_number,
    )


@router.get("/me")
async def get_current_user(
    request: Request,
    db: AsyncSession = Depends(get_session),
):
    """
    Get current user info from OAuth token.
    """
    auth_header = request.headers.get("Authorization", "")
    if not auth_header.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing authorization")

    token = auth_header[7:]

    try:
        payload = jwt.decode(token, settings.secret_key, algorithms=["HS256"])
    except jwt.InvalidTokenError:
        raise HTTPException(status_code=401, detail="Invalid token")

    email = payload["sub"]

    result = await db.execute(
        select(TeamAccount).where(TeamAccount.email == email)
    )
    account = result.scalar_one_or_none()

    if not account:
        raise HTTPException(status_code=404, detail="Account not found")

    # Get vehicle info if linked
    vehicle_info = None
    if account.vehicle_id:
        result = await db.execute(
            select(Vehicle).where(Vehicle.vehicle_id == account.vehicle_id)
        )
        vehicle = result.scalar_one_or_none()
        if vehicle:
            vehicle_info = {
                "vehicle_id": vehicle.vehicle_id,
                "vehicle_number": vehicle.vehicle_number,
                "team_name": vehicle.team_name,
            }

    return {
        "email": account.email,
        "name": account.name,
        "oauth_provider": account.oauth_provider,
        "vehicle": vehicle_info,
        "created_at": account.created_at.isoformat(),
        "last_login": account.last_login.isoformat() if account.last_login else None,
    }
