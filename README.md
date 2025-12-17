# JSON Dump

A simple web application that receives arbitrary JSON payloads via HTTP POST and writes them to files.

## Features

- Accepts any valid JSON payload
- Writes each payload to a uniquely-named file
- Rate limiting via Nginx
- Systemd integration for process management
- Health check endpoint for monitoring

## Quick Start (Development)

```bash
# Create virtual environment
python3 -m venv venv
source venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Run development server
python app.py
```

Test it:
```bash
curl -X POST http://localhost:5000/dump \
  -H "Content-Type: application/json" \
  -d '{"hello": "world"}'
```

## API

### POST /dump

Receives a JSON payload and writes it to a file.

**Request:**
- Method: `POST`
- Content-Type: `application/json`
- Body: Any valid JSON

**Response (201 Created):**
```json
{
  "success": true,
  "filename": "20251217_143052_a1b2c3d4.json",
  "size": 42
}
```

**Errors:**
- `400` - Invalid JSON or missing Content-Type header
- `413` - Payload too large (default limit: 1MB)
- `429` - Rate limit exceeded
- `500` - Server error

### GET /health

Health check endpoint for load balancers and monitoring.

**Response (200 OK):**
```json
{
  "status": "healthy"
}
```

## Production Installation on Ubuntu/Debian with Nginx

### 1. Install System Dependencies

```bash
sudo apt update
sudo apt install -y python3 python3-venv python3-pip nginx
```

### 2. Create System User

```bash
sudo useradd --system --no-create-home --shell /usr/sbin/nologin json_dump
```

### 3. Create Application Directory

```bash
sudo mkdir -p /opt/json_dump
sudo chown json_dump:json_dump /opt/json_dump
```

### 4. Create Data Directory

```bash
sudo mkdir -p /var/lib/json_dump
sudo chown json_dump:json_dump /var/lib/json_dump
sudo chmod 750 /var/lib/json_dump
```

### 5. Deploy Application

```bash
# Copy application files
sudo cp app.py gunicorn.conf.py requirements.txt /opt/json_dump/

# Create virtual environment
sudo -u json_dump python3 -m venv /opt/json_dump/venv

# Install dependencies
sudo -u json_dump /opt/json_dump/venv/bin/pip install -r /opt/json_dump/requirements.txt
```

### 6. Configure Systemd

```bash
# Copy service file
sudo cp deploy/json_dump.service /etc/systemd/system/

# Reload systemd
sudo systemctl daemon-reload

# Enable and start service
sudo systemctl enable json_dump
sudo systemctl start json_dump

# Check status
sudo systemctl status json_dump
```

### 7. Configure Nginx

```bash
# Copy Nginx configuration
sudo cp deploy/nginx_simple.conf /etc/nginx/sites-available/json_dump

# Enable site
sudo ln -s /etc/nginx/sites-available/json_dump /etc/nginx/sites-enabled/

# Remove default site (optional)
sudo rm /etc/nginx/sites-enabled/default

# Test configuration
sudo nginx -t

# Reload Nginx
sudo systemctl reload nginx
```

### 8. Test the Installation

```bash
# Test health endpoint
curl http://localhost/health

# Test dump endpoint
curl -X POST http://localhost/dump \
  -H "Content-Type: application/json" \
  -d '{"test": "data", "timestamp": "2025-12-17"}'

# Check the saved files
sudo ls -la /var/lib/json_dump/
```

## Configuration

Environment variables (set in the systemd service file):

| Variable | Default | Description |
|----------|---------|-------------|
| `JSON_DUMP_DIR` | `./data` | Directory to store JSON files |
| `JSON_DUMP_MAX_SIZE` | `1048576` | Maximum payload size in bytes (1MB) |

## Monitoring

### View Logs

```bash
# Application logs
sudo journalctl -u json_dump -f

# Nginx access logs
sudo tail -f /var/log/nginx/access.log

# Nginx error logs
sudo tail -f /var/log/nginx/error.log
```

### Check Service Status

```bash
sudo systemctl status json_dump
```

### Restart Service

```bash
sudo systemctl restart json_dump
```

## Security Considerations

1. **Rate Limiting**: Nginx is configured to limit requests to 10/second per IP with a burst of 5
2. **File Permissions**: JSON files are written with `640` permissions (owner read/write, group read)
3. **Systemd Hardening**: Service runs with `NoNewPrivileges`, `PrivateTmp`, and `ProtectSystem=strict`
4. **No Authentication**: Add authentication if exposing to the public internet

### Adding Basic Authentication (Optional)

```bash
# Install apache2-utils for htpasswd
sudo apt install apache2-utils

# Create password file
sudo htpasswd -c /etc/nginx/.htpasswd username

# Add to Nginx location block:
# auth_basic "Restricted";
# auth_basic_user_file /etc/nginx/.htpasswd;
```

## SSL/TLS with Let's Encrypt (Recommended for Production)

```bash
# Install certbot
sudo apt install certbot python3-certbot-nginx

# Obtain certificate
sudo certbot --nginx -d your-domain.com

# Auto-renewal is configured automatically
```

## File Structure

```
json_dump/
├── app.py                    # Flask application
├── gunicorn.conf.py          # Gunicorn configuration
├── requirements.txt          # Python dependencies
├── README.md                 # This file
├── CLAUDE.md                 # Development notes
└── deploy/
    ├── json_dump.service     # Systemd service file
    ├── nginx_simple.conf     # Simple Nginx configuration
    ├── nginx.conf            # Advanced Nginx configuration
    └── nginx_location.conf   # Location block (for advanced config)
```

## Troubleshooting

### Service won't start

```bash
# Check logs
sudo journalctl -u json_dump -n 50

# Verify permissions
sudo ls -la /opt/json_dump/
sudo ls -la /var/lib/json_dump/
```

### 502 Bad Gateway

```bash
# Check if Gunicorn is running
sudo systemctl status json_dump

# Check if it's listening on the correct port
sudo ss -tlnp | grep 8000
```

### Permission Denied errors

```bash
# Fix ownership
sudo chown -R json_dump:json_dump /opt/json_dump
sudo chown -R json_dump:json_dump /var/lib/json_dump
```

## License

MIT License - Use freely for any purpose.
