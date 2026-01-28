"""
Pytest configuration and fixtures for Argus Cloud tests.
"""
import os
import sys

# Add app directory to path for imports
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import pytest
from unittest.mock import patch, AsyncMock

# Set test environment before importing app
os.environ["SETUP_COMPLETED"] = "true"
os.environ["DATABASE_URL"] = "sqlite+aiosqlite:///:memory:"
os.environ["REDIS_URL"] = "redis://localhost:6379"
os.environ["SECRET_KEY"] = "test-secret-key-for-testing-only"
os.environ["DEBUG"] = "true"


@pytest.fixture(autouse=True)
def mock_redis():
    """Mock Redis client for all tests."""
    with patch("app.redis_client") as mock:
        mock.get_latest_positions = AsyncMock(return_value={})
        mock.get_visible_vehicles = AsyncMock(return_value=set())
        mock.get_latest_position = AsyncMock(return_value=None)
        mock.get_json = AsyncMock(return_value=None)
        mock.set_json = AsyncMock()
        mock.get_truck_token_info = AsyncMock(return_value=None)
        mock.cache_truck_token = AsyncMock()
        mock.publish_event = AsyncMock()
        mock.subscribe_to_event = AsyncMock()
        mock.delete_key = AsyncMock()
        yield mock


@pytest.fixture(autouse=True)
def mock_database():
    """Mock database for tests that don't need real DB."""
    # Tests can override this if they need real database
    pass
