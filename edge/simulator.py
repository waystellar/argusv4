#!/usr/bin/env python3
"""
Argus Edge Simulator - Generates realistic GPS telemetry for multiple vehicles.

Usage:
    python simulator.py --api-url http://localhost:8000 --vehicles 5 --event-id evt_xxx
"""
import argparse
import asyncio
import json
import math
import random
import time
from dataclasses import dataclass
from typing import Optional

import httpx


@dataclass
class VehicleState:
    """Current state of a simulated vehicle."""
    vehicle_id: str
    truck_token: str
    vehicle_number: str
    lat: float
    lon: float
    speed_mps: float  # meters per second
    heading_deg: float
    progress: float  # 0.0 to 1.0 along course
    last_ts_ms: int


class CourseSimulator:
    """
    Simulates vehicles moving along a race course.
    Generates noisy GPS data with realistic movement patterns.
    """

    def __init__(
        self,
        api_url: str,
        event_id: str,
        course_points: list[tuple[float, float]],
        hz: int = 5,
        load_test: bool = False,
    ):
        self.api_url = api_url.rstrip("/")
        self.event_id = event_id
        self.course_points = course_points
        self.hz = hz
        self.load_test = load_test
        self.vehicles: list[VehicleState] = []
        self.client = httpx.AsyncClient(timeout=30.0)

        # Load test metrics
        self.total_requests = 0
        self.successful_requests = 0
        self.failed_requests = 0
        self.rate_limited_requests = 0
        self.total_points_sent = 0
        self.total_latency_ms = 0
        self.max_latency_ms = 0
        self.min_latency_ms = float('inf')

    def add_vehicle(self, vehicle_id: str, truck_token: str, vehicle_number: str):
        """Add a vehicle to the simulation."""
        # Start at beginning of course with random offset
        start_progress = random.uniform(0.0, 0.05)
        lat, lon = self._interpolate_position(start_progress)

        vehicle = VehicleState(
            vehicle_id=vehicle_id,
            truck_token=truck_token,
            vehicle_number=vehicle_number,
            lat=lat,
            lon=lon,
            speed_mps=random.uniform(15, 25),  # 35-55 mph starting speed
            heading_deg=0.0,
            progress=start_progress,
            last_ts_ms=int(time.time() * 1000),
        )
        self.vehicles.append(vehicle)
        print(f"Added vehicle {vehicle_number} (ID: {vehicle_id})")

    def _interpolate_position(self, progress: float) -> tuple[float, float]:
        """Get lat/lon at given progress (0.0 to 1.0) along course."""
        if not self.course_points:
            return 34.1, -116.4  # Default location

        # Clamp progress
        progress = max(0.0, min(1.0, progress))

        # Find segment
        total_segments = len(self.course_points) - 1
        segment_progress = progress * total_segments
        segment_idx = int(segment_progress)
        segment_frac = segment_progress - segment_idx

        if segment_idx >= total_segments:
            return self.course_points[-1]

        # Interpolate between points
        p1 = self.course_points[segment_idx]
        p2 = self.course_points[segment_idx + 1]

        lat = p1[0] + (p2[0] - p1[0]) * segment_frac
        lon = p1[1] + (p2[1] - p1[1]) * segment_frac

        return lat, lon

    def _add_gps_noise(self, lat: float, lon: float) -> tuple[float, float]:
        """Add realistic GPS noise (±5m accuracy)."""
        # ~5m in degrees at mid-latitudes
        noise_lat = random.gauss(0, 0.00005)
        noise_lon = random.gauss(0, 0.00005)
        return lat + noise_lat, lon + noise_lon

    def _calculate_heading(
        self, lat1: float, lon1: float, lat2: float, lon2: float
    ) -> float:
        """Calculate heading in degrees from point 1 to point 2."""
        dlat = lat2 - lat1
        dlon = lon2 - lon1
        heading = math.degrees(math.atan2(dlon, dlat))
        return (heading + 360) % 360

    async def update_vehicle(self, vehicle: VehicleState) -> list[dict]:
        """
        Update vehicle position and generate GPS points.
        Returns list of position points for the batch.
        """
        now_ms = int(time.time() * 1000)
        dt_s = (now_ms - vehicle.last_ts_ms) / 1000.0

        if dt_s <= 0:
            dt_s = 1.0 / self.hz

        points = []

        # Generate points at specified Hz
        num_points = max(1, int(dt_s * self.hz))
        time_step_ms = int((now_ms - vehicle.last_ts_ms) / num_points)

        for i in range(num_points):
            # Vary speed randomly (simulating terrain/racing)
            speed_change = random.gauss(0, 2)  # ±2 m/s variance
            vehicle.speed_mps = max(5, min(45, vehicle.speed_mps + speed_change))

            # Calculate distance traveled
            distance_m = vehicle.speed_mps * (time_step_ms / 1000.0)

            # Estimate course length (rough, ~50km)
            course_length_m = 50000
            progress_delta = distance_m / course_length_m

            # Update progress (loop back to start if finished)
            vehicle.progress += progress_delta
            if vehicle.progress > 1.0:
                vehicle.progress = 0.0

            # Get new position
            old_lat, old_lon = vehicle.lat, vehicle.lon
            new_lat, new_lon = self._interpolate_position(vehicle.progress)

            # Add GPS noise
            noisy_lat, noisy_lon = self._add_gps_noise(new_lat, new_lon)

            # Calculate heading
            if abs(new_lat - old_lat) > 0.00001 or abs(new_lon - old_lon) > 0.00001:
                vehicle.heading_deg = self._calculate_heading(
                    old_lat, old_lon, new_lat, new_lon
                )

            # Update vehicle state
            vehicle.lat = new_lat
            vehicle.lon = new_lon

            ts_ms = vehicle.last_ts_ms + (i + 1) * time_step_ms

            # PR-2 SCHEMA FIX: Use canonical field names matching cloud schema
            points.append({
                "ts_ms": ts_ms,  # Canonical: ts_ms (not ts_utc_ms)
                "lat": noisy_lat,
                "lon": noisy_lon,
                "speed_mps": vehicle.speed_mps + random.gauss(0, 0.5),
                "heading_deg": vehicle.heading_deg + random.gauss(0, 2),
                "altitude_m": 1000 + random.gauss(0, 5),
                "hdop": 1.0 + random.random(),
                "satellites": random.randint(8, 14),
            })

        vehicle.last_ts_ms = now_ms
        return points

    async def upload_batch(self, vehicle: VehicleState, points: list[dict]) -> bool:
        """Upload position batch to cloud API."""
        # PR-2 SCHEMA FIX: Use canonical endpoint and payload structure
        # Matches v3 uplink_service.py and cloud TelemetryIngestRequest schema
        url = f"{self.api_url}/api/v1/telemetry/ingest"
        payload = {
            "positions": points,
            # "telemetry": [] - Optional, simulator doesn't generate CAN data
        }
        headers = {
            "X-Truck-Token": vehicle.truck_token,
            "Content-Type": "application/json",
        }

        start_time = time.time()
        self.total_requests += 1

        try:
            response = await self.client.post(
                url,
                json=payload,
                headers=headers,
            )

            latency_ms = (time.time() - start_time) * 1000
            self.total_latency_ms += latency_ms
            self.max_latency_ms = max(self.max_latency_ms, latency_ms)
            self.min_latency_ms = min(self.min_latency_ms, latency_ms)

            if response.status_code == 200 or response.status_code == 202:
                self.successful_requests += 1
                self.total_points_sent += len(points)
                data = response.json()
                crossings = data.get("checkpoint_crossings", [])
                if crossings and not self.load_test:
                    for cp in crossings:
                        print(
                            f"  🏁 {vehicle.vehicle_number} crossed checkpoint "
                            f"{cp['checkpoint_number']}: {cp.get('checkpoint_name', '')}"
                        )
                return True
            elif response.status_code == 429:
                self.rate_limited_requests += 1
                self.failed_requests += 1
                if not self.load_test:
                    print(f"  ⚠️  Rate limited: {vehicle.vehicle_number}")
                return False
            else:
                self.failed_requests += 1
                if not self.load_test:
                    print(f"  ❌ Upload failed for {vehicle.vehicle_number}: {response.status_code}")
                return False

        except Exception as e:
            self.failed_requests += 1
            if not self.load_test:
                print(f"  ❌ Upload error for {vehicle.vehicle_number}: {e}")
            return False

    async def run_simulation(self):
        """Main simulation loop."""
        print(f"\n🏎️  Starting simulation with {len(self.vehicles)} vehicles")
        print(f"   API: {self.api_url}")
        print(f"   Event: {self.event_id}")
        print(f"   Frequency: {self.hz} Hz")
        if self.load_test:
            print(f"   Mode: LOAD TEST (metrics enabled)")
        print()

        batch_interval = 1.0  # Upload every 1 second
        metrics_interval = 5.0  # Print metrics every 5 seconds
        last_metrics_time = time.time()
        iteration = 0

        while True:
            start = time.time()
            iteration += 1

            # Upload all vehicles concurrently in load test mode
            if self.load_test:
                tasks = []
                for vehicle in self.vehicles:
                    points = await self.update_vehicle(vehicle)
                    tasks.append(self.upload_batch(vehicle, points))
                await asyncio.gather(*tasks, return_exceptions=True)
            else:
                for vehicle in self.vehicles:
                    # Generate position points
                    points = await self.update_vehicle(vehicle)

                    # Upload batch
                    success = await self.upload_batch(vehicle, points)

                    if success:
                        print(
                            f"📍 {vehicle.vehicle_number}: "
                            f"({vehicle.lat:.5f}, {vehicle.lon:.5f}) "
                            f"{vehicle.speed_mps * 2.237:.0f} mph "
                            f"({len(points)} pts)"
                        )

            # Print load test metrics
            if self.load_test and (time.time() - last_metrics_time) >= metrics_interval:
                self._print_metrics()
                last_metrics_time = time.time()

            # Wait for next batch interval
            elapsed = time.time() - start
            sleep_time = max(0, batch_interval - elapsed)
            await asyncio.sleep(sleep_time)

    def _print_metrics(self):
        """Print load test metrics."""
        avg_latency = self.total_latency_ms / max(1, self.total_requests)
        success_rate = (self.successful_requests / max(1, self.total_requests)) * 100

        print("\n" + "=" * 70)
        print("📊 LOAD TEST METRICS")
        print("=" * 70)
        print(f"   Vehicles: {len(self.vehicles)}")
        print(f"   Total Requests: {self.total_requests}")
        print(f"   Successful: {self.successful_requests} ({success_rate:.1f}%)")
        print(f"   Failed: {self.failed_requests}")
        print(f"   Rate Limited (429): {self.rate_limited_requests}")
        print(f"   Points Sent: {self.total_points_sent}")
        print(f"   Latency: avg={avg_latency:.1f}ms, min={self.min_latency_ms:.1f}ms, max={self.max_latency_ms:.1f}ms")
        print("=" * 70 + "\n")


