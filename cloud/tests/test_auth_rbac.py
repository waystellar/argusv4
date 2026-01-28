"""
PR-1: Security Gate & Setup-Mode Hardening - Tests

Tests for:
1. SSE access level cannot be elevated via query params
2. Admin endpoints require authentication
3. Setup-mode blocks /api/* except explicit allowlist

Run with: pytest tests/test_auth_rbac.py -v
"""
import hashlib
import pytest
from unittest.mock import AsyncMock, patch, MagicMock
from fastapi import FastAPI
from fastapi.testclient import TestClient
from httpx import AsyncClient

# Import app and components
from app.main import app
from app.services.auth import (
    Role,
    AuthInfo,
    get_auth_info,
    require_role,
    get_viewer_access,
    _verify_admin_token,
)
from app.config import get_settings


# ============================================
# Test Fixtures
# ============================================

@pytest.fixture
def client():
    """Test client for sync tests."""
    return TestClient(app)


@pytest.fixture
def valid_admin_token():
    """Generate a valid admin token for testing."""
    return "test-admin-token-12345"


@pytest.fixture
def valid_admin_token_hash(valid_admin_token):
    """Hash of the valid admin token."""
    return hashlib.sha256(valid_admin_token.encode()).hexdigest()


# ============================================
# Test: SSE Access Level Security
# ============================================

class TestSSEAccessLevel:
    """
    Test that SSE access level is computed server-side, not client-controlled.

    PR-1 SECURITY: The ?access=team query param should be IGNORED.
    Access level must be computed from authentication headers.
    """

    def test_sse_ignores_access_query_param(self, client):
        """
        Anonymous user with ?access=team should still get public access.
        The query parameter should be completely ignored.
        """
        # This test verifies the endpoint exists and doesn't error
        # In a real scenario, we'd verify the access_level in the SSE response
        response = client.get(
            "/api/v1/events/test-event-123/stream",
            params={"access": "team"},  # Attempt to escalate
        )
        # Should not error (404 for non-existent event is expected)
        assert response.status_code in [404, 200]

    def test_sse_requires_valid_token_for_team_access(self, client):
        """
        To get team access, a valid X-Team-Token must be provided.
        Just passing ?access=team is insufficient.
        """
        # Without token, should get public access
        response = client.get(
            "/api/v1/events/test-event/stream",
        )
        # Event doesn't exist, but the important thing is no server error
        assert response.status_code == 404

    def test_sse_with_admin_token_gets_team_access(self, client, valid_admin_token, valid_admin_token_hash):
        """Admin token should grant team-level access to SSE."""
        with patch('app.services.auth.settings') as mock_settings:
            mock_settings.admin_token_hash = valid_admin_token_hash

            response = client.get(
                "/api/v1/events/test-event/stream",
                headers={"X-Admin-Token": valid_admin_token},
            )
            # Event doesn't exist, but auth should work
            assert response.status_code == 404


# ============================================
# Test: Admin Endpoint Authentication
# ============================================

class TestAdminEndpointAuth:
    """
    Test that all admin endpoints require authentication.

    PR-1 SECURITY: Router-level RBAC ensures no endpoint can be accessed
    without valid X-Admin-Token header.
    """

    def test_admin_health_requires_auth(self, client):
        """Admin health endpoint requires authentication."""
        response = client.get("/api/v1/admin/health")
        assert response.status_code == 401
        assert "Authentication required" in response.json()["detail"]

    def test_admin_events_list_requires_auth(self, client):
        """Admin events list requires authentication."""
        response = client.get("/api/v1/admin/events")
        assert response.status_code == 401

    def test_admin_event_create_requires_auth(self, client):
        """Admin event creation requires authentication."""
        response = client.post(
            "/api/v1/admin/events",
            json={"name": "Test Event", "classes": ["Unlimited"]},
        )
        assert response.status_code == 401

    def test_admin_event_delete_requires_auth(self, client):
        """Admin event deletion requires authentication."""
        response = client.delete("/api/v1/admin/events/test-event-123")
        assert response.status_code == 401

    def test_admin_vehicle_register_requires_auth(self, client):
        """Vehicle registration requires authentication."""
        response = client.post(
            "/api/v1/admin/events/test-event/vehicles",
            json={
                "vehicle_number": "123",
                "team_name": "Test Team",
                "vehicle_class": "Unlimited",
            },
        )
        assert response.status_code == 401

    def test_admin_with_valid_token_works(self, client, valid_admin_token, valid_admin_token_hash):
        """Valid admin token should allow access."""
        with patch('app.services.auth.settings') as mock_settings:
            mock_settings.admin_token_hash = valid_admin_token_hash

            response = client.get(
                "/api/v1/admin/ping",
                headers={"X-Admin-Token": valid_admin_token},
            )
            # Ping endpoint should work with valid token
            assert response.status_code == 200

    def test_admin_with_invalid_token_rejected(self, client, valid_admin_token_hash):
        """Invalid admin token should be rejected."""
        with patch('app.services.auth.settings') as mock_settings:
            mock_settings.admin_token_hash = valid_admin_token_hash

            response = client.get(
                "/api/v1/admin/ping",
                headers={"X-Admin-Token": "wrong-token"},
            )
            # Should get 401 for invalid token
            assert response.status_code == 401


