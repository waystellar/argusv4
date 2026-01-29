"""
GPX file parsing for course and checkpoint extraction.

FIXED: Now properly extracts waypoints (<wpt>) as timing gates/checkpoints.
Supports both GPX 1.1 waypoints and route points.
"""
from typing import Optional, TypedDict
import gpxpy
import gpxpy.gpx

from app.services.geo import haversine_distance


class CheckpointData(TypedDict):
    """Checkpoint data ready for DB insertion."""
    checkpoint_number: int
    name: str
    lat: float
    lon: float
    elevation_m: Optional[float]
    radius_m: float
    checkpoint_type: str  # 'start', 'finish', 'timing', 'waypoint'
    description: Optional[str]


class ParsedCourse(TypedDict):
    """Complete parsed course data."""
    geojson: dict
    checkpoints: list[CheckpointData]
    total_distance_m: float
    course_cumulative_m: list[float]  # PROGRESS-1: cumulative distance at each polyline point
    bounds: dict
    point_count: int
    waypoint_count: int


def parse_gpx(gpx_content: str) -> ParsedCourse:
    """
    Parse GPX file and extract:
    - Track points as GeoJSON LineString
    - Waypoints (<wpt>) as timing checkpoints
    - Route points (<rtept>) as additional waypoints
    - Total distance
    - Bounds

    Returns a structured object ready for database insertion.

    GPX Waypoint attributes used:
    - name: Checkpoint display name
    - lat/lon: Position
    - ele: Elevation in meters
    - desc: Description
    - type: Checkpoint type (start, finish, timing)
    - sym: Symbol (can indicate checkpoint type)
    """
    gpx = gpxpy.parse(gpx_content)

    # Extract track points
    all_points = []
    for track in gpx.tracks:
        for segment in track.segments:
            for point in segment.points:
                all_points.append({
                    "lat": point.latitude,
                    "lon": point.longitude,
                    "ele": point.elevation,
                })

    # Also check routes if no tracks (some GPX files use routes instead)
    if not all_points:
        for route in gpx.routes:
            for point in route.points:
                all_points.append({
                    "lat": point.latitude,
                    "lon": point.longitude,
                    "ele": point.elevation,
                })

    # Calculate total distance and cumulative distances (PROGRESS-1)
    total_distance_m = 0.0
    course_cumulative_m: list[float] = [0.0] if all_points else []
    for i in range(1, len(all_points)):
        total_distance_m += haversine_distance(
            all_points[i - 1]["lat"],
            all_points[i - 1]["lon"],
            all_points[i]["lat"],
            all_points[i]["lon"],
        )
        course_cumulative_m.append(total_distance_m)

    # Build GeoJSON LineString
    coordinates = [[p["lon"], p["lat"]] for p in all_points]

    # Get course name from track or route
    course_name = "Course"
    if gpx.tracks and gpx.tracks[0].name:
        course_name = gpx.tracks[0].name
    elif gpx.routes and gpx.routes[0].name:
        course_name = gpx.routes[0].name
    elif gpx.name:
        course_name = gpx.name

    # Build GeoJSON FeatureCollection (required by frontend Map component)
    # PROGRESS-1: Store cumulative distances in properties for progress computation
    geojson = {
        "type": "FeatureCollection",
        "features": [
            {
                "type": "Feature",
                "geometry": {
                    "type": "LineString",
                    "coordinates": coordinates,
                } if coordinates else {
                    "type": "Point",
                    "coordinates": [0, 0],
                },
                "properties": {
                    "name": course_name,
                    "distance_m": total_distance_m,
                    "cumulative_m": course_cumulative_m,
                },
            }
        ],
    }

    # Extract waypoints as checkpoints
    checkpoints: list[CheckpointData] = []

    # Process GPX waypoints (<wpt> elements) - these are the timing gates
    for i, waypoint in enumerate(gpx.waypoints, start=1):
        # Determine checkpoint type from name, type field, or symbol
        checkpoint_type = _determine_checkpoint_type(
            waypoint.name or "",
            getattr(waypoint, 'type', None),
            getattr(waypoint, 'symbol', None),
            i,
            len(gpx.waypoints)
        )

        # Extract description if available
        description = None
        if hasattr(waypoint, 'description') and waypoint.description:
            description = waypoint.description
        elif hasattr(waypoint, 'comment') and waypoint.comment:
            description = waypoint.comment

        checkpoints.append({
            "checkpoint_number": i,
            "name": waypoint.name or f"Checkpoint {i}",
            "lat": waypoint.latitude,
            "lon": waypoint.longitude,
            "elevation_m": waypoint.elevation,
            "radius_m": _get_checkpoint_radius(checkpoint_type),
            "checkpoint_type": checkpoint_type,
            "description": description,
        })

    # If no waypoints found, try to extract from route points with special names
    if not checkpoints:
        for route in gpx.routes:
            for i, point in enumerate(route.points, start=1):
                # Only add route points that look like checkpoints (have names)
                if point.name:
                    checkpoint_type = _determine_checkpoint_type(
                        point.name,
                        getattr(point, 'type', None),
                        None,
                        i,
                        len(route.points)
                    )
                    checkpoints.append({
                        "checkpoint_number": len(checkpoints) + 1,
                        "name": point.name,
                        "lat": point.latitude,
                        "lon": point.longitude,
                        "elevation_m": point.elevation,
                        "radius_m": _get_checkpoint_radius(checkpoint_type),
                        "checkpoint_type": checkpoint_type,
                        "description": getattr(point, 'description', None),
                    })

    # If still no checkpoints, create start/finish from track endpoints
    if not checkpoints and all_points:
        checkpoints = [
            {
                "checkpoint_number": 1,
                "name": "Start",
                "lat": all_points[0]["lat"],
                "lon": all_points[0]["lon"],
                "elevation_m": all_points[0].get("ele"),
                "radius_m": 100.0,  # Wider radius for auto-generated start/finish
                "checkpoint_type": "start",
                "description": "Auto-generated start point",
            },
            {
                "checkpoint_number": 2,
                "name": "Finish",
                "lat": all_points[-1]["lat"],
                "lon": all_points[-1]["lon"],
                "elevation_m": all_points[-1].get("ele"),
                "radius_m": 100.0,
                "checkpoint_type": "finish",
                "description": "Auto-generated finish point",
            },
        ]

    # Calculate bounds
    all_lats = [p["lat"] for p in all_points]
    all_lons = [p["lon"] for p in all_points]

    # Include checkpoint positions in bounds
    for cp in checkpoints:
        all_lats.append(cp["lat"])
        all_lons.append(cp["lon"])

    if all_lats and all_lons:
        bounds = {
            "north": max(all_lats),
            "south": min(all_lats),
            "east": max(all_lons),
            "west": min(all_lons),
        }
    else:
        bounds = {"north": 0, "south": 0, "east": 0, "west": 0}

    return {
        "geojson": geojson,
        "checkpoints": checkpoints,
        "total_distance_m": total_distance_m,
        "course_cumulative_m": course_cumulative_m,
        "bounds": bounds,
        "point_count": len(all_points),
        "waypoint_count": len(checkpoints),
    }


