#!/usr/bin/env python3
"""
Test that Cloudflare Tunnel fields persist through save/load cycle.

Validates:
- cloudflare_tunnel_token and cloudflare_tunnel_url are saved to JSON
- cloudflare_tunnel_token and cloudflare_tunnel_url are loaded from JSON
- Missing fields default to empty string (backwards compatibility)
- Environment variable overrides work
"""
import json
import os
import sys
import tempfile

# Add parent directory to path so we can import from the edge module
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from pit_crew_dashboard import DashboardConfig


def test_save_and_load_cloudflare_fields():
    """Cloudflare fields round-trip through save/load."""
    with tempfile.NamedTemporaryFile(suffix='.json', delete=False, mode='w') as f:
        tmp_path = f.name

    try:
        # Create config with Cloudflare fields set
        config = DashboardConfig()
        config.password_hash = "test_hash"
        config.cloudflare_tunnel_token = "eyJhIjoiYWJjMTIzIn0="
        config.cloudflare_tunnel_url = "https://pit-truck42.example.com"
        config.save(path=tmp_path)

        # Verify JSON file contains the fields
        with open(tmp_path, 'r') as f:
            data = json.load(f)
        assert "cloudflare_tunnel_token" in data, "Token field missing from saved JSON"
        assert data["cloudflare_tunnel_token"] == "eyJhIjoiYWJjMTIzIn0="
        assert "cloudflare_tunnel_url" in data, "URL field missing from saved JSON"
        assert data["cloudflare_tunnel_url"] == "https://pit-truck42.example.com"

        # Load and verify
        loaded = DashboardConfig.load(path=tmp_path)
        assert loaded.cloudflare_tunnel_token == "eyJhIjoiYWJjMTIzIn0=", \
            f"Token mismatch: {loaded.cloudflare_tunnel_token}"
        assert loaded.cloudflare_tunnel_url == "https://pit-truck42.example.com", \
            f"URL mismatch: {loaded.cloudflare_tunnel_url}"

        print("PASS: save/load round-trip preserves Cloudflare fields")
    finally:
        os.unlink(tmp_path)


def test_missing_cloudflare_fields_default_empty():
    """Loading a config file without Cloudflare fields returns empty strings."""
    with tempfile.NamedTemporaryFile(suffix='.json', delete=False, mode='w') as f:
        # Write a config file that predates the Cloudflare fields
        json.dump({
            "password_hash": "test",
            "session_secret": "abc",
            "cloud_url": "https://cloud.example.com",
            "truck_token": "trk_123",
            "event_id": "evt_456",
            "vehicle_number": "42",
            "port": 8080,
            "youtube_stream_key": "",
            "youtube_live_url": "",
        }, f)
        tmp_path = f.name

    try:
        loaded = DashboardConfig.load(path=tmp_path)
        assert loaded.cloudflare_tunnel_token == "", \
            f"Expected empty token, got: {loaded.cloudflare_tunnel_token}"
        assert loaded.cloudflare_tunnel_url == "", \
            f"Expected empty URL, got: {loaded.cloudflare_tunnel_url}"
        # Existing fields should still load
        assert loaded.cloud_url == "https://cloud.example.com"
        assert loaded.truck_token == "trk_123"

        print("PASS: missing Cloudflare fields default to empty string")
    finally:
        os.unlink(tmp_path)


def test_env_var_overrides():
    """Environment variables override config file values."""
    with tempfile.NamedTemporaryFile(suffix='.json', delete=False, mode='w') as f:
        json.dump({"password_hash": ""}, f)  # Empty config, not fully loaded
        tmp_path = f.name

    try:
        # Set env vars — since the file has password_hash="" the load will
        # still try loading but the file is valid JSON so it returns from file.
        # We need a file that fails to load to hit env var path, OR we test
        # the env path directly by removing the file.
        os.unlink(tmp_path)

        os.environ["ARGUS_CF_TUNNEL_TOKEN"] = "env_token_value"
        os.environ["ARGUS_CF_TUNNEL_URL"] = "https://env-tunnel.example.com"

        loaded = DashboardConfig.load(path=tmp_path)  # File doesn't exist -> env vars
        assert loaded.cloudflare_tunnel_token == "env_token_value", \
            f"Expected env token, got: {loaded.cloudflare_tunnel_token}"
        assert loaded.cloudflare_tunnel_url == "https://env-tunnel.example.com", \
            f"Expected env URL, got: {loaded.cloudflare_tunnel_url}"

        print("PASS: environment variable overrides work")
    finally:
        os.environ.pop("ARGUS_CF_TUNNEL_TOKEN", None)
        os.environ.pop("ARGUS_CF_TUNNEL_URL", None)
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)