async def setup_demo(api_url: str, num_vehicles: int) -> tuple[str, list[dict]]:
    """
    Set up demo event and vehicles.
    Returns (event_id, list of vehicle info dicts).
    """
    client = httpx.AsyncClient(timeout=30.0)

    # Create event
    print("Creating demo event...")
    response = await client.post(
        f"{api_url}/api/v1/events",
        json={
            "name": "Demo Race 2026",
            "total_laps": 1,
        },
    )
    response.raise_for_status()
    event = response.json()
    event_id = event["event_id"]
    print(f"  Created event: {event_id}")

    # Upload sample course
    print("Uploading course GPX...")
    gpx_content = generate_sample_gpx()
    files = {"file": ("course.gpx", gpx_content, "application/gpx+xml")}
    response = await client.post(
        f"{api_url}/api/v1/events/{event_id}/course",
        files=files,
    )
    response.raise_for_status()
    course = response.json()
    print(f"  Course: {course['total_distance_m']:.0f}m, {course['checkpoint_count']} checkpoints")

    # Set event to in_progress
    await client.patch(
        f"{api_url}/api/v1/events/{event_id}/status",
        params={"status": "in_progress"},
    )

    # Create vehicles
    vehicles = []
    team_names = ["Desert Storm", "Mountain Goats", "Sand Vipers", "Rock Crawlers", "Dune Runners"]
    driver_names = ["Jake Smith", "Maria Garcia", "Tom Wilson", "Sarah Chen", "Mike Johnson"]

    print(f"Creating {num_vehicles} vehicles...")
    for i in range(num_vehicles):
        vehicle_number = str(100 + i * 10 + random.randint(0, 9))
        response = await client.post(
            f"{api_url}/api/v1/vehicles",
            json={
                "vehicle_number": vehicle_number,
                "vehicle_class": "4400",
                "team_name": team_names[i % len(team_names)],
                "driver_name": driver_names[i % len(driver_names)],
            },
        )
        response.raise_for_status()
        vehicle = response.json()
        vehicles.append(vehicle)
        print(f"  Created vehicle #{vehicle_number}: {vehicle['vehicle_id']}")

        # Register for event
        await client.post(
            f"{api_url}/api/v1/vehicles/{vehicle['vehicle_id']}/events/{event_id}/register"
        )

    await client.aclose()
    return event_id, vehicles


