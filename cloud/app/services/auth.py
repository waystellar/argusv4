"""
Centralized authentication and authorization module.

PR-1: Security Gate & Setup-Mode Hardening

Provides:
- require_role(): FastAPI dependency for route-level RBAC
- get_viewer_access(): Compute viewer access level from auth + subscription
- Role hierarchy: public < premium < team < organizer < admin

SECURITY: This module is the single source of truth for access control.
All protected routes MUST use these dependencies.
"""
import hashlib
from enum import IntEnum
from typing import Optional

from fastapi import Depends, Header, HTTPException, Request
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.database import get_session
from app.models import Vehicle, EventVehicle, Event

settings = get_settings()


class Role(IntEnum):
    """
    Role hierarchy with numeric values for comparison.
    Higher value = more permissions.
    """
    PUBLIC = 0      # Anonymous fans
    PREMIUM = 1     # Paid subscribers
    TEAM = 2        # Team members (authenticated via team token)
    ORGANIZER = 3   # Race organizers (can manage their events)
    ADMIN = 4       # System administrators (full access)


# Map string access levels to Role enum
ACCESS_LEVEL_TO_ROLE = {
    "public": Role.PUBLIC,
    "premium": Role.PREMIUM,
    "team": Role.TEAM,
    "organizer": Role.ORGANIZER,
    "admin": Role.ADMIN,
}


class AuthInfo:
    """
    Authentication context for a request.
    Populated by auth dependencies.
    """
    def __init__(
        self,
        role: Role = Role.PUBLIC,
        user_id: Optional[str] = None,
        vehicle_id: Optional[str] = None,
        event_id: Optional[str] = None,
        team_name: Optional[str] = None,
    ):
        self.role = role
        self.user_id = user_id
        self.vehicle_id = vehicle_id
        self.event_id = event_id
        self.team_name = team_name

    @property
    def access_level(self) -> str:
        """Return string access level for backwards compatibility."""
        for level, role in ACCESS_LEVEL_TO_ROLE.items():
            if role == self.role:
                return level
        return "public"

    def has_role(self, required: Role) -> bool:
        """Check if this auth has at least the required role."""
        return self.role >= required


def _verify_admin_jwt(token: str) -> bool:
    """
    Verify JWT token from admin password login.
    Returns True if valid admin session token.
    """
    import jwt
    try:
        payload = jwt.decode(token, settings.secret_key, algorithms=["HS256"])
        return payload.get("type") == "admin_session"
    except jwt.ExpiredSignatureError:
        return False
    except jwt.InvalidTokenError:
        return False


async def _verify_admin_token(token: str) -> bool:
    """
    Verify admin token against stored tokens list or hash.
    Supports both:
    1. Direct token match against ADMIN_TOKENS list
    2. Hash comparison against admin_token_hash (legacy)
    Returns True if valid.
    """
    # Check against ADMIN_TOKENS list (comma-separated)
    if settings.admin_tokens:
        valid_tokens = [t.strip() for t in settings.admin_tokens.split(",") if t.strip()]
        if token in valid_tokens:
            return True

    # Fallback: Check against hash (legacy method)
    if settings.admin_token_hash:
        provided_hash = hashlib.sha256(token.encode()).hexdigest()
        if provided_hash == settings.admin_token_hash:
            return True

    return False


async def _verify_team_token(
    token: str,
    event_id: Optional[str],
    db: AsyncSession,
) -> Optional[AuthInfo]:
    """
    Verify team/truck token and return AuthInfo if valid.
    Team tokens are truck_token values from Vehicle records.
    """
    result = await db.execute(
        select(Vehicle).where(Vehicle.truck_token == token)
    )
    vehicle = result.scalar_one_or_none()
    if not vehicle:
        return None

    # If event_id provided, verify vehicle is registered for that event
    if event_id:
        result = await db.execute(
            select(EventVehicle).where(
                EventVehicle.vehicle_id == vehicle.vehicle_id,
                EventVehicle.event_id == event_id,
            )
        )
        if not result.scalar_one_or_none():
            return None

    return AuthInfo(
        role=Role.TEAM,
        vehicle_id=vehicle.vehicle_id,
        team_name=vehicle.team_name,
    )


