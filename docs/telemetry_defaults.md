# Telemetry & Fuel Defaults — Design Decisions

> Last updated: 2026-01-29

---

## Principle

**Unknown = null/None, never a hardcoded fallback.** UI renders `--` for missing values. API returns `null` in JSON. Only user-configured values produce numbers.

---

## P0: Coolant / Oil Pressure / Oil Temp

### Problem

When CAN bus stops sending a field (e.g., coolant_temp), the edge dashboard retained the last-known value indefinitely via:

```python
self.telemetry.coolant_temp = payload.get('coolant_temp', self.telemetry.coolant_temp)
```

This made stale values indistinguishable from live data.

### Fix

Reset to `None` when the CAN payload omits the key:

```python
self.telemetry.coolant_temp = payload.get('coolant_temp')  # None if absent
```

**Files changed:** [pit_crew_dashboard.py:10595-10597](../edge/pit_crew_dashboard.py#L10595)

### Simulation Gating

Mock telemetry (coolant=90, oil_pressure=45, oil_temp=95) is now gated behind `ARGUS_SIMULATE_TELEMETRY` env var (default: off).

```bash
# Enable simulation telemetry for dev/testing:
ARGUS_SIMULATE_TELEMETRY=1 python pit_crew_dashboard.py
```

**File changed:** [pit_crew_dashboard.py:10735](../edge/pit_crew_dashboard.py#L10735)

### UI Initial Display

HTML initial values changed from `0` to `--` so gauges show unknown state on page load before CAN data arrives.

**Files changed:** [pit_crew_dashboard.py:2402,2407](../edge/pit_crew_dashboard.py#L2402)

The JavaScript update handler already had proper null checks (lines 4528-4543) that render `--` when data is null.

---

## P1: Fuel Tank Capacity

### Problem

`handle_fuel_status` returned `DEFAULT_TANK_CAPACITY_GAL` (95.0) when the team hadn't configured a value, making it look like 95 gallons was set.

### Fix

Return `null` when `tank_capacity_gal` is not in `_fuel_strategy`:

```python
tank_capacity = self._fuel_strategy.get('tank_capacity_gal')  # None if unset
```

`fuel_percent` is only computed when `tank_capacity is not None and tank_capacity > 0`.

**File changed:** [pit_crew_dashboard.py:9498](../edge/pit_crew_dashboard.py#L9498)

> **Note:** `handle_fuel_update` (the mutation endpoint) still uses `DEFAULT_TANK_CAPACITY_GAL` as a starting point when updating. This is intentional — it provides a reasonable default for the first configuration.

---

## P1: MPG / Consumption Rate

### Problem

`handle_fuel_status` returned `2.0` MPG when the team hadn't set a value, producing phantom range estimates.

### Fix

Return `null` when `consumption_rate_mpg` is not in `_fuel_strategy`:

```python
consumption_rate = self._fuel_strategy.get('consumption_rate_mpg')  # None if unset
```

Range calculations (`estimated_miles`, `range_miles_remaining`) only execute when `consumption_rate is not None and consumption_rate > 0`.

**File changed:** [pit_crew_dashboard.py:9499-9514](../edge/pit_crew_dashboard.py#L9499)

---

## P2: Leaderboard `lap_number`

### Problem

`LeaderboardEntry` schema lacked a `lap_number` field. Clients couldn't show which lap a vehicle was on.

### Fix

Added `lap_number: Optional[int] = None` to `LeaderboardEntry`. Populated from `crossing.lap_number` in `calculate_leaderboard`. Vehicles without crossings get `lap_number=None`.

**Files changed:**
- [schemas.py:200](../cloud/app/schemas.py#L200)
- [checkpoint_service.py:286](../cloud/app/services/checkpoint_service.py#L286)

---

## Regression Gate

```bash
bash scripts/regress/tel_defaults_gate.sh
```

14 checks across 5 sections (A–E). Expected output: `ALL CHECKS PASSED`

---

## API Contract Summary

| Field | Before | After |
|-------|--------|-------|
| `coolant_temp` (no CAN) | Last known value | `null` |
| `oil_pressure` (no CAN) | Last known value | `null` |
| `oil_temp` (no CAN) | Last known value | `null` |
| `tank_capacity_gal` (unset) | `95.0` | `null` |
| `consumption_rate_mpg` (unset) | `2.0` | `null` |
| `estimated_miles_remaining` (unset) | Phantom number | `null` |
| `range_miles_remaining` (unset) | Phantom number | `null` |
| `fuel_percent` (unset capacity) | Phantom number | `null` |
| `lap_number` (leaderboard) | Not present | `int` or `null` |

### UI Rendering Rule

| API value | Edge UI display | Cloud/React display |
|-----------|----------------|---------------------|
| `null` | `--` | `—` (em dash) or `Unknown` |
| `0` | `0` | `0` |
| Number | Formatted number | Formatted number |