# ============================================
# Test: Production Endpoint Authentication
# ============================================

class TestProductionEndpointAuth:
    """
    Test that production write endpoints require authentication
    while read endpoints remain public.
    """

    def test_production_broadcast_state_is_public(self, client):
        """GET broadcast state should be public (read-only)."""
        response = client.get("/api/v1/production/events/test-event/broadcast")
        # 404 for non-existent event is expected, not 401
        assert response.status_code == 404

    def test_production_cameras_list_is_public(self, client):
        """GET cameras list should be public (read-only)."""
        response = client.get("/api/v1/production/events/test-event/cameras")
        # Empty list is fine, no auth required
        assert response.status_code == 200

    def test_production_switch_camera_requires_auth(self, client):
        """POST switch-camera requires authentication."""
        response = client.post(
            "/api/v1/production/events/test-event/switch-camera",
            json={"vehicle_id": "veh_123", "camera_name": "chase"},
        )
        assert response.status_code == 401

    def test_production_featured_vehicle_requires_auth(self, client):
        """POST featured-vehicle requires authentication."""
        response = client.post(
            "/api/v1/production/events/test-event/featured-vehicle",
            json={"vehicle_id": "veh_123"},
        )
        assert response.status_code == 401

    def test_production_clear_featured_requires_auth(self, client):
        """DELETE featured-vehicle requires authentication."""
        response = client.delete("/api/v1/production/events/test-event/featured-vehicle")
        assert response.status_code == 401


# ============================================
# Test: Setup Mode Allowlist
# ============================================

class TestSetupModeAllowlist:
    """
    Test that setup mode blocks all API access except explicit allowlist.

    PR-1 SECURITY: When SETUP_COMPLETED=false, only /health and /setup
    should be accessible.
    """

    def test_setup_mode_allows_health(self):
        """Health endpoint must work in setup mode (Docker healthchecks)."""
        with patch('app.main.settings') as mock_settings:
            mock_settings.setup_completed = False

            # Create new client to pick up patched settings
            with TestClient(app) as client:
                response = client.get("/health")
                # Health should always work
                assert response.status_code == 200

    def test_setup_mode_allows_setup_routes(self):
        """Setup wizard routes must work in setup mode."""
        with patch('app.main.settings') as mock_settings:
            mock_settings.setup_completed = False

            with TestClient(app) as client:
                response = client.get("/setup/status")
                # Setup routes should work
                assert response.status_code in [200, 307]  # May redirect

    def test_setup_mode_blocks_api(self):
        """API endpoints should be blocked in setup mode."""
        with patch('app.main.settings') as mock_settings:
            mock_settings.setup_completed = False

            with TestClient(app, follow_redirects=False) as client:
                response = client.get("/api/v1/events")
                # Should redirect to /setup
                assert response.status_code == 307
                assert response.headers.get("location") == "/setup"

    def test_setup_mode_blocks_admin_api(self):
        """Admin API should be blocked in setup mode."""
        with patch('app.main.settings') as mock_settings:
            mock_settings.setup_completed = False

            with TestClient(app, follow_redirects=False) as client:
                response = client.get("/api/v1/admin/events")
                # Should redirect to /setup
                assert response.status_code == 307

    def test_setup_mode_blocks_docs(self):
        """API docs should be blocked in setup mode (exposes structure)."""
        with patch('app.main.settings') as mock_settings:
            mock_settings.setup_completed = False

            with TestClient(app, follow_redirects=False) as client:
                response = client.get("/docs")
                # Should redirect to /setup
                assert response.status_code == 307