async def get_auth_info(
    request: Request,
    db: AsyncSession = Depends(get_session),
    x_admin_token: Optional[str] = Header(None, alias="X-Admin-Token"),
    x_team_token: Optional[str] = Header(None, alias="X-Team-Token"),
    x_truck_token: Optional[str] = Header(None, alias="X-Truck-Token"),
    authorization: Optional[str] = Header(None),
) -> AuthInfo:
    """
    Extract and validate authentication from request.
    Checks multiple auth methods in priority order:
    1. X-Admin-Token header (admin access via raw token)
    2. Admin JWT session (from cookie or Bearer - web console login)
    3. X-Team-Token or X-Truck-Token header (team access)
    4. Authorization: Bearer token (premium subscriber)
    5. Anonymous (public access)

    This is a FastAPI dependency that populates AuthInfo.
    """
    # 1. Check X-Admin-Token header (raw token)
    if x_admin_token:
        if await _verify_admin_token(x_admin_token):
            return AuthInfo(role=Role.ADMIN, user_id="admin")

    # 2. Check for admin JWT session (from password login)
    # Check cookie first
    admin_jwt = request.cookies.get("argus_admin_token")
    # Also check Bearer token for JWT (localStorage-based auth)
    if not admin_jwt and authorization and authorization.startswith("Bearer "):
        admin_jwt = authorization[7:]

    if admin_jwt and _verify_admin_jwt(admin_jwt):
        return AuthInfo(role=Role.ADMIN, user_id="admin")

    # 3. Check team/truck token
    team_token = x_team_token or x_truck_token
    if team_token:
        # Extract event_id from path if available
        event_id = request.path_params.get("event_id")
        auth = await _verify_team_token(team_token, event_id, db)
        if auth:
            return auth

    # 4. Check Bearer token for premium subscribers (non-admin JWT)
    if authorization and authorization.startswith("Bearer "):
        # TODO: Implement subscription verification
        # For now, Bearer tokens grant premium access if valid JWT
        pass

    # 5. Default to public access
    return AuthInfo(role=Role.PUBLIC)


def require_role(minimum_role: Role):
    """
    FastAPI dependency factory that requires minimum role.

    Usage:
        @router.get("/admin/events")
        async def list_events(auth: AuthInfo = Depends(require_role(Role.ADMIN))):
            ...

    Raises 401 if no auth, 403 if insufficient role.
    """
    async def dependency(
        auth: AuthInfo = Depends(get_auth_info),
    ) -> AuthInfo:
        if auth.role == Role.PUBLIC and minimum_role > Role.PUBLIC:
            raise HTTPException(
                status_code=401,
                detail="Authentication required",
            )
        if not auth.has_role(minimum_role):
            raise HTTPException(
                status_code=403,
                detail=f"Insufficient permissions. Required: {minimum_role.name.lower()}",
            )
        return auth

    return dependency


async def get_viewer_access(
    event_id: str,
    request: Request,
    db: AsyncSession,
) -> str:
    """
    Compute viewer access level for SSE streaming.

    SECURITY: This replaces client-controlled access parameter.
    Access level is determined by:
    1. Admin token → team access (can see everything except hidden)
    2. Team token for this event → team access
    3. Premium subscription (Bearer token) → premium access
    4. Anonymous → public access

    Returns: "public", "premium", or "team"
    """
    # Get auth info
    auth = await get_auth_info(
        request=request,
        db=db,
        x_admin_token=request.headers.get("X-Admin-Token"),
        x_team_token=request.headers.get("X-Team-Token"),
        x_truck_token=request.headers.get("X-Truck-Token"),
        authorization=request.headers.get("Authorization"),
    )

    # Admin gets team-level access (sees everything except hidden)
    if auth.role >= Role.ADMIN:
        return "team"

    # Team member gets team access for their team
    if auth.role >= Role.TEAM:
        # Verify team is registered for this event
        if auth.vehicle_id:
            result = await db.execute(
                select(EventVehicle).where(
                    EventVehicle.vehicle_id == auth.vehicle_id,
                    EventVehicle.event_id == event_id,
                )
            )
            if result.scalar_one_or_none():
                return "team"
        # SECURITY FIX: Team token not valid for this event, fall back to PUBLIC
        # (not premium - that would be privilege escalation)
        return "public"

    # Premium subscriber
    if auth.role >= Role.PREMIUM:
        return "premium"

    # Default: public access
    return "public"


# Convenience dependencies for common role requirements
require_admin = require_role(Role.ADMIN)
require_organizer = require_role(Role.ORGANIZER)
require_team = require_role(Role.TEAM)
require_premium = require_role(Role.PREMIUM)
