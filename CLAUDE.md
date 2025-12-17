# JSON Dump - Development Notes

## Project Overview
A simple web application that receives arbitrary JSON payloads via HTTP POST and writes them to files.

## Technology Stack Decision

**Chosen: Python + Flask + Gunicorn + Nginx**

### Rationale:
- **Flask**: Minimal framework, perfect for single-endpoint applications
- **Gunicorn**: Production-grade WSGI server, handles concurrency well
- **Nginx**: Reverse proxy for SSL termination, rate limiting, and static file serving
- **systemd**: Process management and auto-restart on failure

### Alternatives Considered:
- **Node.js/Express**: Also viable, but Python is more commonly pre-installed on servers
- **Go**: Would require compilation, overkill for this simple task
- **Django**: Too heavy for a single-endpoint app

## Architecture

```
[Client] --> [Nginx:80/443] --> [Gunicorn:8000] --> [Flask App] --> [File System]
```

## File Storage Strategy
- Files stored in `/var/lib/json_dump/` (production) or `./data/` (development)
- Filename format: `{timestamp}_{uuid}.json` for uniqueness and sortability
- Example: `20251217_143052_a1b2c3d4.json`

## API Endpoint
- `POST /dump` - Receives JSON payload, writes to file, returns filename

## Configuration
- Environment variables for configuration (12-factor app style)
- `JSON_DUMP_DIR`: Directory for storing JSON files
- `JSON_DUMP_MAX_SIZE`: Maximum payload size (default 1MB)

## Security Considerations
- Nginx handles rate limiting
- Maximum request body size enforced
- No authentication by default (add if needed for your use case)
- Files written with restrictive permissions (640)

## Development Commands
```bash
# Install dependencies
pip install -r requirements.txt

# Run development server
python app.py

# Run with Gunicorn (production-like)
gunicorn -c gunicorn.conf.py app:app
```

## Deployment Checklist
- [ ] Create system user for the service
- [ ] Create data directory with proper permissions
- [ ] Install Python dependencies in virtualenv
- [ ] Configure systemd service
- [ ] Configure Nginx reverse proxy
- [ ] Enable and start services
- [ ] Test endpoint

## Project Files

| File | Purpose |
|------|---------|
| `app.py` | Main Flask application |
| `gunicorn.conf.py` | Production Gunicorn settings |
| `requirements.txt` | Python dependencies |
| `README.md` | Full documentation with installation guide |
| `deploy/json_dump.service` | Systemd service file |
| `deploy/nginx_simple.conf` | Simple Nginx configuration |
| `deploy/nginx.conf` | Advanced Nginx configuration |
| `deploy/nginx_location.conf` | Reusable location block |

## Current Status
- **COMPLETE** - All components implemented and documented
- Ready for deployment

## Next Steps (if resuming work)
1. Test locally with `python app.py`
2. Deploy to server following README.md instructions
3. Add authentication if needed for public-facing deployment
4. Configure SSL with Let's Encrypt for HTTPS
