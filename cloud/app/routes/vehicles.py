"""
Vehicle management API routes.

Includes bulk import endpoint for CSV files.

SECURITY FIX: Added auth guards to prevent token leakage.
- POST /vehicles: Requires ORGANIZER role
- POST /vehicles/events/{event_id}/bulk: Requires ORGANIZER role
- GET /vehicles/events/{event_id}/export: Requires ADMIN for include_tokens=true
"""
import csv
import io
import secrets
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Form
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_session
from app.models import Vehicle, Event, EventVehicle, generate_id
from app.schemas import VehicleCreate, VehicleResponse, VehicleWithToken, EventVehicleRegister
from app import redis_client
from app.services.auth import AuthInfo, Role, require_role, require_admin, require_organizer

router = APIRouter(prefix="/api/v1/vehicles", tags=["vehicles"])


# ============================================
# Schemas for Bulk Import
# ============================================

class BulkImportResult(BaseModel):
    """Result of bulk vehicle import."""
    added: int
    skipped: int
    errors: list[str]
    vehicles: list[dict]  # List of added vehicles with their tokens


class VehicleImportRow(BaseModel):
    """Single row from CSV import."""
    number: str
    class_name: Optional[str] = None
    team_name: Optional[str] = None
    driver_name: Optional[str] = None


# ============================================
# Standard Vehicle Endpoints
# ============================================

@router.post("", response_model=VehicleWithToken, status_code=201)
async def create_vehicle(
    vehicle_data: VehicleCreate,
    db: AsyncSession = Depends(get_session),
    auth: AuthInfo = Depends(require_organizer),
):
    """
    Register a new vehicle.
    Returns the truck_token which must be stored securely on the edge device.

    SECURITY: Requires ORGANIZER role to prevent unauthorized vehicle creation.
    """
    vehicle = Vehicle(
        vehicle_id=generate_id("veh"),
        vehicle_number=vehicle_data.vehicle_number,
        vehicle_class=vehicle_data.vehicle_class,
        team_name=vehicle_data.team_name,
        driver_name=vehicle_data.driver_name,
        youtube_url=vehicle_data.youtube_url,
    )
    db.add(vehicle)
    await db.commit()
    await db.refresh(vehicle)
    return vehicle


@router.get("", response_model=list[VehicleResponse])
async def list_vehicles(
    team_name: Optional[str] = None,
    db: AsyncSession = Depends(get_session),
):
    """List all vehicles, optionally filtered by team."""
    query = select(Vehicle).order_by(Vehicle.vehicle_number)
    if team_name:
        query = query.where(Vehicle.team_name.ilike(f"%{team_name}%"))
    result = await db.execute(query)
    return result.scalars().all()


@router.get("/{vehicle_id}", response_model=VehicleResponse)
async def get_vehicle(
    vehicle_id: str,
    db: AsyncSession = Depends(get_session),
):
    """Get vehicle details."""
    result = await db.execute(select(Vehicle).where(Vehicle.vehicle_id == vehicle_id))
    vehicle = result.scalar_one_or_none()
    if not vehicle:
        raise HTTPException(status_code=404, detail="Vehicle not found")
    return vehicle


@router.post("/{vehicle_id}/events/{event_id}/register", status_code=201)
async def register_for_event(
    vehicle_id: str,
    event_id: str,
    db: AsyncSession = Depends(get_session),
):
    """Register a vehicle for an event."""
    # Validate vehicle exists
    result = await db.execute(select(Vehicle).where(Vehicle.vehicle_id == vehicle_id))
    vehicle = result.scalar_one_or_none()
    if not vehicle:
        raise HTTPException(status_code=404, detail="Vehicle not found")

    # Validate event exists
    result = await db.execute(select(Event).where(Event.event_id == event_id))
    event = result.scalar_one_or_none()
    if not event:
        raise HTTPException(status_code=404, detail="Event not found")

    # Check if already registered
    result = await db.execute(
        select(EventVehicle).where(
            EventVehicle.event_id == event_id,
            EventVehicle.vehicle_id == vehicle_id,
        )
    )
    if result.scalar_one_or_none():
        raise HTTPException(status_code=400, detail="Vehicle already registered for event")

    # Create registration
    registration = EventVehicle(
        event_id=event_id,
        vehicle_id=vehicle_id,
    )
    db.add(registration)
    await db.commit()

    # Cache truck token for fast lookup
    await redis_client.cache_truck_token(vehicle.truck_token, vehicle_id, event_id)

    return {
        "vehicle_id": vehicle_id,
        "event_id": event_id,
        "status": "registered",
    }


