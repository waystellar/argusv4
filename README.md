# Argus Timing System v4.0

Live off-road racing timing and telemetry platform.

## Quick Start (Production)

```bash
# Clone the repository
git clone https://github.com/waystellar/argusv4.git
cd argusv4

# Install on cloud server (Ubuntu 24.04)
sudo ./install/install_cloud.sh

# For fresh installation (recommended for testing)
sudo ./install/install_cloud.sh --clean

# For complete reset (also removes Docker images)
sudo ./install/install_cloud.sh --nuke
```

After installation, open your browser to access:
- **Admin Dashboard**: http://your-server-ip/
- **API Docs**: http://your-server-ip/docs
- **Setup Wizard** (if not configured): http://your-server-ip/setup

### Uninstall

```bash
# Standard uninstall
./install/uninstall_cloud.sh

# Keep database data
./install/uninstall_cloud.sh --keep-data

# Remove everything including images
./install/uninstall_cloud.sh --nuke
```

See [INSTALL.md](INSTALL.md) for complete installation guide.

## Running the Simulator

The simulator creates a demo event with vehicles and simulates GPS telemetry:

```bash
cd edge
pip install -r requirements.txt
python simulator.py --api-url http://localhost:8000 --vehicles 5
```

This will:
1. Create a demo event
2. Upload a sample GPX course
3. Register 5 vehicles with truck tokens
4. Start simulating GPS positions at 5Hz

## Manual Development Setup

### Backend (FastAPI)

```bash
cd cloud
python -m venv venv
source venv/bin/activate  # or venv\Scripts\activate on Windows
pip install -r requirements.txt

# Start PostgreSQL and Redis (or use Docker)
docker run -d --name argus-pg -e POSTGRES_USER=argus -e POSTGRES_PASSWORD=argus -e POSTGRES_DB=argus -p 5432:5432 postgres:16-alpine
docker run -d --name argus-redis -p 6379:6379 redis:7-alpine

# Set environment variables
export DATABASE_URL=postgresql+asyncpg://argus:argus@localhost:5432/argus
export REDIS_URL=redis://localhost:6379

# Run server
uvicorn app.main:app --reload
```

### Frontend (React)

```bash
cd web
npm install
npm run dev
```

## API Endpoints

### Events
- `POST /api/v1/events` - Create event
- `GET /api/v1/events` - List events
- `GET /api/v1/events/{id}` - Get event
- `POST /api/v1/events/{id}/course` - Upload GPX course

### Vehicles
- `POST /api/v1/vehicles` - Register vehicle (returns truck_token)
- `GET /api/v1/vehicles` - List vehicles
- `POST /api/v1/vehicles/{id}/events/{eid}/register` - Register for event
- `PUT /api/v1/vehicles/{id}/visibility` - Toggle visibility

### Telemetry
- `POST /api/v1/telemetry/ingest` - Upload position batch (requires X-Truck-Token header)
- `GET /api/v1/events/{id}/positions/latest` - Get all latest positions

### Real-time
- `GET /api/v1/events/{id}/stream` - SSE stream for live updates
- `GET /api/v1/events/{id}/leaderboard` - Current standings
- `GET /api/v1/events/{id}/splits` - Checkpoint split times

## Demo Validation Checklist

- [ ] Create event via API
- [ ] Upload GPX course
- [ ] Register vehicles
- [ ] Start simulator
- [ ] Open web app (http://localhost:5173)
- [ ] See vehicles moving on map
- [ ] Leaderboard updates on checkpoint crossings
- [ ] Click vehicle → see detail page
- [ ] Toggle vehicle visibility → see it disappear

## Project Structure

```
argus_v4/
├── cloud/                 # FastAPI backend
│   ├── app/
│   │   ├── main.py       # Application entry
│   │   ├── config.py     # Settings
│   │   ├── models.py     # SQLAlchemy models
│   │   ├── schemas.py    # Pydantic schemas
│   │   ├── database.py   # DB connection
│   │   ├── redis_client.py
│   │   ├── routes/       # API endpoints
│   │   └── services/     # Business logic
│   ├── requirements.txt
│   └── Dockerfile
├── edge/                  # Edge device code
│   ├── simulator.py      # GPS simulator
│   └── requirements.txt
├── web/                   # React PWA
│   ├── src/
│   │   ├── pages/        # Route pages
│   │   ├── components/   # UI components
│   │   ├── hooks/        # Custom hooks
│   │   ├── stores/       # Zustand stores
│   │   └── api/          # API client
│   ├── package.json
│   └── Dockerfile
├── deploy/
│   └── docker-compose.yml
└── docs/
```

## License

Proprietary - Administrative Results, L.L.C.