def _determine_checkpoint_type(
    name: str,
    type_field: Optional[str],
    symbol: Optional[str],
    index: int,
    total: int
) -> str:
    """
    Determine checkpoint type from various GPX fields.

    Priority:
    1. Explicit type field
    2. Name pattern matching
    3. Symbol matching
    4. Position-based inference (first=start, last=finish)
    """
    name_lower = name.lower()
    type_lower = (type_field or "").lower()
    symbol_lower = (symbol or "").lower()

    # Check explicit type field
    if type_lower in ('start', 'finish', 'timing', 'checkpoint'):
        return type_lower

    # Check name patterns
    if any(x in name_lower for x in ('start', 'begin', 'green flag')):
        return 'start'
    if any(x in name_lower for x in ('finish', 'end', 'checkered', 'final')):
        return 'finish'
    if any(x in name_lower for x in ('pit', 'service', 'fuel')):
        return 'pit'
    if any(x in name_lower for x in ('timing', 'checkpoint', 'cp', 'split', 'sector')):
        return 'timing'

    # Check symbol
    if 'start' in symbol_lower or 'flag' in symbol_lower:
        return 'start'
    if 'finish' in symbol_lower or 'checkered' in symbol_lower:
        return 'finish'

    # Position-based inference
    if index == 1:
        return 'start'
    if index == total:
        return 'finish'

    return 'timing'


def _get_checkpoint_radius(checkpoint_type: str) -> float:
    """
    Get default radius in meters based on checkpoint type.

    Start/finish lines are wider to ensure capture.
    Timing checkpoints are tighter for accuracy.
    """
    radii = {
        'start': 100.0,
        'finish': 100.0,
        'pit': 150.0,
        'timing': 50.0,
        'waypoint': 75.0,
    }
    return radii.get(checkpoint_type, 50.0)


