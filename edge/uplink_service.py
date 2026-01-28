#!/usr/bin/env python3
"""
Argus Uplink Service - Production-Ready Data Router

This is the central data orchestrator for the truck edge device.
It collects telemetry from all local sources via ZMQ, buffers data locally
for offline resilience, and uploads batches to the cloud API.

Architecture:
    [GPS Service]  --ZMQ:5558-->  +------------------+
    [CAN Service]  --ZMQ:5557-->  | Uplink Service   |  --HTTPS-->  [Cloud API]
    [ANT+ Service] --ZMQ:5556-->  +------------------+
                                         |
                                         v
                                  [SQLite queue.db]
                                  (offline buffer)

Features:
    - ZMQ subscriber for GPS (5558), CAN (5557), ANT+ (5556)
    - SQLite disk-backed queue for offline resilience
    - Batch uploads (1 second of data, ~10-50 records)
    - Automatic retry with exponential backoff
    - Graceful handling of Starlink connectivity drops
    - X-Truck-Token authentication

Usage:
    python uplink_service.py

Environment Variables:
    ARGUS_CLOUD_URL     - Cloud API base URL (required)
    ARGUS_TRUCK_TOKEN   - Authentication token (required)
    ARGUS_VEHICLE_NUMBER - Vehicle identifier (for logging)
    ARGUS_UPLOAD_BATCH_SIZE - Records per batch (default: 50)
    ARGUS_LOG_LEVEL     - Logging level (default: INFO)
"""
import asyncio
import json
import logging
import os
import signal
import sys
import time
from dataclasses import dataclass, field, asdict
from datetime import datetime
from pathlib import Path
from typing import Optional, List, Dict, Any

import aiosqlite
import httpx

# ZMQ for IPC
try:
    import zmq
    import zmq.asyncio
    ZMQ_AVAILABLE = True
except ImportError:
    ZMQ_AVAILABLE = False
    print("ERROR: pyzmq not installed. Run: pip install pyzmq")
    sys.exit(1)

# ============ Configuration ============

@dataclass
class UplinkConfig:
    """Configuration for the uplink service."""
    cloud_url: str = ""
    truck_token: str = ""
    vehicle_number: str = "000"

    # ZMQ ports for data sources
    zmq_gps_port: int = 5558
    zmq_can_port: int = 5557
    zmq_ant_port: int = 5556

    # Upload settings
    batch_size: int = 50
    batch_timeout_s: float = 1.0  # Upload at least every 1 second
    upload_retry_base_s: float = 1.0
    upload_retry_max_s: float = 60.0
    upload_timeout_s: float = 10.0

    # Local storage
    db_path: str = "/opt/argus/data/queue.db"
    max_queue_size: int = 100000  # Max records to buffer
    max_queue_bytes: int = 50 * 1024 * 1024  # EDGE-5: 50 MB byte-size cap

    # Logging
    log_level: str = "INFO"

    @classmethod
    def from_env(cls) -> "UplinkConfig":
        """Load configuration from environment variables."""
        return cls(
            cloud_url=os.environ.get("ARGUS_CLOUD_URL", ""),
            truck_token=os.environ.get("ARGUS_TRUCK_TOKEN", ""),
            vehicle_number=os.environ.get("ARGUS_VEHICLE_NUMBER", "000"),
            batch_size=int(os.environ.get("ARGUS_UPLOAD_BATCH_SIZE", "50")),
            db_path=os.environ.get("ARGUS_QUEUE_DB", "/opt/argus/data/queue.db"),
            log_level=os.environ.get("ARGUS_LOG_LEVEL", "INFO"),
        )


# ============ Logging Setup ============

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    handlers=[
        logging.StreamHandler(sys.stdout),
    ]
)
logger = logging.getLogger("uplink_service")


# ============ Data Models ============

@dataclass
class TelemetryRecord:
    """A single telemetry record to be uploaded."""
    ts_ms: int
    source: str  # 'gps', 'can', 'ant'
    data: Dict[str, Any]
    queued_at: float = field(default_factory=time.time)

    def to_position(self) -> Optional[Dict]:
        """Convert to position format for API if this is GPS data."""
        if self.source != "gps":
            return None
        return {
            "ts_ms": self.ts_ms,
            "lat": self.data.get("lat"),
            "lon": self.data.get("lon"),
            "speed_mps": self.data.get("speed_mps"),
            "heading_deg": self.data.get("heading_deg"),
            "altitude_m": self.data.get("altitude_m"),
            "hdop": self.data.get("hdop"),
            "satellites": self.data.get("satellites"),
        }

    def to_telemetry(self) -> Optional[Dict]:
        """Convert to telemetry format for API if this is CAN/ANT data."""
        if self.source == "gps":
            return None
        return {
            "ts_ms": self.ts_ms,
            **{k: v for k, v in self.data.items() if v is not None}
        }