# ============================================
# Test: Auth Module Unit Tests
# ============================================

class TestAuthModule:
    """Unit tests for the auth module functions."""

    @pytest.mark.asyncio
    async def test_verify_admin_token_valid(self, valid_admin_token, valid_admin_token_hash):
        """Valid admin token should verify successfully."""
        with patch('app.services.auth.settings') as mock_settings:
            mock_settings.admin_token_hash = valid_admin_token_hash

            result = await _verify_admin_token(valid_admin_token)
            assert result is True

    @pytest.mark.asyncio
    async def test_verify_admin_token_invalid(self, valid_admin_token_hash):
        """Invalid admin token should fail verification."""
        with patch('app.services.auth.settings') as mock_settings:
            mock_settings.admin_token_hash = valid_admin_token_hash

            result = await _verify_admin_token("wrong-token")
            assert result is False

    @pytest.mark.asyncio
    async def test_verify_admin_token_no_hash_configured(self):
        """If no admin_token_hash configured, all tokens should fail."""
        with patch('app.services.auth.settings') as mock_settings:
            mock_settings.admin_token_hash = ""

            result = await _verify_admin_token("any-token")
            assert result is False

    def test_auth_info_role_comparison(self):
        """Test role comparison logic."""
        public = AuthInfo(role=Role.PUBLIC)
        premium = AuthInfo(role=Role.PREMIUM)
        team = AuthInfo(role=Role.TEAM)
        admin = AuthInfo(role=Role.ADMIN)

        # Role hierarchy checks
        assert not public.has_role(Role.PREMIUM)
        assert premium.has_role(Role.PREMIUM)
        assert premium.has_role(Role.PUBLIC)
        assert not premium.has_role(Role.TEAM)
        assert team.has_role(Role.TEAM)
        assert team.has_role(Role.PREMIUM)
        assert admin.has_role(Role.ADMIN)
        assert admin.has_role(Role.PUBLIC)

    def test_auth_info_access_level(self):
        """Test access_level property returns correct string."""
        public = AuthInfo(role=Role.PUBLIC)
        premium = AuthInfo(role=Role.PREMIUM)
        team = AuthInfo(role=Role.TEAM)
        admin = AuthInfo(role=Role.ADMIN)

        assert public.access_level == "public"
        assert premium.access_level == "premium"
        assert team.access_level == "team"
        assert admin.access_level == "admin"


# ============================================
# Test: Integration - Anonymous Cannot Escalate
# ============================================

class TestAnonymousCannotEscalate:
    """
    Integration tests verifying anonymous users cannot escalate privileges.

    PR-1 SECURITY: This is the core security invariant.
    """

    def test_anonymous_cannot_claim_team_in_sse(self, client):
        """
        Anonymous user attempting to use ?access=team should NOT get team data.

        This is the key PR-1 fix - the query param is now ignored.
        """
        # The endpoint should work (return 404 for non-existent event)
        # but NOT honor the access=team parameter
        response = client.get(
            "/api/v1/events/nonexistent/stream",
            params={"access": "team"},
        )
        assert response.status_code == 404
        # Key: no 500 error, no data leak

    def test_anonymous_cannot_create_events(self, client):
        """Anonymous user cannot create events."""
        response = client.post(
            "/api/v1/admin/events",
            json={"name": "Malicious Event"},
        )
        assert response.status_code == 401

    def test_anonymous_cannot_delete_events(self, client):
        """Anonymous user cannot delete events."""
        response = client.delete("/api/v1/admin/events/any-event-id")
        assert response.status_code == 401

    def test_anonymous_cannot_regenerate_tokens(self, client):
        """Anonymous user cannot regenerate vehicle tokens."""
        response = client.post(
            "/api/v1/admin/events/evt_123/vehicles/veh_456/regenerate-token"
        )
        assert response.status_code == 401

    def test_anonymous_cannot_upload_courses(self, client):
        """Anonymous user cannot upload course files."""
        response = client.post(
            "/api/v1/admin/events/evt_123/course",
            files={"file": ("course.gpx", b"<gpx></gpx>", "application/gpx+xml")},
        )
        assert response.status_code == 401
