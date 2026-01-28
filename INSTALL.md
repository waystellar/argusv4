# Argus Timing System v4.0 - Installation Guide

This guide covers three installation scenarios:

| Scenario | Use Case | Script |
|----------|----------|--------|
| **1. Cloud Server** | Ubuntu server (set up first!) | `./install/install_cloud.sh` |
| **2. Edge (Truck)** | Intel N150 mini PC in race vehicle | `./edge/install.sh` |
| **3. Development** | Local testing without hardware | `./install/install_dev.sh` |

**Important:** Install the cloud server first! Edge devices need the server URL and auth tokens.

---

## Quick Start

Both installers are **headless** (non-interactive) and use **web-based configuration**:

```bash
# Clone the repository
git clone https://github.com/waystellar/argusv4.git
cd argusv4

# Step 1: Set up cloud server first
sudo ./install/install_cloud.sh
# Then visit http://<server-ip>/ for the admin dashboard

# For fresh installations (removes existing and reinstalls):
sudo ./install/install_cloud.sh --clean

# For complete fresh start (also removes Docker images):
sudo ./install/install_cloud.sh --nuke

# Step 2: Set up edge devices (after cloud is configured)
sudo ./edge/install.sh
# Then visit http://<device-ip>:8080 to configure each truck
```

No terminal prompts - all configuration happens through your web browser.

### Install Flags

| Flag | Description |
|------|-------------|
| `--clean` | Uninstall existing installation first, then fresh install |
| `--nuke` | Remove everything including Docker images, then fresh install |
| `-h, --help` | Show help message |

---

## 1. Cloud Server Installation (Set Up First)

### Server Requirements

- Ubuntu 24.04 LTS (or 22.04)
- 2+ CPU cores
- 4GB+ RAM
- 20GB+ disk space
- Public IP or domain (for production)

### Installation

```bash
# SSH into your server
ssh ubuntu@your-server-ip

# Clone the repo and run installer
git clone https://github.com/waystellar/argusv4.git
cd argusv4
sudo ./install/install_cloud.sh
```

### What the Installer Does

The installer is **fully automatic** with no prompts:

1. Detects your operating system
2. Installs Docker and Docker Compose (if needed)
3. Copies application files to `/opt/argus-cloud`
4. Creates a default `.env` in **Setup Mode**
5. Builds and starts the Docker containers
6. Displays the setup wizard URL

### Admin Dashboard

After installation completes, open your browser:

```
http://<your-server-ip>/
```

The **Admin Dashboard** is the main entry point, providing:

1. **System Health** - Database, Redis, and truck connectivity status
2. **Event Management** - Create and manage race events
3. **Vehicle Registration** - Register trucks and generate auth tokens
4. **Quick Links** - Access to fan view, team dashboard, API docs

### Initial Setup (if not configured)

If the system hasn't been configured yet, you'll be redirected to:

```
http://<your-server-ip>/setup
```

The setup wizard guides you through:

1. **Deployment Mode** - Local (SQLite) or Production (PostgreSQL + Redis)
2. **Server Settings** - Hostname, CORS origins, database URLs
3. **Authentication** - Admin token and truck tokens (auto-generated)
4. **Review & Complete** - Save tokens for edge device setup

**Save your truck tokens!** You'll need them when configuring edge devices.

### Deployment Modes

| Mode | Database | Cache | Use Case |
|------|----------|-------|----------|
| **Local** | SQLite | In-memory | Testing, small events |
| **Production** | PostgreSQL | Redis | Real events, multiple viewers |

### Post-Setup

```bash
# Check service status
docker ps

# View logs
docker logs argus-api -f

# Test API health
curl http://localhost:8000/health
```

### Management Commands

After installation, use these scripts at `/opt/argus-cloud/`:

| Script | Description |
|--------|-------------|
| `start.sh` | Start all containers |
| `stop.sh` | Stop all containers |
| `logs.sh` | View container logs |
| `rebuild.sh` | Rebuild and restart |

---

## 2. Edge Installation (Race Truck)

**Prerequisites:** Complete cloud server setup first to get truck tokens.

### Hardware Requirements

- Intel N150 mini PC (or similar x86_64 system) running Ubuntu 24.04
- GPS USB receiver (u-blox recommended)
- CAN bus adapter (USB CAN like PEAK PCAN-USB, Kvaser, or CANtact)
- ANT+ USB stick (optional, for heart rate)
- USB webcams for video streaming (optional)
- 4G/LTE modem or WiFi for connectivity

### Installation

```bash
# SSH into your edge device (or connect keyboard/monitor)
ssh argus@edge-device.local

# Clone the repo and run installer
git clone https://github.com/waystellar/argusv4.git
cd argusv4
sudo ./edge/install.sh
```

### What the Installer Does

The installer is **fully automatic** with no prompts:

1. Updates system packages
2. Installs dependencies (Python, ZMQ, FFmpeg)
3. Creates `argus` system user
4. Sets up Python virtual environment
5. Configures udev rules for USB devices
6. Installs systemd services in **Provisioning Mode**
7. Starts the web-based provisioning portal

