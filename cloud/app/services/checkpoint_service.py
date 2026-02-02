"""
Checkpoint crossing detection and split time calculations.
"""
from typing import Optional
from datetime import datetime

from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.dialects.postgresql import insert  # FIXED: For ON CONFLICT (Issue #9 from audit)

from app.models import Checkpoint, CheckpointCrossing, Vehicle, EventVehicle, Event, VehicleLapState, generate_id
from app.services.geo import haversine_distance, format_time_delta, compute_progress_miles, METERS_PER_MILE
from app.schemas import (
    CheckpointCrossingResponse,
    LeaderboardEntry,
    LeaderboardResponse,
    SplitCrossing,
    CheckpointSplit,
    SplitsResponse,
)
from app import redis_client


async def get_vehicle_lap_state(
    db: AsyncSession,
    event_id: str,
    vehicle_id: str,
) -> VehicleLapState:
    """Get or create vehicle lap state."""
    result = await db.execute(
        select(VehicleLapState).where(
            VehicleLapState.event_id == event_id,
            VehicleLapState.vehicle_id == vehicle_id,
        )
    )
    state = result.scalar_one_or_none()

    if not state:
        state = VehicleLapState(
            event_id=event_id,
            vehicle_id=vehicle_id,
            current_lap=1,
            last_checkpoint=0,
        )
        db.add(state)
        await db.flush()

    return state


async def check_checkpoint_crossings(
    db: AsyncSession,
    event_id: str,
    vehicle_id: str,
    lat: float,
    lon: float,
    ts_ms: int,
) -> list[CheckpointCrossingResponse]:
    """
    Check if vehicle crossed any checkpoints.
    Supports multi-lap races by tracking vehicle lap state.
    Returns list of new crossings.
    """
    # Get event for total_laps
    result = await db.execute(select(Event).where(Event.event_id == event_id))
    event = result.scalar_one_or_none()
    if not event:
        return []

    total_laps = event.total_laps or 1

    # Get all checkpoints for event, ordered by number
    result = await db.execute(
        select(Checkpoint)
        .where(Checkpoint.event_id == event_id)
        .order_by(Checkpoint.checkpoint_number)
    )
    checkpoints = result.scalars().all()
    if not checkpoints:
        return []

    max_checkpoint = max(cp.checkpoint_number for cp in checkpoints)

    # Get vehicle's current lap state
    lap_state = await get_vehicle_lap_state(db, event_id, vehicle_id)

    new_crossings = []

    for checkpoint in checkpoints:
        # Calculate distance from vehicle to checkpoint
        distance = haversine_distance(lat, lon, checkpoint.lat, checkpoint.lon)

        if distance <= checkpoint.radius_m:
            current_lap = lap_state.current_lap

            # Determine if this is the expected next checkpoint
            expected_next = lap_state.last_checkpoint + 1
            if expected_next > max_checkpoint:
                # Wrapped to next lap
                expected_next = 1
                if lap_state.current_lap < total_laps:
                    current_lap = lap_state.current_lap + 1

            # Only process if this is the expected checkpoint (prevents out-of-order)
            if checkpoint.checkpoint_number != expected_next:
                continue

            # FIXED: Use INSERT ON CONFLICT DO NOTHING to prevent race condition (Issue #9 from audit)
            # Previously used check-then-insert which could create duplicates with concurrent requests
            crossing_id = generate_id("cx")
            stmt = insert(CheckpointCrossing).values(
                crossing_id=crossing_id,
                event_id=event_id,
                vehicle_id=vehicle_id,
                checkpoint_id=checkpoint.checkpoint_id,
                checkpoint_number=checkpoint.checkpoint_number,
                lap_number=current_lap,
                ts_ms=ts_ms,
            ).on_conflict_do_nothing(
                # Unique constraint: event_id, vehicle_id, checkpoint_id, lap_number
                index_elements=['event_id', 'vehicle_id', 'checkpoint_id', 'lap_number']
            )
            result = await db.execute(stmt)

            # Only process if we actually inserted (not a duplicate)
            if result.rowcount == 0:
                continue

            # Update lap state
            lap_state.last_checkpoint = checkpoint.checkpoint_number
            if checkpoint.checkpoint_number == max_checkpoint and current_lap > lap_state.current_lap:
                lap_state.current_lap = current_lap

            new_crossings.append(
                CheckpointCrossingResponse(
                    checkpoint_number=checkpoint.checkpoint_number,
                    checkpoint_name=checkpoint.name,
                    ts_ms=ts_ms,
                )
            )

            # Publish to SSE
            await redis_client.publish_event(
                event_id,
                "checkpoint",
                {
                    "vehicle_id": vehicle_id,
                    "checkpoint_number": checkpoint.checkpoint_number,
                    "checkpoint_name": checkpoint.name,
                    "lap_number": current_lap,
                    "ts_ms": ts_ms,
                },
            )

    if new_crossings:
        await db.commit()

    return new_crossings


