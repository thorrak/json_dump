#!/bin/bash
#
# JSON Dump - Installation Script
#
# This script performs a complete installation of the JSON Dump application
# on a fresh Debian/Ubuntu server. Run as root.
#
# Usage: ./install.sh
#

set -euo pipefail

#=============================================================================
# CONFIGURATION
#=============================================================================

# Git repository URL - modify this to point to your repository
REPO_URL="https://github.com/thorrak/json_dump.git"
REPO_BRANCH="main"

# Installation paths
APP_DIR="/opt/json_dump"
DATA_DIR="/var/lib/json_dump"

# Service user
SERVICE_USER="json_dump"
SERVICE_GROUP="json_dump"

# Application settings
MAX_PAYLOAD_SIZE="1048576"  # 1MB in bytes

#=============================================================================
# UTILITY FUNCTIONS
#=============================================================================

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

log_step() {
    echo -e "\n${CYAN}${BOLD}==> $1${NC}"
}

# Error handler
on_error() {
    local line_no=$1
    local error_code=$2
    log_error "Installation failed at line ${line_no} with error code ${error_code}"
    log_error "Please check the output above for details."
    exit 1
}

trap 'on_error ${LINENO} $?' ERR

#=============================================================================
# PREREQUISITE CHECKS
#=============================================================================

check_prerequisites() {
    log_step "Checking prerequisites"

    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
    log_success "Running as root"

    # Check if Debian/Ubuntu
    if [[ ! -f /etc/debian_version ]]; then
        log_error "This script only supports Debian/Ubuntu systems"
        exit 1
    fi
    log_success "Detected Debian/Ubuntu system"

    # Check for required commands
    for cmd in apt-get systemctl; do
        if ! command -v "$cmd" &> /dev/null; then
            log_error "Required command '$cmd' not found"
            exit 1
        fi
    done
    log_success "Required system commands available"

    # Check network connectivity
    if ! ping -c 1 -W 5 8.8.8.8 &> /dev/null; then
        log_warning "Network connectivity check failed (ping to 8.8.8.8)"
        log_warning "Continuing anyway, but package installation may fail"
    else
        log_success "Network connectivity verified"
    fi

    # Validate repository URL is configured
    if [[ "$REPO_URL" == *"your-username"* ]]; then
        log_error "Repository URL contains placeholder 'your-username'"
        log_error "Please edit REPO_URL at the top of this script"
        log_error "Current value: $REPO_URL"
        exit 1
    fi
    log_success "Repository URL configured"
}

#=============================================================================
# PACKAGE INSTALLATION
#=============================================================================

install_packages() {
    log_step "Installing system packages"

    log_info "Updating package lists..."
    apt-get update -qq

    log_info "Installing required packages..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
        python3 \
        python3-venv \
        python3-pip \
        nginx \
        git \
        curl \
        > /dev/null

    log_success "System packages installed"

    # Verify installations
    log_info "Verifying installations..."
    python3 --version
    nginx -v 2>&1 | head -1
    git --version

    log_success "All packages verified"
}

#=============================================================================
# USER AND DIRECTORY SETUP
#=============================================================================

create_service_user() {
    log_step "Creating service user and group"

    # Create group if it doesn't exist
    if ! getent group "$SERVICE_GROUP" &>/dev/null; then
        groupadd --system "$SERVICE_GROUP"
        log_success "Created system group '$SERVICE_GROUP'"
    else
        log_info "Group '$SERVICE_GROUP' already exists"
    fi

    # Create user if it doesn't exist
    if id "$SERVICE_USER" &>/dev/null; then
        log_info "User '$SERVICE_USER' already exists"
    else
        useradd --system --no-create-home --shell /usr/sbin/nologin -g "$SERVICE_GROUP" "$SERVICE_USER"
        log_success "Created system user '$SERVICE_USER'"
    fi
}

