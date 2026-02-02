"""
Argus Timing System v4.0 - Setup Wizard Route

Provides web-based first-time configuration when SETUP_COMPLETED=false.
This route serves both the HTML wizard UI and handles configuration API.
"""
import asyncio
import os
import secrets
import signal
import socket
from pathlib import Path
from typing import Optional

import bcrypt
from fastapi import APIRouter, BackgroundTasks, HTTPException, Request
from fastapi.responses import HTMLResponse, JSONResponse
from pydantic import BaseModel, Field

from app.config import get_settings


def hash_password(password: str) -> str:
    """Hash a password using bcrypt."""
    salt = bcrypt.gensalt(rounds=12)
    return bcrypt.hashpw(password.encode('utf-8'), salt).decode('utf-8')


def get_server_ip() -> str:
    """Get the server's actual IP address."""
    try:
        # Create a socket and connect to an external address
        # This gets the IP of the interface used for outbound connections
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        try:
            # Fallback: get hostname IP
            return socket.gethostbyname(socket.gethostname())
        except Exception:
            return "localhost"

router = APIRouter(prefix="/setup", tags=["setup"])

# Path to .env file (mounted from host in Docker)
ENV_FILE_PATH = Path("/app/.env")
# Alternative path for local development
LOCAL_ENV_PATH = Path(__file__).parent.parent.parent / ".env"


def read_existing_env() -> dict[str, str]:
    """
    Read existing .env file and return as dict.
    Preserves infrastructure settings (DATABASE_URL, REDIS_URL) that were set by installer.
    """
    env_path = ENV_FILE_PATH if ENV_FILE_PATH.exists() else LOCAL_ENV_PATH
    existing = {}
    if env_path.exists():
        try:
            content = env_path.read_text()
            for line in content.splitlines():
                line = line.strip()
                if line and not line.startswith('#') and '=' in line:
                    key, _, value = line.partition('=')
                    existing[key.strip()] = value.strip()
        except Exception:
            pass
    return existing


class SetupConfig(BaseModel):
    """Configuration submitted by setup wizard.

    Note: Truck tokens are NOT generated here - they are created when
    vehicles are registered for events via the admin dashboard.
    """
    # Server settings
    server_hostname: str = Field(..., description="Public hostname or IP")
    api_port: int = Field(default=8000, ge=1, le=65535)

    # Deployment mode
    deployment_mode: str = Field(..., pattern="^(local|production|aws)$")

    # Database (for production/aws modes)
    database_url: Optional[str] = None

    # Redis (for production/aws modes)
    redis_url: Optional[str] = None

    # Authentication - admin only (trucks get tokens when registered for events)
    admin_password: str = Field(..., min_length=4, description="Admin password for web console")
    admin_token: Optional[str] = None  # If not provided, will be generated

    # Optional settings
    enable_debug: bool = False
    log_level: str = Field(default="INFO", pattern="^(DEBUG|INFO|WARNING|ERROR)$")


def is_setup_mode() -> bool:
    """Check if server is in setup mode."""
    settings = get_settings()
    return not getattr(settings, 'setup_completed', True) or \
           os.environ.get('SETUP_COMPLETED', 'true').lower() == 'false'


def generate_token(prefix: str = "") -> str:
    """Generate a secure random token."""
    token = secrets.token_hex(16)
    return f"{prefix}_{token}" if prefix else token


@router.get("/status")
async def setup_status():
    """Check if setup is required."""
    return {
        "setup_required": is_setup_mode(),
        "message": "Visit /setup to complete configuration" if is_setup_mode() else "Setup complete"
    }