def generate_sample_gpx() -> str:
    """Generate a sample GPX course for testing."""
    # Simple course around a rectangle
    waypoints = [
        (34.1000, -116.4000, "Start"),
        (34.1200, -116.3700, "Checkpoint 1"),
        (34.1400, -116.3600, "Checkpoint 2"),
        (34.1500, -116.3500, "Finish"),
    ]

    # Generate track points (curved path)
    track_points = []
    for i in range(100):
        t = i / 99.0
        # Simple interpolation with some curves
        lat = 34.1000 + 0.05 * t + 0.01 * math.sin(t * math.pi * 2)
        lon = -116.4000 + 0.05 * t + 0.01 * math.cos(t * math.pi * 3)
        track_points.append((lat, lon, 1000 + 100 * t))

    gpx = '<?xml version="1.0" encoding="UTF-8"?>\n'
    gpx += '<gpx version="1.1">\n'
    gpx += '  <metadata><name>Demo Race Course</name></metadata>\n'

    # Waypoints (checkpoints)
    for lat, lon, name in waypoints:
        gpx += f'  <wpt lat="{lat}" lon="{lon}"><name>{name}</name></wpt>\n'

    # Track
    gpx += '  <trk><name>Main Course</name><trkseg>\n'
    for lat, lon, ele in track_points:
        gpx += f'    <trkpt lat="{lat}" lon="{lon}"><ele>{ele}</ele></trkpt>\n'
    gpx += '  </trkseg></trk>\n'

    gpx += '</gpx>'
    return gpx