def parse_kml(kml_content: str) -> ParsedCourse:
    """
    Parse KML file and convert to same format as GPX.

    KML placemarks with Point geometry become checkpoints.
    KML placemarks with LineString geometry become the course track.
    """
    import xml.etree.ElementTree as ET

    # KML namespace
    ns = {'kml': 'http://www.opengis.net/kml/2.2'}

    # Try parsing with and without namespace
    root = ET.fromstring(kml_content)

    # Find all placemarks (try with and without namespace)
    placemarks = root.findall('.//kml:Placemark', ns)
    if not placemarks:
        placemarks = root.findall('.//{http://www.opengis.net/kml/2.2}Placemark')
    if not placemarks:
        placemarks = root.findall('.//Placemark')

    all_points: list[dict] = []
    checkpoints: list[CheckpointData] = []

    for placemark in placemarks:
        # Get name
        name_elem = placemark.find('kml:name', ns) or placemark.find('{http://www.opengis.net/kml/2.2}name') or placemark.find('name')
        name = name_elem.text if name_elem is not None and name_elem.text else "Unnamed"

        # Get description
        desc_elem = placemark.find('kml:description', ns) or placemark.find('{http://www.opengis.net/kml/2.2}description') or placemark.find('description')
        description = desc_elem.text if desc_elem is not None else None

        # Check for Point geometry (checkpoint)
        point_elem = placemark.find('.//kml:Point/kml:coordinates', ns) or \
                     placemark.find('.//{http://www.opengis.net/kml/2.2}Point/{http://www.opengis.net/kml/2.2}coordinates') or \
                     placemark.find('.//Point/coordinates')

        if point_elem is not None and point_elem.text:
            coords = point_elem.text.strip().split(',')
            if len(coords) >= 2:
                lon, lat = float(coords[0]), float(coords[1])
                ele = float(coords[2]) if len(coords) > 2 else None

                # Determine checkpoint type
                checkpoint_type = _determine_checkpoint_type(
                    name, None, None, len(checkpoints) + 1, 0  # Total unknown at this point
                )

                checkpoints.append({
                    "checkpoint_number": len(checkpoints) + 1,
                    "name": name,
                    "lat": lat,
                    "lon": lon,
                    "elevation_m": ele,
                    "radius_m": _get_checkpoint_radius(checkpoint_type),
                    "checkpoint_type": checkpoint_type,
                    "description": description,
                })

        # Check for LineString geometry (course track)
        linestring_elem = placemark.find('.//kml:LineString/kml:coordinates', ns) or \
                         placemark.find('.//{http://www.opengis.net/kml/2.2}LineString/{http://www.opengis.net/kml/2.2}coordinates') or \
                         placemark.find('.//LineString/coordinates')

        if linestring_elem is not None and linestring_elem.text:
            coord_pairs = linestring_elem.text.strip().split()
            for pair in coord_pairs:
                coords = pair.strip().split(',')
                if len(coords) >= 2:
                    lon, lat = float(coords[0]), float(coords[1])
                    ele = float(coords[2]) if len(coords) > 2 else None
                    all_points.append({"lat": lat, "lon": lon, "ele": ele})

    # Update checkpoint types now that we know the total
    for i, cp in enumerate(checkpoints):
        cp["checkpoint_type"] = _determine_checkpoint_type(
            cp["name"], None, None, i + 1, len(checkpoints)
        )
        cp["radius_m"] = _get_checkpoint_radius(cp["checkpoint_type"])

    # Calculate total distance and cumulative distances (PROGRESS-1)
    total_distance_m = 0.0
    course_cumulative_m: list[float] = [0.0] if all_points else []
    for i in range(1, len(all_points)):
        total_distance_m += haversine_distance(
            all_points[i - 1]["lat"],
            all_points[i - 1]["lon"],
            all_points[i]["lat"],
            all_points[i]["lon"],
        )
        course_cumulative_m.append(total_distance_m)

    # Build GeoJSON FeatureCollection (required by frontend Map component)
    # PROGRESS-1: Store cumulative distances in properties for progress computation
    coordinates = [[p["lon"], p["lat"]] for p in all_points]
    geojson = {
        "type": "FeatureCollection",
        "features": [
            {
                "type": "Feature",
                "geometry": {
                    "type": "LineString",
                    "coordinates": coordinates,
                } if coordinates else {
                    "type": "Point",
                    "coordinates": [0, 0],
                },
                "properties": {
                    "name": "Course",
                    "distance_m": total_distance_m,
                    "cumulative_m": course_cumulative_m,
                },
            }
        ],
    }

    # If no checkpoints found but we have track points, create start/finish
    if not checkpoints and all_points:
        checkpoints = [
            {
                "checkpoint_number": 1,
                "name": "Start",
                "lat": all_points[0]["lat"],
                "lon": all_points[0]["lon"],
                "elevation_m": all_points[0].get("ele"),
                "radius_m": 100.0,
                "checkpoint_type": "start",
                "description": "Auto-generated start point",
            },
            {
                "checkpoint_number": 2,
                "name": "Finish",
                "lat": all_points[-1]["lat"],
                "lon": all_points[-1]["lon"],
                "elevation_m": all_points[-1].get("ele"),
                "radius_m": 100.0,
                "checkpoint_type": "finish",
                "description": "Auto-generated finish point",
            },
        ]

    # Calculate bounds
    all_lats = [p["lat"] for p in all_points]
    all_lons = [p["lon"] for p in all_points]
    for cp in checkpoints:
        all_lats.append(cp["lat"])
        all_lons.append(cp["lon"])

    if all_lats and all_lons:
        bounds = {
            "north": max(all_lats),
            "south": min(all_lats),
            "east": max(all_lons),
            "west": min(all_lons),
        }
    else:
        bounds = {"north": 0, "south": 0, "east": 0, "west": 0}

    return {
        "geojson": geojson,
        "checkpoints": checkpoints,
        "total_distance_m": total_distance_m,
        "course_cumulative_m": course_cumulative_m,
        "bounds": bounds,
        "point_count": len(all_points),
        "waypoint_count": len(checkpoints),
    }