@router.get("/", response_class=HTMLResponse)
async def setup_wizard(request: Request):
    """Serve the setup wizard HTML page."""
    if not is_setup_mode():
        return HTMLResponse(
            content="""
            <!DOCTYPE html>
            <html>
            <head>
                <title>Already Configured</title>
                <style>
                    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; max-width: 600px; margin: 100px auto; text-align: center; background: #0a0a0a; color: #fafafa; padding: 16px; }
                    .success { color: #22c55e; }
                    a { color: #60a5fa; }
                    a:hover { color: #93c5fd; }
                    p { color: #a3a3a3; }
                </style>
            </head>
            <body>
                <h1 class="success">Setup Complete</h1>
                <p>The system has already been configured.</p>
                <p><a href="/">Go to Dashboard</a> | <a href="/docs">API Documentation</a></p>
            </body>
            </html>
            """,
            status_code=200
        )

    # Get server IP - prefer the Host header (what client used to reach us)
    # but fall back to actual server IP detection
    host_header = request.headers.get("host", "")
    if host_header:
        # Remove port if present
        server_ip = host_header.split(":")[0]
    else:
        server_ip = get_server_ip()

    return HTMLResponse(content=f"""
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Timing System - Setup Wizard</title>
    <style>
        * {{ box-sizing: border-box; }}
        body {{
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Oxygen, Ubuntu, sans-serif;
            background: #0a0a0a;
            color: #fafafa;
            margin: 0;
            min-height: 100vh;
            padding: 16px;
        }}
        .container {{
            max-width: 640px;
            margin: 0 auto;
            background: #171717;
            border-radius: 12px;
            border: 1px solid #404040;
            overflow: hidden;
        }}
        .header {{
            background: #171717;
            border-bottom: 1px solid #404040;
            padding: 24px 24px 20px;
        }}
        .header h1 {{
            margin: 0;
            font-size: 1.5rem;
            font-weight: 700;
            color: #fafafa;
        }}
        .header p {{
            margin: 4px 0 0;
            font-size: 0.875rem;
            color: #a3a3a3;
        }}
        .content {{
            padding: 24px;
        }}
        .step {{
            display: none;
        }}
        .step.active {{
            display: block;
        }}
        .step-indicator {{
            display: flex;
            justify-content: center;
            gap: 8px;
            margin-bottom: 24px;
        }}
        .step-dot {{
            width: 10px;
            height: 10px;
            border-radius: 9999px;
            background: #525252;
            transition: background 0.2s;
        }}
        .step-dot.active {{
            background: #3b82f6;
        }}
        .step-dot.completed {{
            background: #22c55e;
        }}
        h2 {{
            margin: 0 0 16px;
            font-size: 1.125rem;
            font-weight: 600;
            color: #fafafa;
        }}
        .form-group {{
            margin-bottom: 16px;
        }}
        label {{
            display: block;
            margin-bottom: 8px;
            font-weight: 500;
            font-size: 0.875rem;
            color: #d4d4d4;
        }}
        input, select, textarea {{
            width: 100%;
            padding: 12px 16px;
            border: 1px solid #525252;
            border-radius: 8px;
            background: #0a0a0a;
            color: #fafafa;
            font-size: 1rem;
            transition: border-color 0.1s;
        }}
        input:focus, select:focus, textarea:focus {{
            outline: none;
            border-color: #3b82f6;
            box-shadow: 0 0 0 2px rgba(59, 130, 246, 0.25);
        }}
        input::placeholder {{
            color: #737373;
        }}
        .radio-group {{
            display: flex;
            gap: 12px;
            flex-wrap: wrap;
        }}
        .radio-option {{
            flex: 1;
            min-width: 150px;
            padding: 16px;
            border: 1px solid #404040;
            border-radius: 8px;
            cursor: pointer;
            transition: border-color 0.1s, background 0.1s;
        }}
        .radio-option:hover {{
            border-color: #525252;
            background: #1f1f1f;
        }}
        .radio-option.selected {{
            border-color: #3b82f6;
            background: rgba(59, 130, 246, 0.08);
        }}
        .radio-option input {{
            display: none;
        }}
        .radio-option .title {{
            font-weight: 600;
            font-size: 0.875rem;
            margin-bottom: 4px;
            color: #fafafa;
        }}
        .radio-option .desc {{
            font-size: 0.75rem;
            color: #a3a3a3;
            line-height: 1rem;
        }}
        .token-list {{
            background: #0a0a0a;
            border-radius: 8px;
            padding: 12px;
            font-family: "JetBrains Mono", "SF Mono", Menlo, monospace;
            font-size: 0.875rem;
            max-height: 200px;
            overflow-y: auto;
        }}
        .token-item {{
            padding: 8px 0;
            border-bottom: 1px solid #262626;
        }}
        .token-item:last-child {{
            border-bottom: none;
        }}
        .button-group {{
            display: flex;
            gap: 12px;
            margin-top: 24px;
        }}
        button {{
            flex: 1;
            padding: 12px 24px;
            border: none;
            border-radius: 8px;
            font-size: 0.875rem;
            font-weight: 600;
            cursor: pointer;
            transition: background 0.1s;
        }}
        .btn-primary {{
            background: #2563eb;
            color: white;
        }}
        .btn-primary:hover {{
            background: #3b82f6;
        }}
        .btn-primary:active {{
            background: #1d4ed8;
        }}
        .btn-secondary {{
            background: #262626;
            color: #d4d4d4;
            border: 1px solid #404040;
        }}
        .btn-secondary:hover {{
            background: #363636;
        }}
        .info-box {{
            background: rgba(59, 130, 246, 0.06);
            border: 1px solid rgba(59, 130, 246, 0.2);
            border-radius: 8px;
            padding: 12px 16px;
            margin-bottom: 16px;
            font-size: 0.875rem;
            line-height: 1.4;
        }}
        .info-box.warning {{
            background: rgba(245, 158, 11, 0.06);
            border-color: rgba(245, 158, 11, 0.2);
        }}
        .info-box.success {{
            background: rgba(34, 197, 94, 0.06);
            border-color: rgba(34, 197, 94, 0.2);
        }}
        .info-box.danger {{
            background: rgba(239, 68, 68, 0.06);
            border-color: rgba(239, 68, 68, 0.2);
        }}
        .copy-btn {{
            padding: 4px 8px;
            font-size: 0.75rem;
            margin-left: 8px;
        }}
        .loading {{
            text-align: center;
            padding: 48px 24px;
        }}
        .spinner {{
            width: 32px;
            height: 32px;
            border: 3px solid #262626;
            border-top-color: #3b82f6;
            border-radius: 50%;
            animation: spin 1s linear infinite;
            margin: 0 auto 16px;
        }}
        @keyframes spin {{
            to {{ transform: rotate(360deg); }}
        }}
        .hidden {{ display: none !important; }}
        small {{
            font-size: 0.75rem;
            color: #737373;
            margin-top: 4px;
            display: block;
        }}
        a {{
            color: #60a5fa;
        }}
        a:hover {{
            color: #93c5fd;
        }}
        @media (max-width: 480px) {{
            body {{ padding: 8px; }}
            .content {{ padding: 16px; }}
            .header {{ padding: 16px; }}
            .radio-group {{ flex-direction: column; }}
            .radio-option {{ min-width: unset; }}
        }}
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>Timing System</h1>
            <p>Setup Wizard</p>
        </div>

        <div class="content">
            <div class="step-indicator">
                <div class="step-dot active" data-step="1"></div>
                <div class="step-dot" data-step="2"></div>
                <div class="step-dot" data-step="3"></div>
            </div>

            <!-- Step 1: Deployment Mode -->
            <div class="step active" data-step="1">
                <h2>Step 1: Deployment Mode</h2>
                <p style="color: #a3a3a3; margin-bottom: 16px; font-size: 0.875rem;">Choose how you want to run the timing system.</p>

                <div class="radio-group">
                    <label class="radio-option selected" onclick="selectMode(this, 'local')">
                        <input type="radio" name="mode" value="local" checked>
                        <div class="title">Local / Development</div>
                        <div class="desc">SQLite database, single server. Great for testing.</div>
                    </label>
                    <label class="radio-option" onclick="selectMode(this, 'production')">
                        <input type="radio" name="mode" value="production">
                        <div class="title">Production</div>
                        <div class="desc">PostgreSQL + Redis. For real events.</div>
                    </label>
                </div>

                <div class="button-group">
                    <button class="btn-primary" onclick="nextStep()">Next</button>
                </div>
            </div>

            <!-- Step 2: Authentication -->
            <div class="step" data-step="2">
                <h2>Step 2: Admin Authentication</h2>

                <div class="info-box">
                    <strong>Server IP Detected:</strong> {server_ip}
                </div>

                <div class="info-box danger">
                    <strong>Admin Password</strong> — Required to access the web admin console. Keep this secure.
                </div>

                <div class="form-group">
                    <label for="admin_password">Admin Password</label>
                    <input type="password" id="admin_password" placeholder="Enter a secure password (min 4 characters)" minlength="4" required>
                    <small>You'll use this to log into the admin dashboard.</small>
                </div>

                <div class="form-group">
                    <label for="admin_password_confirm">Confirm Password</label>
                    <input type="password" id="admin_password_confirm" placeholder="Confirm your password" minlength="4" required>
                </div>

                <div id="password-error" style="display: none; color: #ef4444; margin-bottom: 12px; font-size: 0.875rem;"></div>

                <div id="advanced-toggle" style="display: none;">
                    <button type="button" class="btn-secondary" style="width: auto; padding: 8px 16px; font-size: 0.75rem; margin-bottom: 12px;" onclick="toggleAdvanced()">
                        <span id="advanced-arrow">&#9654;</span> Advanced: Override Database / Redis URLs
                    </button>
                    <div id="advanced-fields" style="display: none;">
                        <div class="info-box">
                            Leave blank to use the Docker container defaults set by the installer.
                        </div>
                        <div class="form-group" id="db-settings">
                            <label for="database_url">PostgreSQL Connection URL (optional)</label>
                            <input type="text" id="database_url" placeholder="Leave blank to use installer defaults">
                        </div>
                        <div class="form-group" id="redis-settings">
                            <label for="redis_url">Redis URL (optional)</label>
                            <input type="text" id="redis_url" placeholder="Leave blank to use installer defaults">
                        </div>
                    </div>
                </div>

                <div class="button-group">
                    <button class="btn-secondary" onclick="prevStep()">Back</button>
                    <button class="btn-primary" onclick="validateAndContinue()">Next</button>
                </div>
            </div>

            <!-- Step 3: Review & Complete -->
            <div class="step" data-step="3">
                <h2>Step 3: Review & Complete</h2>

                <div class="info-box success">
                    <strong>Ready to Configure!</strong><br>
                    Review your settings below, then click "Complete Setup" to finalize.
                </div>

                <div id="review-config" style="background: #0a0a0a; padding: 16px; border-radius: 8px; margin-bottom: 16px; font-size: 0.875rem; border: 1px solid #262626;">
                    <!-- Config summary will be populated here -->
                </div>

                <div class="info-box">
                    <strong>Note:</strong> Truck tokens will be generated when you register vehicles for events in the Admin Dashboard.
                </div>

                <div class="button-group">
                    <button class="btn-secondary" onclick="prevStep()">Back</button>
                    <button class="btn-primary" onclick="completeSetup()">Complete Setup</button>
                </div>
            </div>

            <!-- Loading State -->
            <div class="step" data-step="loading">
                <div class="loading">
                    <div class="spinner"></div>
                    <p id="loading-message">Applying configuration...</p>
                    <p style="color: #737373; font-size: 0.875rem;">The server will restart automatically.</p>
                </div>
            </div>

            <!-- Success State -->
            <div class="step" data-step="success">
                <div style="text-align: center; padding: 32px 0;">
                    <h2>Setup Complete!</h2>
                    <p style="color: #a3a3a3; margin-bottom: 24px; font-size: 0.875rem;">The system is now configured and ready to use.</p>
                    <div class="info-box success">
                        <p><strong>API:</strong> <a href="/">http://<span id="final-host"></span>/</a></p>
                        <p><strong>Docs:</strong> <a href="/docs">http://<span id="final-host-2"></span>/docs</a></p>
                    </div>
                    <p style="color: #737373; margin-top: 16px; font-size: 0.875rem; line-height: 1.6;">
                        <strong style="color: #d4d4d4;">Next Steps:</strong><br>
                        1. Log into the Admin Dashboard to create events and register vehicles.<br>
                        2. When you register a vehicle, a truck token will be generated.<br>
                        3. Install the edge software on your trucks using those tokens.
                    </p>
                </div>
            </div>
        </div>
    </div>

    <script>
        let currentStep = 1;
        let config = {{
            deployment_mode: 'local',
            server_hostname: '{server_ip}',
            admin_password: '',
            admin_token: '',
            database_url: null,
            redis_url: null
        }};

        function validateAndContinue() {{
            const password = document.getElementById('admin_password').value;
            const confirm = document.getElementById('admin_password_confirm').value;
            const errorDiv = document.getElementById('password-error');

            // Validate password
            if (password.length < 4) {{
                errorDiv.textContent = 'Password must be at least 4 characters.';
                errorDiv.style.display = 'block';
                return;
            }}

            if (password !== confirm) {{
                errorDiv.textContent = 'Passwords do not match.';
                errorDiv.style.display = 'block';
                return;
            }}

            errorDiv.style.display = 'none';
            config.admin_password = password;

            // Save database/redis URLs if in production mode
            config.database_url = document.getElementById('database_url').value || null;
            config.redis_url = document.getElementById('redis_url').value || null;

            nextStep();
        }}

        function selectMode(el, mode) {{
            document.querySelectorAll('.radio-option').forEach(o => o.classList.remove('selected'));
            el.classList.add('selected');
            config.deployment_mode = mode;

            // Show/hide advanced toggle (DB/Redis override behind toggle)
            const advancedToggle = document.getElementById('advanced-toggle');
            if (mode === 'production') {{
                advancedToggle.style.display = 'block';
            }} else {{
                advancedToggle.style.display = 'none';
                document.getElementById('advanced-fields').style.display = 'none';
                document.getElementById('advanced-arrow').innerHTML = '&#9654;';
            }}
        }}

        function toggleAdvanced() {{
            const fields = document.getElementById('advanced-fields');
            const arrow = document.getElementById('advanced-arrow');
            if (fields.style.display === 'none') {{
                fields.style.display = 'block';
                arrow.innerHTML = '&#9660;';
            }} else {{
                fields.style.display = 'none';
                arrow.innerHTML = '&#9654;';
            }}
        }}

        function nextStep() {{
            // Don't auto-advance from final step
            if (currentStep === 3) {{
                return;
            }}

            // Update step indicator
            document.querySelector(`.step-dot[data-step="${{currentStep}}"]`).classList.add('completed');
            document.querySelector(`.step-dot[data-step="${{currentStep}}"]`).classList.remove('active');

            currentStep++;

            document.querySelector(`.step-dot[data-step="${{currentStep}}"]`).classList.add('active');

            // Show new step
            document.querySelectorAll('.step').forEach(s => s.classList.remove('active'));
            document.querySelector(`.step[data-step="${{currentStep}}"]`).classList.add('active');

            // Populate review on step 3
            if (currentStep === 3) {{
                populateReview();
            }}
        }}

        function prevStep() {{
            document.querySelector(`.step-dot[data-step="${{currentStep}}"]`).classList.remove('active');
            document.querySelector(`.step-dot[data-step="${{currentStep}}"]`).classList.remove('completed');

            currentStep--;

            document.querySelector(`.step-dot[data-step="${{currentStep}}"]`).classList.add('active');
            document.querySelector(`.step-dot[data-step="${{currentStep}}"]`).classList.remove('completed');

            document.querySelectorAll('.step').forEach(s => s.classList.remove('active'));
            document.querySelector(`.step[data-step="${{currentStep}}"]`).classList.add('active');
        }}

        function generateToken(prefix) {{
            return prefix + '_' + Array.from(crypto.getRandomValues(new Uint8Array(16)))
                .map(b => b.toString(16).padStart(2, '0')).join('');
        }}

        function populateReview() {{
            // Generate admin token if not set
            if (!config.admin_token) {{
                config.admin_token = generateToken('admin');
            }}

            const review = document.getElementById('review-config');
            review.innerHTML = `
                <p><strong>Deployment Mode:</strong> ${{config.deployment_mode}}</p>
                <p><strong>Server:</strong> ${{config.server_hostname}}</p>
                ${{config.database_url ? `<p><strong>Database:</strong> ${{config.database_url.replace(/:[^:@]+@/, ':***@')}}</p>` : ''}}
                ${{config.redis_url ? `<p><strong>Redis:</strong> ${{config.redis_url}}</p>` : ''}}
                <p><strong>Admin Password:</strong> ******** (set)</p>
                <p><strong>Admin Token:</strong> <code style="background: #262626; padding: 2px 6px; border-radius: 4px; font-size: 0.75rem;">${{config.admin_token}}</code></p>
            `;
        }}

        async function completeSetup() {{
            // Show loading
            document.querySelectorAll('.step').forEach(s => s.classList.remove('active'));
            document.querySelector('.step[data-step="loading"]').classList.add('active');
            const loadingMsg = document.getElementById('loading-message');

            try {{
                loadingMsg.textContent = 'Saving configuration...';
                const response = await fetch('/setup/configure', {{
                    method: 'POST',
                    headers: {{ 'Content-Type': 'application/json' }},
                    body: JSON.stringify(config)
                }});

                const result = await response.json();

                if (result.status === 'ok') {{
                    // Config saved, server will restart
                    loadingMsg.textContent = 'Configuration saved! Server restarting...';

                    // Wait for server to come back up
                    await waitForServerRestart();

                    // Show success
                    document.querySelectorAll('.step').forEach(s => s.classList.remove('active'));
                    document.querySelector('.step[data-step="success"]').classList.add('active');
                    // Use current location (nginx proxies on port 80, so no port needed)
                    document.getElementById('final-host').textContent = window.location.host;
                    document.getElementById('final-host-2').textContent = window.location.host;
                }} else {{
                    alert('Setup failed: ' + (result.message || 'Unknown error'));
                    document.querySelectorAll('.step').forEach(s => s.classList.remove('active'));
                    document.querySelector('.step[data-step="3"]').classList.add('active');
                }}
            }} catch (err) {{
                // If fetch fails, server might have already restarted
                loadingMsg.textContent = 'Server restarting, please wait...';
                await waitForServerRestart();

                // Show success (assume it worked if server comes back)
                document.querySelectorAll('.step').forEach(s => s.classList.remove('active'));
                document.querySelector('.step[data-step="success"]').classList.add('active');
                // Use current location (nginx proxies on port 80, so no port needed)
                document.getElementById('final-host').textContent = window.location.host;
                document.getElementById('final-host-2').textContent = window.location.host;
            }}
        }}

        async function waitForServerRestart() {{
            // Poll health endpoint until server responds
            const maxAttempts = 30;
            const delayMs = 1000;

            for (let i = 0; i < maxAttempts; i++) {{
                try {{
                    const resp = await fetch('/health', {{ method: 'GET' }});
                    if (resp.ok) {{
                        // Server is back, wait a bit more for full startup
                        await new Promise(r => setTimeout(r, 1000));
                        return;
                    }}
                }} catch (e) {{
                    // Server not ready yet, continue polling
                }}
                await new Promise(r => setTimeout(r, delayMs));
            }}
            // Timeout - show success anyway, user can refresh
        }}
    </script>
</body>
</html>
    """)