setup_directories() {
    log_step "Setting up directories"

    # Application directory
    if [[ -d "$APP_DIR" ]]; then
        log_warning "Application directory $APP_DIR already exists"
        log_info "Backing up to ${APP_DIR}.backup.$(date +%Y%m%d%H%M%S)"
        mv "$APP_DIR" "${APP_DIR}.backup.$(date +%Y%m%d%H%M%S)"
    fi
    mkdir -p "$APP_DIR"
    log_success "Created application directory: $APP_DIR"

    # Data directory
    if [[ ! -d "$DATA_DIR" ]]; then
        mkdir -p "$DATA_DIR"
        log_success "Created data directory: $DATA_DIR"
    else
        log_info "Data directory already exists: $DATA_DIR"
    fi

    # Set ownership
    chown "$SERVICE_USER:$SERVICE_GROUP" "$APP_DIR"
    chown "$SERVICE_USER:$SERVICE_GROUP" "$DATA_DIR"
    chmod 750 "$DATA_DIR"

    log_success "Directory permissions configured"
}

#=============================================================================
# APPLICATION DEPLOYMENT
#=============================================================================

clone_repository() {
    log_step "Cloning application repository"

    log_info "Cloning from: $REPO_URL (branch: $REPO_BRANCH)"

    # Clone to a temporary location first
    local temp_dir
    temp_dir=$(mktemp -d)

    if ! git clone --depth 1 --branch "$REPO_BRANCH" "$REPO_URL" "$temp_dir" 2>&1; then
        log_error "Failed to clone repository from $REPO_URL"
        rm -rf "$temp_dir"
        exit 1
    fi

    # Verify required files exist
    for file in app.py gunicorn.conf.py requirements.txt; do
        if [[ ! -f "$temp_dir/$file" ]]; then
            log_error "Required file '$file' not found in repository"
            rm -rf "$temp_dir"
            exit 1
        fi
    done

    # Copy application files
    cp "$temp_dir/app.py" "$APP_DIR/"
    cp "$temp_dir/gunicorn.conf.py" "$APP_DIR/"
    cp "$temp_dir/requirements.txt" "$APP_DIR/"

    # Cleanup
    rm -rf "$temp_dir"

    # Set ownership
    chown -R "$SERVICE_USER:$SERVICE_GROUP" "$APP_DIR"

    log_success "Application files deployed to $APP_DIR"

    # List deployed files
    log_info "Deployed files:"
    ls -la "$APP_DIR/"
}

setup_python_environment() {
    log_step "Setting up Python environment"

    log_info "Creating virtual environment..."
    python3 -m venv "$APP_DIR/venv"
    log_success "Virtual environment created"

    log_info "Installing Python dependencies..."
    "$APP_DIR/venv/bin/pip" install --quiet --upgrade pip
    "$APP_DIR/venv/bin/pip" install --quiet -r "$APP_DIR/requirements.txt"
    log_success "Python dependencies installed"

    # Verify Flask and Gunicorn
    log_info "Verifying Python packages..."
    "$APP_DIR/venv/bin/python" -c "import flask; print(f'Flask {flask.__version__}')"
    "$APP_DIR/venv/bin/gunicorn" --version

    # Set ownership
    chown -R "$SERVICE_USER:$SERVICE_GROUP" "$APP_DIR/venv"

    log_success "Python environment ready"
}

#=============================================================================
# SYSTEMD CONFIGURATION
#=============================================================================

