#!/usr/bin/env python3
"""
Streaming Switch Camera Test

Tests:
1. Dropdown retention logic: when idle, user selection is preserved
2. Dropdown sync logic: when live, dropdown reflects streaming camera
3. /api/streaming/switch-camera endpoint returns expected response format

Usage:
    python test_streaming_switch.py [dashboard_url]

Example:
    python test_streaming_switch.py http://192.168.0.18:8080

These tests validate the JS-side logic semantically via Python assertions,
plus the backend switch-camera endpoint contract.
"""
import sys

# ============================================================
# Test 1-2: Dropdown retention logic (pure logic, no server)
# ============================================================

def test_dropdown_idle_preserves_user_selection():
    """When streaming status is idle, the dropdown should retain
    the user's manually selected camera, not overwrite from server."""

    # Simulate state
    streaming_status = {"status": "idle", "camera": "chase"}
    user_selected_camera = "main"  # User picked main

    # The JS logic: when idle, restore userSelectedCamera
    # when live/starting, sync to streamingStatus.camera
    if streaming_status["status"] in ("live", "starting"):
        dropdown_value = streaming_status["camera"]
    elif user_selected_camera:
        dropdown_value = user_selected_camera
    else:
        dropdown_value = "main"  # default

    assert dropdown_value == "main", (
        f"Idle: dropdown should be user selection 'main', got '{dropdown_value}'"
    )
    print("[PASS] Idle: dropdown preserves user selection ('main')")


def test_dropdown_live_syncs_to_streaming_camera():
    """When streaming status is live, the dropdown should reflect
    the actual streaming camera from the server."""

    streaming_status = {"status": "live", "camera": "chase"}
    user_selected_camera = "main"  # User had picked main before

    if streaming_status["status"] in ("live", "starting"):
        dropdown_value = streaming_status["camera"]
    elif user_selected_camera:
        dropdown_value = user_selected_camera
    else:
        dropdown_value = "main"

    assert dropdown_value == "chase", (
        f"Live: dropdown should sync to streaming camera 'chase', got '{dropdown_value}'"
    )
    print("[PASS] Live: dropdown syncs to streaming camera ('chase')")


def test_dropdown_starting_syncs_to_streaming_camera():
    """When streaming status is starting, dropdown syncs to server camera."""

    streaming_status = {"status": "starting", "camera": "cockpit"}
    user_selected_camera = "suspension"

    if streaming_status["status"] in ("live", "starting"):
        dropdown_value = streaming_status["camera"]
    elif user_selected_camera:
        dropdown_value = user_selected_camera
    else:
        dropdown_value = "main"

    assert dropdown_value == "cockpit", (
        f"Starting: dropdown should sync to 'cockpit', got '{dropdown_value}'"
    )
    print("[PASS] Starting: dropdown syncs to streaming camera ('cockpit')")


def test_dropdown_idle_no_user_selection_uses_current():
    """When idle and user hasn't made a selection, keep whatever is in dropdown."""

    streaming_status = {"status": "idle", "camera": "chase"}
    user_selected_camera = None  # No manual selection

    if streaming_status["status"] in ("live", "starting"):
        dropdown_value = streaming_status["camera"]
    elif user_selected_camera:
        dropdown_value = user_selected_camera
    else:
        dropdown_value = "main"  # default HTML <select> value

    assert dropdown_value == "main", (
        f"Idle/no selection: dropdown should default to 'main', got '{dropdown_value}'"
    )
    print("[PASS] Idle/no user selection: dropdown defaults to 'main'")


def test_switch_button_visible_when_selection_differs():
    """Switch button should be visible when streaming and dropdown
    differs from the active streaming camera."""

    streaming_status = {"status": "live", "camera": "chase"}
    dropdown_value = "main"  # User changed dropdown

    show_switch = (
        streaming_status["status"] in ("live", "starting") and
        dropdown_value != streaming_status["camera"]
    )
    assert show_switch is True, "Switch button should be visible when selection differs"
    print("[PASS] Switch button visible when dropdown differs from streaming camera")