# FIXED: Added function to fetch vehicles for existing events (Issue #10 from audit)
async def fetch_event_vehicles(api_url: str, event_id: str) -> list[dict]:
    """
    Fetch vehicles registered for an existing event.
    Returns list of vehicle info dicts with vehicle_id, truck_token, vehicle_number.
    """
    client = httpx.AsyncClient(timeout=30.0)

    try:
        # Get event details to verify it exists
        response = await client.get(f"{api_url}/api/v1/events/{event_id}")
        if response.status_code == 404:
            print(f"❌ Event {event_id} not found")
            await client.aclose()
            return []
        response.raise_for_status()

        # Get vehicles registered for this event
        # Note: This assumes an endpoint exists - we'll create a simple one
        # For now, try to get the event's vehicles list
        response = await client.get(f"{api_url}/api/v1/events/{event_id}/vehicles")
        if response.status_code == 404:
            # Fallback: try getting all vehicles and filtering
            print("  Note: Event vehicles endpoint not found, attempting to list all vehicles...")
            response = await client.get(f"{api_url}/api/v1/vehicles")
            response.raise_for_status()
            all_vehicles = response.json()

            # For simulation, we need truck_token which isn't normally exposed
            # This is a limitation - suggest using demo setup instead
            print("  ⚠️  Warning: Cannot retrieve truck tokens for existing vehicles.")
            print("     For existing events, re-run without --event-id to create a new demo,")
            print("     or manually provide vehicle credentials.")
            await client.aclose()
            return []

        response.raise_for_status()
        vehicles = response.json()

        await client.aclose()
        return vehicles

    except Exception as e:
        print(f"❌ Error fetching vehicles: {e}")
        await client.aclose()
        return []