# ============ SQLite Queue ============

class LocalQueue:
    """
    Disk-backed queue using SQLite for offline resilience.

    Data is immediately written to disk when received from ZMQ,
    ensuring no data loss during network outages or power failures.

    EDGE-5: Enforces both record-count and byte-size caps.
    Runs periodic VACUUM to reclaim disk after large deletions.
    """

    def __init__(self, db_path: str, max_size: int = 100000, max_bytes: int = 50 * 1024 * 1024):
        self.db_path = db_path
        self.max_size = max_size
        self.max_bytes = max_bytes  # EDGE-5: byte-size cap
        self._db: Optional[aiosqlite.Connection] = None
        self._lock = asyncio.Lock()
        self._deletes_since_vacuum: int = 0  # EDGE-5: track deletions for VACUUM
        self._vacuum_threshold: int = 5000   # VACUUM after this many deletes

    async def initialize(self):
        """Initialize the database and create tables if needed."""
        # Ensure directory exists
        Path(self.db_path).parent.mkdir(parents=True, exist_ok=True)

        self._db = await aiosqlite.connect(self.db_path)

        # Enable WAL mode for better concurrent performance
        await self._db.execute("PRAGMA journal_mode=WAL")
        await self._db.execute("PRAGMA synchronous=NORMAL")

        # Create queue table
        await self._db.execute("""
            CREATE TABLE IF NOT EXISTS telemetry_queue (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                ts_ms INTEGER NOT NULL,
                source TEXT NOT NULL,
                data TEXT NOT NULL,
                queued_at REAL NOT NULL,
                attempts INTEGER DEFAULT 0,
                created_at TEXT DEFAULT CURRENT_TIMESTAMP
            )
        """)

        # Create index for efficient FIFO retrieval
        await self._db.execute("""
            CREATE INDEX IF NOT EXISTS idx_queue_order ON telemetry_queue(id ASC)
        """)

        await self._db.commit()

        # Log queue status including byte size
        cursor = await self._db.execute("SELECT COUNT(*) FROM telemetry_queue")
        count = (await cursor.fetchone())[0]
        db_bytes = await self._get_db_size_bytes()
        logger.info(
            f"Queue initialized: {count} records, {db_bytes / 1024 / 1024:.1f} MB "
            f"(cap: {self.max_size} records / {self.max_bytes / 1024 / 1024:.0f} MB) "
            f"in {self.db_path}"
        )

    async def _get_db_size_bytes(self) -> int:
        """Get current database file size in bytes using PRAGMA."""
        try:
            cursor = await self._db.execute("PRAGMA page_count")
            page_count = (await cursor.fetchone())[0]
            cursor = await self._db.execute("PRAGMA page_size")
            page_size = (await cursor.fetchone())[0]
            return page_count * page_size
        except Exception:
            return 0

    async def _maybe_vacuum(self):
        """EDGE-5: Run VACUUM periodically to reclaim disk after large deletions."""
        if self._deletes_since_vacuum >= self._vacuum_threshold:
            try:
                await self._db.execute("PRAGMA wal_checkpoint(TRUNCATE)")
                logger.info(f"Queue WAL checkpoint after {self._deletes_since_vacuum} deletions")
                self._deletes_since_vacuum = 0
            except Exception as e:
                logger.warning(f"WAL checkpoint failed: {e}")

    async def enqueue(self, record: TelemetryRecord) -> bool:
        """
        Add a record to the queue.
        EDGE-5: Enforces both record-count and byte-size caps.
        Drops oldest records when either cap is exceeded.
        """
        async with self._lock:
            # Check record-count cap
            cursor = await self._db.execute("SELECT COUNT(*) FROM telemetry_queue")
            count = (await cursor.fetchone())[0]

            dropped = False
            if count >= self.max_size:
                delete_count = count - self.max_size + 100
                await self._db.execute(
                    "DELETE FROM telemetry_queue WHERE id IN "
                    "(SELECT id FROM telemetry_queue ORDER BY id ASC LIMIT ?)",
                    (delete_count,)
                )
                self._deletes_since_vacuum += delete_count
                logger.warning(f"Queue record cap hit, dropped {delete_count} oldest records")
                dropped = True

            # EDGE-5: Check byte-size cap
            db_bytes = await self._get_db_size_bytes()
            if db_bytes > self.max_bytes:
                # Drop 10% of records to create headroom
                drop_pct = max(100, count // 10)
                await self._db.execute(
                    "DELETE FROM telemetry_queue WHERE id IN "
                    "(SELECT id FROM telemetry_queue ORDER BY id ASC LIMIT ?)",
                    (drop_pct,)
                )
                self._deletes_since_vacuum += drop_pct
                logger.warning(
                    f"Queue byte cap hit ({db_bytes / 1024 / 1024:.1f} MB > "
                    f"{self.max_bytes / 1024 / 1024:.0f} MB), dropped {drop_pct} oldest records"
                )
                dropped = True

            if dropped:
                await self._maybe_vacuum()

            # Insert new record
            await self._db.execute(
                "INSERT INTO telemetry_queue (ts_ms, source, data, queued_at) VALUES (?, ?, ?, ?)",
                (record.ts_ms, record.source, json.dumps(record.data), record.queued_at)
            )
            await self._db.commit()
            return True

    async def dequeue_batch(self, batch_size: int) -> List[tuple]:
        """
        Get a batch of records from the queue (oldest first).
        Returns list of (id, TelemetryRecord) tuples.
        Does NOT remove them - call remove_batch after successful upload.
        """
        async with self._lock:
            cursor = await self._db.execute(
                "SELECT id, ts_ms, source, data, queued_at FROM telemetry_queue "
                "ORDER BY id ASC LIMIT ?",
                (batch_size,)
            )
            rows = await cursor.fetchall()

            result = []
            for row in rows:
                record = TelemetryRecord(
                    ts_ms=row[1],
                    source=row[2],
                    data=json.loads(row[3]),
                    queued_at=row[4],
                )
                result.append((row[0], record))

            return result

    async def remove_batch(self, ids: List[int]):
        """Remove successfully uploaded records from the queue."""
        if not ids:
            return

        # Ensure IDs are integers to prevent injection
        if not all(isinstance(i, int) for i in ids):
            logger.error("Invalid IDs passed to remove_batch")
            return

        async with self._lock:
            placeholders = ",".join("?" * len(ids))
            await self._db.execute(
                f"DELETE FROM telemetry_queue WHERE id IN ({placeholders})",
                ids
            )
            await self._db.commit()
            # EDGE-5: Track deletions for periodic WAL checkpoint
            self._deletes_since_vacuum += len(ids)
            await self._maybe_vacuum()

    async def get_stats(self) -> Dict[str, Any]:
        """Get queue statistics including byte size (EDGE-5)."""
        cursor = await self._db.execute("""
            SELECT
                COUNT(*) as total,
                COUNT(CASE WHEN source = 'gps' THEN 1 END) as gps,
                COUNT(CASE WHEN source = 'can' THEN 1 END) as can,
                COUNT(CASE WHEN source = 'ant' THEN 1 END) as ant
            FROM telemetry_queue
        """)
        row = await cursor.fetchone()
        db_bytes = await self._get_db_size_bytes()
        return {
            "total": row[0],
            "gps": row[1],
            "can": row[2],
            "ant": row[3],
            "db_bytes": db_bytes,
            "db_mb": round(db_bytes / 1024 / 1024, 1),
            "max_bytes": self.max_bytes,
        }

    async def close(self):
        """Close the database connection."""
        if self._db:
            await self._db.close()
            self._db = None


# ============ Cloud Uploader ============

class CloudUploader:
    """
    Handles batched uploads to the cloud API with retry logic.
    """

    def __init__(self, config: UplinkConfig):
        self.config = config
        self._client: Optional[httpx.AsyncClient] = None
        self._retry_delay = config.upload_retry_base_s
        self._consecutive_failures = 0
        self._last_success_time = time.time()

    async def initialize(self):
        """Initialize the HTTP client."""
        self._client = httpx.AsyncClient(
            timeout=httpx.Timeout(self.config.upload_timeout_s),
            limits=httpx.Limits(max_connections=5),
        )

    async def upload_batch(self, records: List[TelemetryRecord]) -> bool:
        """
        Upload a batch of telemetry records to the cloud.
        Returns True on success, False on failure.
        """
        if not records:
            return True

        if not self.config.cloud_url or not self.config.truck_token:
            logger.error("Cloud URL or truck token not configured!")
            return False

        # Separate GPS positions from CAN/ANT telemetry
        positions = []
        telemetry = []

        for record in records:
            if record.source == "gps":
                pos = record.to_position()
                if pos and pos.get("lat") and pos.get("lon"):
                    positions.append(pos)
            else:
                telem = record.to_telemetry()
                if telem:
                    telemetry.append(telem)

        # Build payload
        payload = {
            "positions": positions,
        }
        if telemetry:
            payload["telemetry"] = telemetry

        url = f"{self.config.cloud_url.rstrip('/')}/api/v1/telemetry/ingest"
        headers = {
            "X-Truck-Token": self.config.truck_token,
            "Content-Type": "application/json",
        }

        try:
            response = await self._client.post(url, json=payload, headers=headers)

            if response.status_code in (200, 201, 202):
                self._consecutive_failures = 0
                self._retry_delay = self.config.upload_retry_base_s
                self._last_success_time = time.time()

                result = response.json()
                accepted = result.get("accepted", len(positions))
                rejected = result.get("rejected", 0)
                crossings = result.get("checkpoint_crossings", [])

                if crossings:
                    for cp in crossings:
                        logger.info(f"🏁 Checkpoint {cp.get('checkpoint_number')}: {cp.get('checkpoint_name', '')}")

                logger.debug(f"Upload success: {accepted} accepted, {rejected} rejected")
                return True

            elif response.status_code == 401:
                logger.error("Authentication failed - check ARGUS_TRUCK_TOKEN")
                return False

            elif response.status_code == 429:
                logger.warning("Rate limited by server, backing off")
                self._increase_retry_delay()
                return False

            else:
                logger.warning(f"Upload failed: HTTP {response.status_code}")
                self._increase_retry_delay()
                return False

        except httpx.ConnectError:
            logger.warning("Network unreachable - data buffered locally")
            self._increase_retry_delay()
            return False

        except httpx.TimeoutException:
            logger.warning("Upload timeout - will retry")
            self._increase_retry_delay()
            return False

        except Exception as e:
            logger.error(f"Upload error: {e}")
            self._increase_retry_delay()
            return False

    def _increase_retry_delay(self):
        """Exponential backoff for retry delays."""
        self._consecutive_failures += 1
        self._retry_delay = min(
            self._retry_delay * 2,
            self.config.upload_retry_max_s
        )

    @property
    def retry_delay(self) -> float:
        """Current retry delay in seconds."""
        return self._retry_delay

    @property
    def is_connected(self) -> bool:
        """Check if we've had a recent successful upload."""
        return (time.time() - self._last_success_time) < 30.0

    async def close(self):
        """Close the HTTP client."""
        if self._client:
            await self._client.aclose()
            self._client = None


# ============ ZMQ Subscriber ============

class ZMQCollector:
    """
    Subscribes to local ZMQ publishers and routes data to the queue.
    """

    def __init__(self, queue: LocalQueue):
        self.queue = queue
        self._context: Optional[zmq.asyncio.Context] = None
        self._sockets: Dict[str, zmq.asyncio.Socket] = {}
        self._running = False
        self._stats = {"gps": 0, "can": 0, "ant": 0}
        # EDGE-7: Track which data sources are actively producing data
        self._source_last_seen: Dict[str, float] = {}
        self._source_timeout_s = 15.0  # Consider source inactive after 15s silence

    async def initialize(self, config: UplinkConfig):
        """Initialize ZMQ context and sockets."""
        self._context = zmq.asyncio.Context()

        # GPS subscriber (port 5558)
        self._sockets["gps"] = self._context.socket(zmq.SUB)
        self._sockets["gps"].connect(f"tcp://localhost:{config.zmq_gps_port}")
        self._sockets["gps"].setsockopt_string(zmq.SUBSCRIBE, "")  # Subscribe to all
        logger.info(f"ZMQ GPS subscriber connected to port {config.zmq_gps_port}")

        # CAN subscriber (port 5557)
        self._sockets["can"] = self._context.socket(zmq.SUB)
        self._sockets["can"].connect(f"tcp://localhost:{config.zmq_can_port}")
        self._sockets["can"].setsockopt_string(zmq.SUBSCRIBE, "")
        logger.info(f"ZMQ CAN subscriber connected to port {config.zmq_can_port}")

        # ANT+ subscriber (port 5556)
        self._sockets["ant"] = self._context.socket(zmq.SUB)
        self._sockets["ant"].connect(f"tcp://localhost:{config.zmq_ant_port}")
        self._sockets["ant"].setsockopt_string(zmq.SUBSCRIBE, "")
        logger.info(f"ZMQ ANT+ subscriber connected to port {config.zmq_ant_port}")

    async def run(self):
        """Run the collector - receives from all sources."""
        self._running = True

        # Create tasks for each source
        tasks = [
            asyncio.create_task(self._receive_loop("gps", self._sockets["gps"])),
            asyncio.create_task(self._receive_loop("can", self._sockets["can"])),
            asyncio.create_task(self._receive_loop("ant", self._sockets["ant"])),
        ]

        try:
            await asyncio.gather(*tasks)
        except asyncio.CancelledError:
            pass

    async def _receive_loop(self, source: str, socket: zmq.asyncio.Socket):
        """Receive loop for a single ZMQ socket."""
        logger.info(f"Starting {source.upper()} receive loop")

        while self._running:
            try:
                # Non-blocking receive with timeout
                if await socket.poll(timeout=100):  # 100ms timeout
                    message = await socket.recv_multipart()

                    # Parse message (topic + payload format)
                    if len(message) >= 2:
                        topic = message[0].decode() if message[0] else source
                        payload = json.loads(message[1].decode())
                    else:
                        payload = json.loads(message[0].decode())

                    # Create telemetry record
                    ts_ms = payload.get("ts_ms", int(time.time() * 1000))
                    record = TelemetryRecord(
                        ts_ms=ts_ms,
                        source=source,
                        data=payload,
                    )

                    # Immediately write to queue (disk)
                    await self.queue.enqueue(record)
                    self._stats[source] += 1
                    # EDGE-7: Track last data received per source
                    self._source_last_seen[source] = time.time()

            except zmq.ZMQError as e:
                if e.errno != zmq.EAGAIN:
                    logger.error(f"ZMQ error on {source}: {e}")
                    await asyncio.sleep(0.1)
            except json.JSONDecodeError as e:
                logger.warning(f"Invalid JSON from {source}: {e}")
            except Exception as e:
                logger.error(f"Error receiving from {source}: {e}")
                await asyncio.sleep(0.1)

    def stop(self):
        """Signal the collector to stop."""
        self._running = False

    @property
    def stats(self) -> Dict[str, int]:
        """Get receive statistics."""
        return self._stats.copy()

    @property
    def source_status(self) -> Dict[str, str]:
        """EDGE-7: Get active/inactive status per data source."""
        now = time.time()
        result = {}
        for source in ("gps", "can", "ant"):
            last = self._source_last_seen.get(source)
            if last is None:
                result[source] = "no_data"
            elif (now - last) > self._source_timeout_s:
                result[source] = "stale"
            else:
                result[source] = "active"
        return result

    async def close(self):
        """Close all sockets and context."""
        self._running = False

        for name, socket in self._sockets.items():
            socket.close()

        if self._context:
            self._context.term()


# ============ Main Service ============

class UplinkService:
    """
    Main uplink service orchestrator.
    """

    def __init__(self, config: UplinkConfig):
        self.config = config
        self.queue = LocalQueue(config.db_path, config.max_queue_size, config.max_queue_bytes)
        self.uploader = CloudUploader(config)
        self.collector = ZMQCollector(self.queue)
        self._running = False
        self._upload_task: Optional[asyncio.Task] = None
        self._stats_task: Optional[asyncio.Task] = None

    async def start(self):
        """Start all service components."""
        logger.info("=" * 60)
        logger.info("Argus Uplink Service Starting")
        logger.info("=" * 60)
        logger.info(f"Vehicle: {self.config.vehicle_number}")
        logger.info(f"Cloud URL: {self.config.cloud_url}")
        logger.info(f"Queue DB: {self.config.db_path}")
        logger.info(f"Batch size: {self.config.batch_size}")
        # EDGE-7: Uplink runs independently of data sources
        logger.info("Mode: independent (queues available data; GPS/CAN/ANT optional)")
        logger.info("=" * 60)

        # Validate configuration
        if not self.config.cloud_url:
            logger.error("ARGUS_CLOUD_URL not set!")
            return

        if not self.config.truck_token:
            logger.error("ARGUS_TRUCK_TOKEN not set!")
            return

        self._running = True

        # Initialize components
        await self.queue.initialize()
        await self.uploader.initialize()
        await self.collector.initialize(self.config)

        # Start background tasks
        self._upload_task = asyncio.create_task(self._upload_loop())
        self._stats_task = asyncio.create_task(self._stats_loop())

        # Run collector (blocks until stopped)
        try:
            await self.collector.run()
        except asyncio.CancelledError:
            pass

    async def _upload_loop(self):
        """Background task to upload batches from the queue."""
        logger.info("Upload loop started")

        while self._running:
            try:
                # Get batch from queue
                batch = await self.queue.dequeue_batch(self.config.batch_size)

                if batch:
                    ids = [item[0] for item in batch]
                    records = [item[1] for item in batch]

                    # Try to upload
                    success = await self.uploader.upload_batch(records)

                    if success:
                        # Remove from queue on success
                        await self.queue.remove_batch(ids)
                        logger.debug(f"Uploaded and removed {len(ids)} records")
                    else:
                        # Wait before retry (exponential backoff)
                        await asyncio.sleep(self.uploader.retry_delay)
                else:
                    # No data, wait a bit
                    await asyncio.sleep(self.config.batch_timeout_s)

            except asyncio.CancelledError:
                break
            except Exception as e:
                logger.error(f"Upload loop error: {e}")
                await asyncio.sleep(1.0)

    async def _stats_loop(self):
        """Periodically log statistics."""
        while self._running:
            try:
                await asyncio.sleep(30)  # Every 30 seconds

                queue_stats = await self.queue.get_stats()
                collector_stats = self.collector.stats
                connected = "✓" if self.uploader.is_connected else "✗"
                # EDGE-7: Show per-source activity status
                src_status = self.collector.source_status

                logger.info(
                    f"Stats: Queue={queue_stats['total']} ({queue_stats['db_mb']}MB) | "
                    f"Received: GPS={collector_stats['gps']} CAN={collector_stats['can']} ANT={collector_stats['ant']} | "
                    f"Sources: GPS={src_status['gps']} CAN={src_status['can']} ANT={src_status['ant']} | "
                    f"Cloud={connected}"
                )

                # EDGE-5: Write queue status to state file for edge_status/dashboard
                try:
                    queue_status = {
                        "depth": queue_stats["total"],
                        "db_bytes": queue_stats["db_bytes"],
                        "db_mb": queue_stats["db_mb"],
                        "max_records": self.queue.max_size,
                        "max_bytes": self.queue.max_bytes,
                        "cloud_connected": self.uploader.is_connected,
                        "sources": src_status,
                        "epoch": int(time.time()),
                    }
                    state_path = Path("/opt/argus/state/queue_status.json")
                    state_path.write_text(json.dumps(queue_status))
                except Exception:
                    pass  # Non-critical — don't disrupt uplink

            except asyncio.CancelledError:
                break
            except Exception as e:
                logger.error(f"Stats error: {e}")

    async def stop(self):
        """Stop all service components gracefully."""
        logger.info("Shutting down uplink service...")
        self._running = False

        # Stop collector first
        self.collector.stop()

        # Cancel background tasks
        if self._upload_task:
            self._upload_task.cancel()
            try:
                await self._upload_task
            except asyncio.CancelledError:
                pass

        if self._stats_task:
            self._stats_task.cancel()
            try:
                await self._stats_task
            except asyncio.CancelledError:
                pass

        # Final upload attempt for remaining data
        logger.info("Uploading remaining queued data...")
        remaining = await self.queue.dequeue_batch(self.config.batch_size * 10)
        if remaining:
            records = [item[1] for item in remaining]
            if await self.uploader.upload_batch(records):
                await self.queue.remove_batch([item[0] for item in remaining])
                logger.info(f"Uploaded {len(remaining)} remaining records")

        # Close everything
        await self.collector.close()
        await self.uploader.close()
        await self.queue.close()

        logger.info("Uplink service stopped")


# ============ Main Entry Point ============

async def main():
    """Main entry point."""
    config = UplinkConfig.from_env()

    # Set log level
    logging.getLogger().setLevel(getattr(logging, config.log_level.upper()))

    service = UplinkService(config)

    # Handle signals
    loop = asyncio.get_event_loop()

    def signal_handler():
        logger.info("Received shutdown signal")
        asyncio.create_task(service.stop())

    for sig in (signal.SIGTERM, signal.SIGINT):
        loop.add_signal_handler(sig, signal_handler)

    try:
        await service.start()
    except KeyboardInterrupt:
        pass
    finally:
        await service.stop()


if __name__ == "__main__":
    asyncio.run(main())