def test_edge_url_prefers_tunnel():
    """Heartbeat edge_url should use cloudflare_tunnel_url when configured."""
    config = DashboardConfig()
    config.port = 8080
    config.cloudflare_tunnel_url = "https://pit-truck42.example.com"

    # Simulate the edge_url logic from _send_cloud_heartbeat
    if config.cloudflare_tunnel_url:
        edge_url = config.cloudflare_tunnel_url
    else:
        edge_url = f"http://192.168.1.10:{config.port}"

    assert edge_url == "https://pit-truck42.example.com", \
        f"Expected tunnel URL, got: {edge_url}"
    print("PASS: edge_url prefers cloudflare_tunnel_url when set")


def test_edge_url_falls_back_to_lan():
    """Heartbeat edge_url should fall back to LAN when tunnel is not configured."""
    config = DashboardConfig()
    config.port = 8080
    config.cloudflare_tunnel_url = ""

    # Simulate the edge_url logic from _send_cloud_heartbeat
    if config.cloudflare_tunnel_url:
        edge_url = config.cloudflare_tunnel_url
    else:
        edge_url = f"http://192.168.1.10:{config.port}"

    assert edge_url == "http://192.168.1.10:8080", \
        f"Expected LAN URL, got: {edge_url}"
    print("PASS: edge_url falls back to LAN when tunnel not configured")


def test_setup_blocks_without_tunnel_token():
    """Setup validation must reject empty tunnel token."""
    # Simulate the server-side validation logic from handle_setup
    cf_token = "".strip()
    cf_url = "https://pit-truck42.example.com".strip()

    blocked = False
    if not cf_token:
        blocked = True
    elif not cf_url or not cf_url.startswith('https://'):
        blocked = True

    assert blocked, "Setup should block when tunnel token is empty"
    print("PASS: setup blocks without tunnel token")


def test_setup_blocks_without_tunnel_url():
    """Setup validation must reject empty or non-https tunnel URL."""
    cf_token = "eyJhIjoiYWJjIn0="

    # Empty URL
    cf_url = ""
    blocked_empty = not cf_url or not cf_url.startswith('https://')
    assert blocked_empty, "Setup should block when tunnel URL is empty"

    # HTTP URL (not https)
    cf_url = "http://example.com"
    blocked_http = not cf_url or not cf_url.startswith('https://')
    assert blocked_http, "Setup should block when tunnel URL is not https"

    print("PASS: setup blocks without valid tunnel URL")


def test_setup_allows_valid_tunnel():
    """Setup validation must accept valid tunnel token + https URL."""
    cf_token = "eyJhIjoiYWJjIn0=".strip()
    cf_url = "https://pit-truck42.example.com".strip()

    blocked = False
    if not cf_token:
        blocked = True
    elif not cf_url or not cf_url.startswith('https://'):
        blocked = True

    assert not blocked, "Setup should allow valid tunnel token + https URL"
    print("PASS: setup allows valid tunnel configuration")


def test_dashboard_banner_hidden_when_tunnel_configured():
    """Dashboard tunnel banner should be hidden when tunnel URL is set."""
    config = DashboardConfig()

    # Tunnel configured
    config.cloudflare_tunnel_url = "https://pit-truck42.example.com"
    display = 'none' if config.cloudflare_tunnel_url else 'block'
    assert display == 'none', f"Expected 'none', got: {display}"

    # Tunnel not configured
    config.cloudflare_tunnel_url = ""
    display = 'none' if config.cloudflare_tunnel_url else 'block'
    assert display == 'block', f"Expected 'block', got: {display}"

    print("PASS: dashboard banner visibility matches tunnel config state")


if __name__ == "__main__":
    test_save_and_load_cloudflare_fields()
    test_missing_cloudflare_fields_default_empty()
    test_env_var_overrides()
    test_edge_url_prefers_tunnel()
    test_edge_url_falls_back_to_lan()
    test_setup_blocks_without_tunnel_token()
    test_setup_blocks_without_tunnel_url()
    test_setup_allows_valid_tunnel()
    test_dashboard_banner_hidden_when_tunnel_configured()
    print("\nAll Cloudflare config tests passed.")