async def trigger_restart():
    """
    Trigger application restart after a short delay.
    This allows the HTTP response to be sent before the process exits.
    Docker's restart policy will bring the container back up with new config.
    """
    await asyncio.sleep(2)  # Wait for response to be sent
    # Kill PID 1 (main container process) so Docker restarts the entire container.
    # Using os.getpid() only kills the worker, leaving the container "running" but unhealthy.
    os.kill(1, signal.SIGTERM)


@router.post("/configure")
async def configure(config: SetupConfig, background_tasks: BackgroundTasks):
    """
    Apply configuration from setup wizard.

    Note: Truck tokens are NOT generated here - they are created when
    vehicles are registered for events via the admin dashboard.
    """
    if not is_setup_mode():
        raise HTTPException(
            status_code=403,
            detail="Setup already completed. To reconfigure, set SETUP_COMPLETED=false in .env"
        )

    # Read existing env to preserve infrastructure settings
    existing_env = read_existing_env()

    # Generate admin token if not provided
    admin_token = config.admin_token or generate_token("admin")

    # Hash the admin password
    admin_password_hash = hash_password(config.admin_password)

    # Generate a secure secret key
    secret_key = secrets.token_hex(32)

    # Preserve DATABASE_URL and REDIS_URL from installer (container hostnames)
    # These are critical for Docker networking - the installer sets them to
    # postgres:5432 and redis:6379 (container names, not localhost)
    database_url = config.database_url or existing_env.get('DATABASE_URL', '')
    redis_url = config.redis_url or existing_env.get('REDIS_URL', '')

    # Build environment file content
    env_content = f"""# Argus Cloud Configuration
# Generated by Setup Wizard
# ===========================

# Setup complete flag
SETUP_COMPLETED=true

# Server
SERVER_HOST={config.server_hostname}
API_PORT={config.api_port}

# Deployment Mode
DEPLOYMENT_MODE={config.deployment_mode}

# Debug
DEBUG={str(config.enable_debug).lower()}
LOG_LEVEL={config.log_level}

# Security
SECRET_KEY={secret_key}
ADMIN_PASSWORD_HASH={admin_password_hash}

# Authentication (admin only - truck tokens created when vehicles registered)
ADMIN_TOKENS={admin_token}

# Rate Limiting
RATE_LIMIT_PUBLIC=100
RATE_LIMIT_TRUCKS=1000
"""

    # Always include database URL (from config, existing env, or default for containers)
    if database_url:
        env_content += f"\n# Database\nDATABASE_URL={database_url}\n"

    # Always include Redis URL (from config, existing env, or default for containers)
    if redis_url:
        env_content += f"\n# Redis\nREDIS_URL={redis_url}\n"

    # Write environment file
    env_path = ENV_FILE_PATH if ENV_FILE_PATH.exists() else LOCAL_ENV_PATH
    try:
        env_path.write_text(env_content)
        # Don't chmod 600 - container user needs to read it
        env_path.chmod(0o644)
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Failed to write configuration: {e}"
        )

    # Schedule restart AFTER response is sent
    # Docker's restart policy will bring the container back up with new config
    background_tasks.add_task(trigger_restart)

    return {
        "status": "ok",
        "message": "Configuration saved. Server will restart in 2 seconds.",
        "admin_token": admin_token,
        "restart_scheduled": True,
    }


@router.get("/tokens")
async def get_generated_tokens():
    """
    Get the tokens that were generated during setup.
    Only works if setup is complete and request includes admin token.
    """
    # This would require admin auth - placeholder for now
    raise HTTPException(
        status_code=501,
        detail="Token retrieval not implemented. Check your saved tokens from setup."
    )