async def main():
    parser = argparse.ArgumentParser(
        description="Argus Edge Simulator",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
EXAMPLES:
    # Basic simulation with 5 vehicles
    python simulator.py --api-url http://localhost:8000

    # Load test with 50 vehicles (Full Grid test)
    python simulator.py --vehicles 50 --load-test

    # Stress test with aggressive rate
    python simulator.py --vehicles 20 --hz 10 --load-test
        """,
    )
    parser.add_argument(
        "--api-url",
        default="http://localhost:8000",
        help="Cloud API URL",
    )
    parser.add_argument(
        "--vehicles",
        type=int,
        default=5,
        help="Number of vehicles to simulate",
    )
    parser.add_argument(
        "--event-id",
        help="Existing event ID (if not provided, creates new demo)",
    )
    parser.add_argument(
        "--hz",
        type=int,
        default=5,
        help="GPS update frequency in Hz",
    )
    parser.add_argument(
        "--load-test",
        action="store_true",
        help="Enable load test mode with detailed metrics",
    )
    args = parser.parse_args()

    # Set up or use existing event
    # FIXED: Added support for existing events (Issue #10 from audit)
    # Previously this just exited without doing anything
    if args.event_id:
        print(f"Using existing event: {args.event_id}")
        event_id = args.event_id
        # Fetch existing vehicles registered for this event
        vehicles = await fetch_event_vehicles(args.api_url, event_id)
        if not vehicles:
            print("❌ No vehicles found for event. Register vehicles first using the API.")
            print(f"   POST {args.api_url}/api/v1/vehicles")
            print(f"   POST {args.api_url}/api/v1/vehicles/{{vehicle_id}}/events/{event_id}/register")
            return
        print(f"  Found {len(vehicles)} registered vehicles")
    else:
        event_id, vehicles = await setup_demo(args.api_url, args.vehicles)

    # Create course points from sample GPX
    course_points = []
    for i in range(100):
        t = i / 99.0
        lat = 34.1000 + 0.05 * t + 0.01 * math.sin(t * math.pi * 2)
        lon = -116.4000 + 0.05 * t + 0.01 * math.cos(t * math.pi * 3)
        course_points.append((lat, lon))

    # Create simulator
    simulator = CourseSimulator(
        api_url=args.api_url,
        event_id=event_id,
        course_points=course_points,
        hz=args.hz,
        load_test=args.load_test,
    )

    # Add vehicles
    for v in vehicles:
        simulator.add_vehicle(v["vehicle_id"], v["truck_token"], v["vehicle_number"])

    # Run simulation
    print("\n" + "=" * 60)
    print("Press Ctrl+C to stop simulation")
    print("=" * 60 + "\n")

    try:
        await simulator.run_simulation()
    except KeyboardInterrupt:
        print("\n\nSimulation stopped.")


if __name__ == "__main__":
    asyncio.run(main())