configure_systemd() {
    log_step "Configuring systemd service"

    cat > /etc/systemd/system/json_dump.service << EOF
[Unit]
Description=JSON Dump Web Application
After=network.target

[Service]
Type=exec
User=${SERVICE_USER}
Group=${SERVICE_GROUP}

# Application directory
WorkingDirectory=${APP_DIR}

# Environment variables
Environment="JSON_DUMP_DIR=${DATA_DIR}"
Environment="JSON_DUMP_MAX_SIZE=${MAX_PAYLOAD_SIZE}"

# Start command
ExecStart=${APP_DIR}/venv/bin/gunicorn -c gunicorn.conf.py app:app

# Reload command (graceful restart)
ExecReload=/bin/kill -s HUP \$MAINPID

# Stop command
ExecStop=/bin/kill -s TERM \$MAINPID

# Restart policy
Restart=on-failure
RestartSec=5

# Security hardening
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=${DATA_DIR}

# Resource limits
LimitNOFILE=65536

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=json_dump

[Install]
WantedBy=multi-user.target
EOF

    log_success "Systemd service file created"

    # Reload systemd
    systemctl daemon-reload
    log_success "Systemd daemon reloaded"

    # Enable service
    systemctl enable json_dump --quiet
    log_success "Service enabled for auto-start"

    # Start service
    log_info "Starting json_dump service..."
    systemctl start json_dump

    # Wait for service to be ready
    sleep 2

    # Verify service is running
    if systemctl is-active --quiet json_dump; then
        log_success "Service is running"
        systemctl status json_dump --no-pager | head -10
    else
        log_error "Service failed to start"
        journalctl -u json_dump --no-pager -n 20
        exit 1
    fi
}

#=============================================================================
# NGINX CONFIGURATION
#=============================================================================

configure_nginx() {
    log_step "Configuring Nginx"

    # Create Nginx configuration
    cat > /etc/nginx/sites-available/json_dump << 'EOF'
# JSON Dump - Nginx Configuration
# Rate limiting zone - 10 requests per second per IP
limit_req_zone $binary_remote_addr zone=json_dump_limit:10m rate=10r/s;

server {
    listen 80;
    server_name _;

    # Maximum request body size
    client_max_body_size 1m;

    # Security headers
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "DENY" always;

    # Health check endpoint (no rate limiting)
    location /health {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # Main dump endpoint with rate limiting
    location /dump {
        # Apply rate limiting - burst of 5 requests, no delay
        limit_req zone=json_dump_limit burst=5 nodelay;
        limit_req_status 429;

        # Only allow POST method
        if ($request_method !~ ^(POST)$) {
            return 405;
        }

        # Proxy to Gunicorn
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # Timeouts
        proxy_connect_timeout 10s;
        proxy_send_timeout 30s;
        proxy_read_timeout 30s;
    }

    # Deny all other paths
    location / {
        return 404;
    }
}
EOF

    log_success "Nginx configuration created"

    # Enable site
    if [[ -L /etc/nginx/sites-enabled/json_dump ]]; then
        rm /etc/nginx/sites-enabled/json_dump
    fi
    ln -s /etc/nginx/sites-available/json_dump /etc/nginx/sites-enabled/
    log_success "Site enabled"

    # Remove default site if it exists
    if [[ -L /etc/nginx/sites-enabled/default ]]; then
        rm /etc/nginx/sites-enabled/default
        log_info "Removed default Nginx site"
    fi

    # Test configuration
    log_info "Testing Nginx configuration..."
    if nginx -t 2>&1; then
        log_success "Nginx configuration is valid"
    else
        log_error "Nginx configuration test failed"
        exit 1
    fi

    # Start or reload Nginx
    if systemctl is-active --quiet nginx; then
        systemctl reload nginx
        log_success "Nginx reloaded"
    else
        systemctl start nginx
        log_success "Nginx started"
    fi
}

#=============================================================================
# VERIFICATION
#=============================================================================

verify_installation() {
    log_step "Verifying installation"

    local all_passed=true

    # Check service status
    log_info "Checking service status..."
    if systemctl is-active --quiet json_dump; then
        log_success "json_dump service is running"
    else
        log_error "json_dump service is not running"
        all_passed=false
    fi

    if systemctl is-active --quiet nginx; then
        log_success "nginx service is running"
    else
        log_error "nginx service is not running"
        all_passed=false
    fi

    # Check port bindings
    log_info "Checking port bindings..."
    if ss -tlnp | grep -q ':8000'; then
        log_success "Gunicorn is listening on port 8000"
    else
        log_error "Gunicorn is not listening on port 8000"
        all_passed=false
    fi

    if ss -tlnp | grep -q ':80'; then
        log_success "Nginx is listening on port 80"
    else
        log_error "Nginx is not listening on port 80"
        all_passed=false
    fi

    # Test endpoints
    log_info "Testing API endpoints..."
    sleep 1  # Brief wait for services to be fully ready

    # Health endpoint
    local health_response
    health_response=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1/health 2>/dev/null || echo "000")
    if [[ "$health_response" == "200" ]]; then
        log_success "Health endpoint returned 200 OK"
    else
        log_error "Health endpoint returned $health_response (expected 200)"
        all_passed=false
    fi

    # Dump endpoint
    local dump_response
    dump_response=$(curl -s -X POST http://127.0.0.1/dump \
        -H "Content-Type: application/json" \
        -d '{"test": "installation_verification", "timestamp": "'$(date -Iseconds)'"}' 2>/dev/null)

    if echo "$dump_response" | grep -q '"success": true'; then
        log_success "Dump endpoint working correctly"
        local filename
        filename=$(echo "$dump_response" | grep -o '"filename": "[^"]*"' | cut -d'"' -f4)
        log_info "Test file created: $filename"
    else
        log_error "Dump endpoint test failed"
        log_error "Response: $dump_response"
        all_passed=false
    fi

    # Check data directory
    log_info "Checking data directory..."
    local file_count
    file_count=$(find "$DATA_DIR" -name "*.json" -type f | wc -l)
    log_info "JSON files in data directory: $file_count"

    if [[ "$all_passed" == true ]]; then
        return 0
    else
        return 1
    fi
}