async def calculate_leaderboard(
    db: AsyncSession,
    event_id: str,
) -> LeaderboardResponse:
    """
    Calculate current race standings based on lap and checkpoint progression.
    For multi-lap races: higher lap + higher checkpoint = better position.
    Ties broken by crossing time.

    FIXED: Section C - Also includes registered vehicles without any checkpoint
    crossings, shown at the bottom with "Not Started" status.
    """
    # FIXED: Section C - Get ALL registered vehicles for event first
    result = await db.execute(
        select(Vehicle, EventVehicle)
        .join(EventVehicle, Vehicle.vehicle_id == EventVehicle.vehicle_id)
        .where(
            EventVehicle.event_id == event_id,
            EventVehicle.visible == True,
        )
    )
    all_vehicles = {row.Vehicle.vehicle_id: row.Vehicle for row in result.all()}

    if not all_vehicles:
        return LeaderboardResponse(event_id=event_id, ts=datetime.utcnow(), entries=[])

    # PROGRESS-1: Get latest positions from Redis (already contain progress_miles)
    latest_positions = await redis_client.get_latest_positions(event_id)

    # PROGRESS-1: Get course length for response
    event_result = await db.execute(select(Event).where(Event.event_id == event_id))
    event_obj = event_result.scalar_one_or_none()
    course_length_miles = None
    if event_obj and event_obj.course_distance_m:
        course_length_miles = round(event_obj.course_distance_m / METERS_PER_MILE, 2)

    # Get all crossings for event, ordered by lap (desc), checkpoint (desc), time (asc)
    result = await db.execute(
        select(CheckpointCrossing)
        .where(CheckpointCrossing.event_id == event_id)
        .order_by(
            CheckpointCrossing.lap_number.desc(),
            CheckpointCrossing.checkpoint_number.desc(),
            CheckpointCrossing.ts_ms.asc(),
        )
    )
    crossings = result.scalars().all()

    # Build vehicle -> best crossing mapping (highest lap + checkpoint)
    vehicle_best: dict[str, CheckpointCrossing] = {}
    for crossing in crossings:
        vid = crossing.vehicle_id
        if vid not in vehicle_best:
            vehicle_best[vid] = crossing
        else:
            # Compare: higher lap wins, then higher checkpoint, then earlier time
            current = vehicle_best[vid]
            if (crossing.lap_number, crossing.checkpoint_number) > \
               (current.lap_number, current.checkpoint_number):
                vehicle_best[vid] = crossing
            elif (crossing.lap_number, crossing.checkpoint_number) == \
                 (current.lap_number, current.checkpoint_number):
                if crossing.ts_ms < current.ts_ms:
                    vehicle_best[vid] = crossing

    # Get checkpoint names
    result = await db.execute(
        select(Checkpoint).where(Checkpoint.event_id == event_id)
    )
    checkpoint_names = {cp.checkpoint_number: cp.name for cp in result.scalars().all()}

    # Sort vehicles with crossings by (lap desc, checkpoint desc, time asc)
    sorted_with_crossings = sorted(
        [(vid, vehicle_best[vid]) for vid in vehicle_best if vid in all_vehicles],
        key=lambda x: (-x[1].lap_number, -x[1].checkpoint_number, x[1].ts_ms),
    )

    # FIXED: Section C - Get vehicles without any crossings
    vehicles_without_crossings = [
        vid for vid in all_vehicles
        if vid not in vehicle_best
    ]
    # Sort by vehicle number for consistency
    vehicles_without_crossings.sort(
        key=lambda vid: all_vehicles[vid].vehicle_number
    )

    # Calculate leader time at each (lap, checkpoint) for deltas
    leader_times: dict[tuple[int, int], int] = {}
    for vid, crossing in sorted_with_crossings:
        key = (crossing.lap_number, crossing.checkpoint_number)
        if key not in leader_times:
            leader_times[key] = crossing.ts_ms

    # Build leaderboard entries - vehicles with crossings first
    entries = []
    for position, (vid, crossing) in enumerate(sorted_with_crossings, start=1):
        vehicle = all_vehicles.get(vid)
        if not vehicle:
            continue

        key = (crossing.lap_number, crossing.checkpoint_number)
        leader_time = leader_times.get(key, crossing.ts_ms)
        delta_ms = crossing.ts_ms - leader_time

        # Format checkpoint name with lap if multi-lap
        cp_name = checkpoint_names.get(crossing.checkpoint_number)
        if crossing.lap_number > 1:
            cp_display = f"Lap {crossing.lap_number} - {cp_name or f'CP{crossing.checkpoint_number}'}"
        else:
            cp_display = cp_name

        # PROGRESS-1: Get progress from cached position
        pos = latest_positions.get(vid, {})
        entries.append(
            LeaderboardEntry(
                position=position,
                vehicle_id=vid,
                vehicle_number=vehicle.vehicle_number,
                team_name=vehicle.team_name,
                driver_name=vehicle.driver_name,
                last_checkpoint=crossing.checkpoint_number,
                last_checkpoint_name=cp_display,
                delta_to_leader_ms=delta_ms,
                delta_formatted=format_time_delta(delta_ms),
                lap_number=crossing.lap_number,
                progress_miles=pos.get("progress_miles"),
                miles_remaining=pos.get("miles_remaining"),
            )
        )

    # FIXED: Section C - Add vehicles without crossings at the end
    start_position = len(entries) + 1
    for i, vid in enumerate(vehicles_without_crossings):
        vehicle = all_vehicles[vid]
        # PROGRESS-1: Get progress from cached position (vehicle may have GPS but no checkpoint)
        pos = latest_positions.get(vid, {})
        entries.append(
            LeaderboardEntry(
                position=start_position + i,
                vehicle_id=vid,
                vehicle_number=vehicle.vehicle_number,
                team_name=vehicle.team_name,
                driver_name=vehicle.driver_name,
                last_checkpoint=0,  # No checkpoint crossed yet
                last_checkpoint_name="Not Started",
                delta_to_leader_ms=0,
                delta_formatted="—",  # Em dash for "no data"
                progress_miles=pos.get("progress_miles"),
                miles_remaining=pos.get("miles_remaining"),
            )
        )

    return LeaderboardResponse(
        event_id=event_id,
        ts=datetime.utcnow(),
        entries=entries,
        course_length_miles=course_length_miles,
    )