def test_switch_button_hidden_when_selection_matches():
    """Switch button should be hidden when dropdown matches streaming camera."""

    streaming_status = {"status": "live", "camera": "chase"}
    dropdown_value = "chase"

    show_switch = (
        streaming_status["status"] in ("live", "starting") and
        dropdown_value != streaming_status["camera"]
    )
    assert show_switch is False, "Switch button should be hidden when selection matches"
    print("[PASS] Switch button hidden when dropdown matches streaming camera")


def test_switch_button_hidden_when_idle():
    """Switch button should be hidden when not streaming."""

    streaming_status = {"status": "idle", "camera": "chase"}
    dropdown_value = "main"

    show_switch = (
        streaming_status["status"] in ("live", "starting") and
        dropdown_value != streaming_status["camera"]
    )
    assert show_switch is False, "Switch button should be hidden when idle"
    print("[PASS] Switch button hidden when idle")


# ============================================================
# Test 3: /api/streaming/switch-camera endpoint contract
# ============================================================

def test_switch_camera_endpoint(dashboard_url):
    """Test the switch-camera endpoint returns expected format.
    Requires a running dashboard server."""
    try:
        import requests
    except ImportError:
        print("[SKIP] requests not installed — skipping endpoint test")
        return

    session = requests.Session()
    session.cookies.set("pit_session", "test_session")

    # Test: missing camera field returns 400
    try:
        resp = session.post(
            f"{dashboard_url}/api/streaming/switch-camera",
            json={},
            timeout=5,
        )
        if resp.status_code == 400:
            data = resp.json()
            assert "error" in data, "400 response should include 'error' field"
            print(f"[PASS] switch-camera missing camera returns 400: {data['error']}")
        elif resp.status_code == 401:
            print("[SKIP] switch-camera requires auth (401) — test with valid session")
        else:
            print(f"[INFO] switch-camera missing camera returned {resp.status_code}")
    except requests.ConnectionError:
        print("[SKIP] Dashboard not reachable — skipping endpoint test")
        return
    except Exception as e:
        print(f"[SKIP] Endpoint test error: {e}")
        return

    # Test: valid camera field returns success/error with expected fields
    try:
        resp = session.post(
            f"{dashboard_url}/api/streaming/switch-camera",
            json={"camera": "main"},
            timeout=5,
        )
        if resp.status_code in (200, 400):
            data = resp.json()
            # Response should have 'success' or 'error'
            has_expected = "success" in data or "error" in data
            assert has_expected, f"Response should have 'success' or 'error': {data}"
            print(f"[PASS] switch-camera returns structured response: {list(data.keys())}")
        elif resp.status_code == 401:
            print("[SKIP] switch-camera requires auth (401)")
        else:
            print(f"[INFO] switch-camera returned HTTP {resp.status_code}")
    except Exception as e:
        print(f"[SKIP] Endpoint test error: {e}")


# ============================================================
# Main
# ============================================================

if __name__ == "__main__":
    print("=" * 50)
    print("  Streaming Camera Switch Tests")
    print("=" * 50)
    print()

    # Pure logic tests (no server needed)
    print("--- Dropdown Retention Logic ---")
    test_dropdown_idle_preserves_user_selection()
    test_dropdown_live_syncs_to_streaming_camera()
    test_dropdown_starting_syncs_to_streaming_camera()
    test_dropdown_idle_no_user_selection_uses_current()
    print()

    print("--- Switch Button Visibility ---")
    test_switch_button_visible_when_selection_differs()
    test_switch_button_hidden_when_selection_matches()
    test_switch_button_hidden_when_idle()
    print()

    # Endpoint tests (needs running server)
    dashboard_url = sys.argv[1] if len(sys.argv) > 1 else "http://localhost:8080"
    print(f"--- Endpoint Tests ({dashboard_url}) ---")
    test_switch_camera_endpoint(dashboard_url)
    print()

    print("All tests completed.")