### Web Provisioning Portal

After installation, the device boots into provisioning mode. Connect to:

```
http://<device-ip>:8080
```

Or if device is on your local network:

```
http://argusedge1.local:8080  (if mDNS is working)
```

The provisioning portal asks for:

1. **Vehicle Number** - Truck identifier (e.g., "42", "Truck-A")
2. **Cloud Server URL** - From your cloud setup (e.g., `https://192.168.1.100:8000`)
3. **Truck Token** - One of the tokens generated during cloud setup
4. **GPS Device** - Auto-detected or manual selection
5. **CAN Adapter** - Auto-detected or manual selection

### Provisioning API

For bulk fleet deployment, use the API endpoint:

```bash
curl -X POST http://<device-ip>:8080/api/provision \
  -H "Content-Type: application/json" \
  -d '{
    "vehicle_id": "truck-42",
    "cloud_url": "https://your-cloud-server.com",
    "auth_token": "truck_abc123def456",
    "gps_device": "/dev/ttyUSB0",
    "can_interface": "can0"
  }'
```

This allows scripted provisioning of multiple trucks without manual web access.

### After Provisioning

Once configured, the device:

1. Creates `/etc/argus/.provisioned` flag
2. Reboots automatically
3. Starts in **Telemetry Mode** (data collection + upload)

### Services in Telemetry Mode

| Service | Description | Port |
|---------|-------------|------|
| `argus-gps` | GPS data collection | ZMQ 5558 |
| `argus-can` | CAN bus telemetry | ZMQ 5557 |
| `argus-uplink` | Cloud data sync | HTTP |

### Post-Provisioning

```bash
# Check service status
sudo systemctl status argus-uplink

# View logs
sudo journalctl -u argus-uplink -f

# Check USB device symlinks
ls -la /dev/argus_*
```

### Re-Provisioning a Device

To reconfigure a device:

```bash
# Remove provisioned flag
sudo rm /etc/argus/.provisioned

# Reboot into provisioning mode
sudo reboot

# Device will boot into web provisioning portal again
```

---

## 3. Development Installation

### Requirements

- macOS or Linux
- Python 3.10+
- Node.js 18+
- Docker (optional, for full stack)

### Installation

```bash
git clone https://github.com/waystellar/argusv4.git
cd argusv4
./install/install_dev.sh
```

### What the Installer Does

1. Checks/installs prerequisites
2. Creates Python virtual environment
3. Installs all dependencies
4. Sets up local SQLite database
5. Installs frontend dependencies
6. Creates test runner scripts

### Running Tests

After installation:

```bash
# Activate virtual environment
source .venv/bin/activate

# Test 1: Full Stack with Docker
./test/run_docker_stack.sh

# Test 2: Simulator only (no hardware)
./test/run_simulator.sh

# Test 3: Load test (50 vehicles)
./test/run_load_test.sh
```

### Manual Testing

```bash
# Terminal 1: Start cloud server
source .venv/bin/activate
cd cloud
python -m uvicorn app.main:app --reload

# Terminal 2: Start frontend
cd web
npm run dev

# Terminal 3: Run simulator
source .venv/bin/activate
cd edge
python simulator.py --api-url http://localhost:8000 --vehicles 5
```

---

## AWS Deployment

For production AWS deployment, use Terraform:

```bash
cd deploy/aws

# Copy and edit variables
cp prod.tfvars.example prod.tfvars
vim prod.tfvars

# Initialize and apply
terraform init
terraform plan -var-file=prod.tfvars
terraform apply -var-file=prod.tfvars
```

### AWS Architecture

```
                    ┌─────────────┐
                    │   Route 53  │
                    │  (DNS)      │
                    └──────┬──────┘
                           │
                    ┌──────▼──────┐
                    │     ALB     │
                    │  (HTTPS)    │
                    └──────┬──────┘
                           │
              ┌────────────┼────────────┐
              │            │            │
       ┌──────▼──────┐ ┌───▼───┐ ┌──────▼──────┐
       │   ECS/EC2   │ │  ...  │ │   ECS/EC2   │
       │  (Worker 1) │ │       │ │  (Worker N) │
       └──────┬──────┘ └───────┘ └──────┬──────┘
              │                         │
              └────────────┬────────────┘
                           │
              ┌────────────┼────────────┐
              │            │            │
       ┌──────▼──────┐ ┌───▼───────┐
       │  RDS        │ │ ElastiCache│
       │ PostgreSQL  │ │   Redis    │
       └─────────────┘ └───────────┘
```

---

## Troubleshooting

### Cloud Issues

**Setup wizard not loading:**
```bash
# Check if container is running
docker ps

# Check container logs
docker logs argus-api

# Check if port 8000 is accessible
curl http://localhost:8000/health
```

**Container won't start:**
```bash
docker logs argus-api
docker compose logs -f
```

**CORS errors:**
```bash
# After setup, check CORS_ORIGINS in .env
cat /opt/argus-cloud/.env | grep CORS
```

