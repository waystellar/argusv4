#!/usr/bin/env python3
"""
Fuel API Test Script

Tests the fuel tracking API endpoints with proper session handling.

Usage:
    python test_fuel_api.py [dashboard_url]

Example:
    python test_fuel_api.py http://192.168.0.18:8080
"""
import sys
import json
import requests
from typing import Optional, Dict, Any

# Default dashboard URL
DASHBOARD_URL = sys.argv[1] if len(sys.argv) > 1 else "http://localhost:8080"

# Test session - in production you'd login first
SESSION = requests.Session()


def print_result(test_name: str, passed: bool, details: str = ""):
    """Print test result."""
    status = "\033[92m[PASS]\033[0m" if passed else "\033[91m[FAIL]\033[0m"
    print(f"{status} {test_name}")
    if details:
        print(f"       {details}")


def get_fuel_status() -> Optional[Dict[str, Any]]:
    """Get current fuel status."""
    try:
        resp = SESSION.get(f"{DASHBOARD_URL}/api/fuel/status")
        if resp.status_code == 200:
            return resp.json()
        elif resp.status_code == 401:
            print("       Note: Requires authentication")
            return None
        return None
    except Exception as e:
        print(f"       Error: {e}")
        return None


def update_fuel(data: Dict[str, Any]) -> tuple[bool, Dict[str, Any]]:
    """Update fuel state."""
    try:
        resp = SESSION.post(
            f"{DASHBOARD_URL}/api/fuel/update",
            json=data,
            headers={"Content-Type": "application/json"}
        )
        result = resp.json() if resp.content else {}
        return resp.status_code == 200, result
    except Exception as e:
        return False, {"error": str(e)}


def test_fuel_api():
    """Run all fuel API tests."""
    print("=" * 50)
    print("  Fuel API Test Suite")
    print("=" * 50)
    print(f"Dashboard: {DASHBOARD_URL}")
    print()

    # Test 1: Get initial status
    print("Test 1: Get Fuel Status")
    print("-" * 30)
    status = get_fuel_status()
    if status:
        print_result("fuel_set field exists", "fuel_set" in status)
        print_result("tank_capacity_gal exists", "tank_capacity_gal" in status)
        print_result("current_fuel_gal exists", "current_fuel_gal" in status)
        print(f"       Current state: fuel_set={status.get('fuel_set')}, "
              f"fuel={status.get('current_fuel_gal')} gal")
    else:
        print_result("Get fuel status", False, "Could not retrieve status")
    print()

    # Test 2: Set fuel level
    print("Test 2: Set Fuel Level")
    print("-" * 30)
    success, result = update_fuel({"current_fuel_gal": 25.5})
    print_result("Set fuel to 25.5 gal", success, str(result) if not success else "")

    # Verify it was set
    status = get_fuel_status()
    if status and status.get("fuel_set"):
        print_result("fuel_set is now True", status.get("fuel_set") == True)
        print_result("current_fuel_gal is 25.5",
                    abs((status.get("current_fuel_gal") or 0) - 25.5) < 0.1)
    print()

    # Test 3: Validation - negative value
    print("Test 3: Validation - Negative Fuel")
    print("-" * 30)
    success, result = update_fuel({"current_fuel_gal": -10})
    print_result("Negative fuel rejected", not success,
                result.get("error", "") if not success else "Should have been rejected")
    print()

    # Test 4: Validation - over capacity
    print("Test 4: Validation - Over Capacity")
    print("-" * 30)
    success, result = update_fuel({"current_fuel_gal": 999})
    print_result("Over-capacity rejected", not success,
                result.get("error", "") if not success else "Should have been rejected")
    print()

    # Test 5: Tank filled shortcut
    print("Test 5: Tank Filled Shortcut")
    print("-" * 30)
    success, result = update_fuel({"filled": True})
    print_result("Tank filled accepted", success)

    status = get_fuel_status()
    if status:
        fuel_pct = status.get("fuel_percent", 0)
        print_result("Fuel at 100%", fuel_pct is not None and fuel_pct >= 99,
                    f"fuel_percent={fuel_pct}")
    print()

    # Test 6: Update configuration
    print("Test 6: Update Configuration")
    print("-" * 30)
    success, result = update_fuel({
        "tank_capacity_gal": 42,
        "consumption_rate_mpg": 5.5
    })
    print_result("Update tank capacity and MPG", success)

    status = get_fuel_status()
    if status:
        print_result("Tank capacity is 42",
                    status.get("tank_capacity_gal") == 42,
                    f"Got {status.get('tank_capacity_gal')}")
        print_result("MPG is 5.5",
                    status.get("consumption_rate_mpg") == 5.5,
                    f"Got {status.get('consumption_rate_mpg')}")
    print()

    # Test 7: Verify persistence fields
    print("Test 7: Persistence Fields")
    print("-" * 30)
    status = get_fuel_status()
    if status:
        print_result("updated_at exists", "updated_at" in status)
        print_result("source exists", "source" in status)
        if status.get("updated_at", 0) > 0:
            print_result("updated_at is non-zero", True)
    print()

    # Test 8: Set specific fuel level for verification
    print("Test 8: Set and Verify Exact Value")
    print("-" * 30)
    test_fuel = 18.7
    success, _ = update_fuel({"current_fuel_gal": test_fuel})
    status = get_fuel_status()
    if status:
        actual = status.get("current_fuel_gal")
        print_result(f"Fuel set to {test_fuel} gal",
                    actual is not None and abs(actual - test_fuel) < 0.1,
                    f"Got {actual}")
    print()

    print("=" * 50)
    print("  Test Summary")
    print("=" * 50)
    print("""
Data Flow:
  UI (promptFuelLevel) -> POST /api/fuel/update
    -> handle_fuel_update() validates input
    -> Updates _fuel_strategy dict
    -> _save_fuel_state() persists to fuel_state.json
    -> Returns success
  UI (loadFuelStatus) -> GET /api/fuel/status
    -> Reads from _fuel_strategy (loaded from file on startup)
    -> Returns fuel state with fuel_set flag

Key Features:
  - fuel_set=False until crew sets value (shows "Unset" in UI)
  - Validation: 0 <= fuel <= tank_capacity
  - Persistence: /opt/argus/config/fuel_state.json
  - Audit: updated_at, updated_by, source fields
""")


if __name__ == "__main__":
    test_fuel_api()
