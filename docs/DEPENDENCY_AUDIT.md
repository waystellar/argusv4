# Dependency Audit - Argus v4.0

All dependencies use permissive licenses (MIT, Apache-2.0, BSD, ISC).
No GPL/AGPL dependencies included.

## Cloud Service (Python)

| Package | Version | License | Stars | Security Notes |
|---------|---------|---------|-------|----------------|
| fastapi | 0.109.2 | MIT | 77K | Active, well-maintained |
| uvicorn | 0.27.1 | BSD-3-Clause | 8K | ASGI server, production-ready |
| gunicorn | 21.2.0 | MIT | 9.7K | Process manager |
| asyncpg | 0.29.0 | Apache-2.0 | 7K | Fastest async Postgres driver |
| sqlalchemy | 2.0.25 | MIT | 9K | Industry standard ORM |
| alembic | 1.13.1 | MIT | 2.5K | Migration management |
| redis | 5.0.1 | MIT | 12K | Official Redis client |
| sse-starlette | 2.0.0 | BSD-3-Clause | 600 | SSE for FastAPI |
| pyjwt | 2.8.0 | MIT | 5K | JWT token handling |
| passlib | 1.7.4 | BSD | 1K | Password hashing |
| pydantic | 2.6.1 | MIT | 21K | Data validation |
| pydantic-settings | 2.1.0 | MIT | - | Settings management |
| gpxpy | 1.6.2 | Apache-2.0 | 1K | GPX parsing |
| structlog | 24.1.0 | Apache-2.0/MIT | 3.5K | Structured logging |
| prometheus-fastapi-instrumentator | 6.1.0 | ISC | 800 | Prometheus metrics |
| httpx | 0.26.0 | BSD-3-Clause | 13K | Async HTTP client |

## Web Frontend (JavaScript/TypeScript)

| Package | Version | License | Stars | Security Notes |
|---------|---------|---------|-------|----------------|
| react | 18.2.0 | MIT | 228K | UI framework |
| react-dom | 18.2.0 | MIT | - | React DOM bindings |
| react-router-dom | 6.22.0 | MIT | 53K | Client routing |
| maplibre-gl | 4.0.0 | BSD-3-Clause | 6.5K | Map rendering (no API key) |
| @mapbox/togeojson | 0.16.2 | ISC | 1.3K | GPX parsing |
| zustand | 4.5.0 | MIT | 47K | State management |
| @tanstack/react-query | 5.18.0 | MIT | 42K | Server state |
| vite | 5.1.0 | MIT | 70K | Build tool |
| tailwindcss | 3.4.1 | MIT | 82K | CSS framework |
| vite-plugin-pwa | 0.19.0 | MIT | 3K | PWA support |

## Edge Simulator (Python)

| Package | Version | License | Security Notes |
|---------|---------|---------|----------------|
| httpx | 0.26.0 | BSD-3-Clause | Async HTTP client |

## License Summary

- **MIT**: 18 packages
- **BSD-3-Clause/BSD**: 5 packages
- **Apache-2.0**: 4 packages
- **ISC**: 2 packages

**No GPL/AGPL dependencies.**

## Security Considerations

1. **No secrets in logs**: structlog configured to redact sensitive fields
2. **CORS**: Configurable allowed origins (no wildcards in production)
3. **Rate limiting**: Configurable per-IP limits
4. **Token security**: Truck tokens are 64-char hex (256 bits entropy)
5. **SQL injection**: All queries use parameterized statements via SQLAlchemy
6. **XSS**: React auto-escapes by default
7. **HTTPS**: Required in production (nginx TLS termination)

## Repo Health Indicators

All major dependencies have:
- Active maintenance (commits within last 3 months)
- Large community (>500 stars)
- Good documentation
- No known critical CVEs

## Update Policy

- Run `pip-audit` and `npm audit` before each release
- Update minor versions monthly
- Review major version upgrades quarterly
