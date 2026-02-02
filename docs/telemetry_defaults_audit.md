# Telemetry & Fuel Defaults Audit

This audit documents sources of misleading defaults, where they are injected, how they flow into UI, and suggested fixes/regression tests.

## Coolant/Oil Telemetry Defaults

**Source -> Serialization -> UI**

- CAN telemetry holds coolant/oil fields as `Optional[float]` and serializes to `None` when missing in `CANDataState.to_dict()`.【F:edge/can_telemetry.py†L151-L195】
- The pit dashboard telemetry state also treats these fields as optional and serializes them into SSE payloads with `None` when missing (after rounding).【F:edge/pit_crew_dashboard.py†L320-L405】

**Default injection points**

- The pit dashboard updates telemetry using `payload.get(..., self.telemetry.coolant_temp)`, which *retains stale values* when CAN stops providing values instead of clearing to `None`.【F:edge/pit_crew_dashboard.py†L10370-L10384】
- Simulation paths inject fixed numeric values (coolant ~90, oil pressure ~45, oil temp ~95) even when live data is not available, which can be misread as live telemetry.【F:edge/pit_crew_dashboard.py†L10516-L10521】

**UI impact**

- The UI renders coolant/oil values as numbers and uses them for alert logic, so stale or simulated values look valid to the user.【F:edge/pit_crew_dashboard.py†L4397-L4448】【F:edge/pit_crew_dashboard.py†L4568-L4579】

**Suggested fixes**

- When CAN is unplugged or data is invalid, reset coolant/oil values to `None` (unknown) instead of retaining the last value.
- Gate simulation values behind an explicit "simulate telemetry" flag to avoid showing fabricated values by default.

**Regression test ideas**

- Verify that missing coolant/oil payloads reset values to `None` instead of retaining prior data.
- Ensure simulation values are only injected when the simulate flag is enabled.

## Fuel Tank Capacity Defaults

**Source -> Serialization -> UI**

- `DEFAULT_TANK_CAPACITY_GAL` defaults to 95.0 while the max capacity constant is 250.0.【F:edge/pit_crew_dashboard.py†L123-L127】
- `handle_fuel_status()` uses `DEFAULT_TANK_CAPACITY_GAL` when `tank_capacity` is not set, so the status response always reports 95 if unset.【F:edge/pit_crew_dashboard.py†L9270-L9295】
- The UI prompt uses this reported capacity to present a "max" to the user, which can appear as a real configuration rather than a default.【F:edge/pit_crew_dashboard.py†L5522-L5538】

**Suggested fixes**

- Return `tank_capacity_gal: null` (unknown) when the user has not set fuel configuration.
- Use the max capacity only for validation, not as an implied default in the UI.

**Regression test ideas**

- Confirm that `tank_capacity_gal` is `null` when fuel is not set.
- UI should show "Unset"/blank capacity until configured.

## Fuel MPG Defaults and Range Calculations

**Source -> Serialization -> UI**

- `handle_fuel_status()` uses a default `consumption_rate_mpg = 2.0` when unset and computes range if `fuel_set` is true.【F:edge/pit_crew_dashboard.py†L9270-L9290】
- `handle_fuel_update()` persists `consumption_rate_mpg` values from the UI into state, which then influences range calculations.【F:edge/pit_crew_dashboard.py†L9309-L9335】
- The UI allows editing MPG and sends it to the update endpoint via `fuelMpgInput`.【F:edge/pit_crew_dashboard.py†L2954-L2956】【F:edge/pit_crew_dashboard.py†L5571-L5600】

**Suggested fixes**

- Treat MPG as unknown until explicitly set (store `null`).
- Only compute remaining range when MPG is set and fuel is configured.

**Regression test ideas**

- Ensure range values are `null` when MPG is not set.
- Ensure updating MPG updates range calculations as expected.

## Leaderboard Lap Count Visibility

**Source -> Serialization -> UI**

- Telemetry ingest tracks checkpoint crossings and publishes progress (miles remaining) into SSE/Redis, but the leaderboard schema does not include a lap number field.【F:cloud/app/routes/telemetry.py†L175-L179】【F:cloud/app/routes/telemetry.py†L228-L273】【F:cloud/app/schemas.py†L189-L202】
- `calculate_leaderboard()` computes leaderboard entries without a lap number (no field in `LeaderboardEntry`).【F:cloud/app/routes/leaderboard.py†L16-L30】

**Suggested fixes**

- Add `lap_number: Optional[int]` to the leaderboard schema and populate it when available; otherwise return `null` to avoid implied values.

**Regression test ideas**

- Validate that leaderboard entries include `lap_number` with `null` when not computed.