async def calculate_splits(
    db: AsyncSession,
    event_id: str,
) -> SplitsResponse:
    """
    Calculate split times at each checkpoint.
    Shows time deltas from leader at each checkpoint.
    """
    # Get checkpoints ordered by number
    result = await db.execute(
        select(Checkpoint)
        .where(Checkpoint.event_id == event_id)
        .order_by(Checkpoint.checkpoint_number)
    )
    checkpoints = result.scalars().all()

    # Get all crossings
    result = await db.execute(
        select(CheckpointCrossing)
        .where(CheckpointCrossing.event_id == event_id)
        .order_by(CheckpointCrossing.ts_ms)
    )
    all_crossings = result.scalars().all()

    # Group crossings by checkpoint
    crossings_by_cp: dict[str, list[CheckpointCrossing]] = {}
    for crossing in all_crossings:
        cp_id = crossing.checkpoint_id
        if cp_id not in crossings_by_cp:
            crossings_by_cp[cp_id] = []
        crossings_by_cp[cp_id].append(crossing)

    # Get vehicle info
    vehicle_ids = list({c.vehicle_id for c in all_crossings})
    if vehicle_ids:
        result = await db.execute(
            select(Vehicle).where(Vehicle.vehicle_id.in_(vehicle_ids))
        )
        vehicles = {v.vehicle_id: v for v in result.scalars().all()}
    else:
        vehicles = {}

    # Build splits response
    checkpoint_splits = []
    for checkpoint in checkpoints:
        crossings = crossings_by_cp.get(checkpoint.checkpoint_id, [])
        if not crossings:
            continue

        # Sort by time (leader first)
        crossings.sort(key=lambda c: c.ts_ms)
        leader_time = crossings[0].ts_ms

        split_crossings = []
        for crossing in crossings:
            vehicle = vehicles.get(crossing.vehicle_id)
            if not vehicle:
                continue

            delta_ms = crossing.ts_ms - leader_time
            split_crossings.append(
                SplitCrossing(
                    vehicle_id=crossing.vehicle_id,
                    vehicle_number=vehicle.vehicle_number,
                    team_name=vehicle.team_name,
                    ts_ms=crossing.ts_ms,
                    delta_to_leader_ms=delta_ms,
                    delta_formatted=format_time_delta(delta_ms),
                )
            )

        checkpoint_splits.append(
            CheckpointSplit(
                checkpoint_number=checkpoint.checkpoint_number,
                name=checkpoint.name,
                crossings=split_crossings,
            )
        )

    return SplitsResponse(event_id=event_id, checkpoints=checkpoint_splits)