### Edge Issues

**Provisioning portal not accessible:**
```bash
# Check if provisioning service is running
sudo systemctl status argus-provision

# Check logs
sudo journalctl -u argus-provision -f

# Verify port 8080 is open
sudo ss -tlnp | grep 8080
```

**GPS not detected:**
```bash
# Check USB devices
lsusb
dmesg | grep -i gps

# Check udev rules
cat /etc/udev/rules.d/99-argus*.rules
sudo udevadm control --reload-rules
sudo udevadm trigger

# Check symlink
ls -la /dev/argus_gps
```

**Services not starting after provisioning:**
```bash
# Check if provisioned flag exists
ls -la /etc/argus/.provisioned

# Check service status
sudo systemctl status argus-uplink

# View detailed logs
sudo journalctl -u argus-uplink -n 100 --no-pager
```

**Upload failures:**
```bash
# Test cloud connectivity
curl -v https://your-cloud-server.com/health

# Check queue database
sqlite3 /opt/argus/data/queue.db "SELECT COUNT(*) FROM positions WHERE uploaded=0"
```

### Development Issues

**Python import errors:**
```bash
# Ensure virtual environment is activated
source .venv/bin/activate
which python  # Should show .venv/bin/python

# Reinstall dependencies
pip install -r cloud/requirements.txt
pip install -r edge/requirements.txt
```

**Frontend not connecting:**
```bash
# Check VITE_API_URL in web/.env
cat web/.env

# Verify API is running
curl http://localhost:8000/health
```

---

## Upgrading

### Edge Upgrade

```bash
cd /opt/argus
sudo systemctl stop argus-uplink argus-gps argus-can
sudo -u argus git pull
sudo -u argus ./venv/bin/pip install -r requirements.txt
sudo systemctl start argus-gps argus-can argus-uplink
```

### Cloud Upgrade

```bash
cd /opt/argus-cloud
docker compose down
git pull
docker compose build
docker compose up -d
```

---

## Uninstalling

### Uninstall Edge

```bash
# Standard uninstall (removes everything)
sudo ./edge/uninstall.sh

# Keep data files (queue database, logs)
sudo ./edge/uninstall.sh --keep-data
```

**What gets removed:**
- Systemd services (argus-gps, argus-can, argus-uplink, argus-provision)
- udev rules
- Configuration files (/etc/argus/)
- Installation directory (/opt/argus/)
- Optionally: argus user account

### Uninstall Cloud

```bash
# Standard uninstall
./install/uninstall_cloud.sh

# Keep database volumes (preserve data)
./install/uninstall_cloud.sh --keep-data

# Nuclear option (remove images too)
./install/uninstall_cloud.sh --nuke
```

**What gets removed:**
- Docker containers (argus-api, argus-web, argus-postgres, argus-redis)
- Docker volumes (database data)
- Docker network
- Installation directory (/opt/argus-cloud/)
- Generated configuration files

### Uninstall Development Environment

```bash
# Standard cleanup
./install/uninstall_dev.sh

# Deep clean (also removes node_modules, __pycache__)
./install/uninstall_dev.sh --deep

# Nuclear option (removes everything including Docker, git-ignored files)
./install/uninstall_dev.sh --nuke
```

**What gets removed:**

| Mode | Removes |
|------|---------|
| Standard | .venv/, test/, *.db files, .env files |
| Deep | + node_modules/, __pycache__/, .pytest_cache/, build/ |
| Nuke | + Docker resources, lock files, all git-ignored files |

---

## Fleet Deployment Workflow

For deploying multiple trucks efficiently:

### 1. Set Up Cloud Server

```bash
sudo ./install/install_cloud.sh
# Visit http://<server-ip>:8000/setup
# Generate 30+ truck tokens (one per vehicle)
# Save tokens to a spreadsheet
```

### 2. Prepare Edge Devices

Flash Ubuntu 24.04 on each Intel N150, then:

```bash
# On each device
git clone https://github.com/waystellar/argusv4.git
cd argusv4
sudo ./edge/install.sh
```

### 3. Bulk Provisioning

Use the API for scripted provisioning:

```bash
#!/bin/bash
# provision_fleet.sh

CLOUD_URL="https://your-server.com"
DEVICES=("192.168.1.101" "192.168.1.102" "192.168.1.103")
TOKENS=("truck_token1" "truck_token2" "truck_token3")
VEHICLE_IDS=("Truck-1" "Truck-2" "Truck-3")

for i in "${!DEVICES[@]}"; do
  curl -X POST "http://${DEVICES[$i]}:8080/api/provision" \
    -H "Content-Type: application/json" \
    -d "{
      \"vehicle_id\": \"${VEHICLE_IDS[$i]}\",
      \"cloud_url\": \"$CLOUD_URL\",
      \"auth_token\": \"${TOKENS[$i]}\"
    }"
done
```

---

## Support

- GitHub Issues: https://github.com/waystellar/argusv4/issues