#=============================================================================
# SUMMARY
#=============================================================================

print_summary() {
    echo ""
    echo -e "${GREEN}${BOLD}=============================================${NC}"
    echo -e "${GREEN}${BOLD}  Installation Complete!${NC}"
    echo -e "${GREEN}${BOLD}=============================================${NC}"
    echo ""
    echo -e "${BOLD}Application Details:${NC}"
    echo "  - App Directory:  $APP_DIR"
    echo "  - Data Directory: $DATA_DIR"
    echo "  - Service User:   $SERVICE_USER"
    echo ""
    echo -e "${BOLD}Endpoints:${NC}"
    echo "  - Health Check:   http://<server-ip>/health"
    echo "  - JSON Dump:      POST http://<server-ip>/dump"
    echo ""
    echo -e "${BOLD}Useful Commands:${NC}"
    echo "  - View logs:      journalctl -u json_dump -f"
    echo "  - Restart app:    systemctl restart json_dump"
    echo "  - Check status:   systemctl status json_dump"
    echo "  - View files:     ls -la $DATA_DIR"
    echo ""
    echo -e "${BOLD}Test with:${NC}"
    echo "  curl -X POST http://localhost/dump \\"
    echo "    -H 'Content-Type: application/json' \\"
    echo "    -d '{\"hello\": \"world\"}'"
    echo ""
}

#=============================================================================
# MAIN
#=============================================================================

main() {
    echo ""
    echo -e "${CYAN}${BOLD}=============================================${NC}"
    echo -e "${CYAN}${BOLD}  JSON Dump - Installation Script${NC}"
    echo -e "${CYAN}${BOLD}=============================================${NC}"
    echo ""
    echo "Repository: $REPO_URL"
    echo "Target:     $APP_DIR"
    echo ""

    check_prerequisites
    install_packages
    create_service_user
    setup_directories
    clone_repository
    setup_python_environment
    configure_systemd
    configure_nginx

    if verify_installation; then
        print_summary
        exit 0
    else
        log_error "Installation completed with errors. Please review the output above."
        exit 1
    fi
}

# Run main function
main "$@"