@router.put("/{vehicle_id}/visibility")
async def set_visibility(
    vehicle_id: str,
    event_id: str,
    visible: bool,
    db: AsyncSession = Depends(get_session),
):
    """
    Toggle vehicle visibility for fans.
    Hidden vehicles are not shown on map or leaderboard.
    """
    # Validate registration exists
    result = await db.execute(
        select(EventVehicle).where(
            EventVehicle.event_id == event_id,
            EventVehicle.vehicle_id == vehicle_id,
        )
    )
    registration = result.scalar_one_or_none()
    if not registration:
        raise HTTPException(status_code=404, detail="Vehicle not registered for event")

    # Update visibility
    registration.visible = visible
    await db.commit()

    # Update cache
    await redis_client.set_vehicle_visibility(event_id, vehicle_id, visible)

    # Broadcast permission change to fans
    await redis_client.publish_event(
        event_id,
        "permission",
        {"vehicle_id": vehicle_id, "visible": visible},
    )

    return {"vehicle_id": vehicle_id, "event_id": event_id, "visible": visible}


# ============================================
# Bulk Import Endpoint
# ============================================

@router.post("/events/{event_id}/bulk", response_model=BulkImportResult)
async def bulk_import_vehicles(
    event_id: str,
    file: UploadFile = File(...),
    auto_register: bool = Form(default=True),
    db: AsyncSession = Depends(get_session),
    auth: AuthInfo = Depends(require_organizer),
):
    """
    Bulk import vehicles from a CSV file.

    SECURITY: Requires ORGANIZER role - returns truck_tokens for created vehicles.

    CSV Format (first row is header):
    ```
    number,class_name,team_name,driver_name
    42,Trophy Truck,Red Bull Racing,John Smith
    7,4400,Desert Demons,Jane Doe
    ```

    Required columns:
    - number: Vehicle number (required, must be unique per event)

    Optional columns:
    - class_name: Vehicle class (e.g., "Trophy Truck", "4400")
    - team_name: Team name
    - driver_name: Driver name

    Parameters:
    - auto_register: If true, automatically register vehicles for the event (default: true)

    Returns:
    - added: Number of vehicles successfully added
    - skipped: Number of vehicles skipped (duplicates)
    - errors: List of error messages for failed rows
    - vehicles: List of added vehicles with their auth tokens
    """
    # Validate event exists
    result = await db.execute(select(Event).where(Event.event_id == event_id))
    event = result.scalar_one_or_none()
    if not event:
        raise HTTPException(status_code=404, detail="Event not found")

    # Validate file type
    if not file.filename:
        raise HTTPException(status_code=400, detail="No filename provided")

    if not file.filename.lower().endswith('.csv'):
        raise HTTPException(
            status_code=400,
            detail="Invalid file type. Please upload a CSV file."
        )

    # Read file content
    try:
        content = await file.read()
        text_content = content.decode('utf-8-sig')  # Handle BOM if present
    except UnicodeDecodeError:
        # Try latin-1 encoding as fallback
        try:
            text_content = content.decode('latin-1')
        except Exception:
            raise HTTPException(
                status_code=400,
                detail="Unable to decode CSV file. Please ensure it's UTF-8 encoded."
            )

    # Parse CSV
    reader = csv.DictReader(io.StringIO(text_content))

    # Validate required columns
    if not reader.fieldnames:
        raise HTTPException(status_code=400, detail="CSV file appears to be empty")

    # Normalize column names (lowercase, strip whitespace)
    fieldnames_lower = [f.lower().strip() for f in reader.fieldnames]

    if 'number' not in fieldnames_lower:
        raise HTTPException(
            status_code=400,
            detail=f"CSV must contain a 'number' column. Found columns: {reader.fieldnames}"
        )

    # Get existing vehicle numbers for this event
    result = await db.execute(
        select(Vehicle.vehicle_number)
        .join(EventVehicle, Vehicle.vehicle_id == EventVehicle.vehicle_id)
        .where(EventVehicle.event_id == event_id)
    )
    existing_numbers = {row[0] for row in result.fetchall()}

    # Also get all vehicle numbers in the system to check global duplicates
    result = await db.execute(select(Vehicle.vehicle_number))
    all_vehicle_numbers = {row[0] for row in result.fetchall()}

    # Process rows
    added = 0
    skipped = 0
    errors: list[str] = []
    added_vehicles: list[dict] = []

    for row_num, row in enumerate(reader, start=2):  # Start at 2 (after header)
        try:
            # Normalize keys
            row_normalized = {k.lower().strip(): v.strip() if v else None for k, v in row.items()}

            # Extract fields
            vehicle_number = row_normalized.get('number', '').strip()

            if not vehicle_number:
                errors.append(f"Row {row_num}: Missing vehicle number")
                continue

            # Check if already registered for this event
            if vehicle_number in existing_numbers:
                skipped += 1
                continue

            # Get optional fields
            class_name = row_normalized.get('class_name') or row_normalized.get('class') or None
            team_name = row_normalized.get('team_name') or row_normalized.get('team') or f"Team {vehicle_number}"
            driver_name = row_normalized.get('driver_name') or row_normalized.get('driver') or None

            # Check if vehicle exists globally (same number for different team)
            if vehicle_number in all_vehicle_numbers:
                # Find existing vehicle and register for this event
                result = await db.execute(
                    select(Vehicle).where(Vehicle.vehicle_number == vehicle_number)
                )
                existing_vehicle = result.scalar_one_or_none()

                if existing_vehicle and auto_register:
                    # Check if already registered
                    result = await db.execute(
                        select(EventVehicle).where(
                            EventVehicle.event_id == event_id,
                            EventVehicle.vehicle_id == existing_vehicle.vehicle_id,
                        )
                    )
                    if not result.scalar_one_or_none():
                        # Register for event
                        registration = EventVehicle(
                            event_id=event_id,
                            vehicle_id=existing_vehicle.vehicle_id,
                        )
                        db.add(registration)
                        existing_numbers.add(vehicle_number)

                        added_vehicles.append({
                            "vehicle_id": existing_vehicle.vehicle_id,
                            "vehicle_number": vehicle_number,
                            "team_name": existing_vehicle.team_name,
                            "truck_token": existing_vehicle.truck_token,
                            "status": "registered_existing",
                        })
                        added += 1
                    else:
                        skipped += 1
                else:
                    skipped += 1
                continue

            # Create new vehicle
            truck_token = secrets.token_urlsafe(32)
            vehicle = Vehicle(
                vehicle_id=generate_id("veh"),
                vehicle_number=vehicle_number,
                vehicle_class=class_name,
                team_name=team_name,
                driver_name=driver_name,
                truck_token=truck_token,
            )
            db.add(vehicle)

            # Auto-register for event if requested
            if auto_register:
                await db.flush()  # Get vehicle_id
                registration = EventVehicle(
                    event_id=event_id,
                    vehicle_id=vehicle.vehicle_id,
                )
                db.add(registration)

            # Track for result
            all_vehicle_numbers.add(vehicle_number)
            existing_numbers.add(vehicle_number)

            added_vehicles.append({
                "vehicle_id": vehicle.vehicle_id,
                "vehicle_number": vehicle_number,
                "team_name": team_name,
                "driver_name": driver_name,
                "class_name": class_name,
                "truck_token": truck_token,
                "status": "created",
            })
            added += 1

        except Exception as e:
            errors.append(f"Row {row_num}: {str(e)}")

    # Commit all changes
    await db.commit()

    # Cache truck tokens for registered vehicles
    for v in added_vehicles:
        try:
            await redis_client.cache_truck_token(
                v["truck_token"],
                v["vehicle_id"],
                event_id
            )
        except Exception:
            pass  # Non-critical, continue

    return BulkImportResult(
        added=added,
        skipped=skipped,
        errors=errors,
        vehicles=added_vehicles,
    )


@router.get("/events/{event_id}/export")
async def export_vehicles_csv(
    event_id: str,
    include_tokens: bool = False,
    db: AsyncSession = Depends(get_session),
    auth: AuthInfo = Depends(require_organizer),
):
    """
    Export all vehicles for an event as CSV.

    SECURITY: Requires ORGANIZER role. ADMIN required for include_tokens=true.

    Parameters:
    - include_tokens: If true, include truck_token column (admin only)

    Returns CSV file download.
    """
    from fastapi.responses import StreamingResponse

    # SECURITY: Only admins can export tokens
    if include_tokens and auth.role < Role.ADMIN:
        raise HTTPException(
            status_code=403,
            detail="Admin role required to export truck tokens"
        )

    # Get all vehicles for event
    result = await db.execute(
        select(Vehicle)
        .join(EventVehicle, Vehicle.vehicle_id == EventVehicle.vehicle_id)
        .where(EventVehicle.event_id == event_id)
        .order_by(Vehicle.vehicle_number)
    )
    vehicles = result.scalars().all()

    # Build CSV
    output = io.StringIO()

    if include_tokens:
        fieldnames = ['number', 'class_name', 'team_name', 'driver_name', 'truck_token']
    else:
        fieldnames = ['number', 'class_name', 'team_name', 'driver_name']

    writer = csv.DictWriter(output, fieldnames=fieldnames)
    writer.writeheader()

    for v in vehicles:
        row = {
            'number': v.vehicle_number,
            'class_name': v.vehicle_class or '',
            'team_name': v.team_name or '',
            'driver_name': v.driver_name or '',
        }
        if include_tokens:
            row['truck_token'] = v.truck_token
        writer.writerow(row)

    output.seek(0)

    return StreamingResponse(
        iter([output.getvalue()]),
        media_type="text/csv",
        headers={
            "Content-Disposition": f"attachment; filename=vehicles_{event_id}.csv"
        }
    )
