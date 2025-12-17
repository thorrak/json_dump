# Gunicorn configuration file for JSON Dump

import multiprocessing

# Bind to localhost only - Nginx will proxy requests
bind = "127.0.0.1:8000"

# Worker configuration
# Rule of thumb: 2-4 workers per core
workers = multiprocessing.cpu_count() * 2 + 1

# Worker class - sync is fine for I/O-bound file writes
worker_class = "sync"

# Timeout for worker processes (seconds)
timeout = 30

# Graceful timeout for worker restart
graceful_timeout = 10

# Maximum requests per worker before restart (prevents memory leaks)
max_requests = 1000
max_requests_jitter = 50

# Logging
accesslog = "-"  # stdout
errorlog = "-"   # stderr
loglevel = "info"

# Process naming
proc_name = "json_dump"

# Security: don't expose server header
forwarded_allow_ips = "127.0.0.1"

# Preload app for faster worker spawning (uses more memory but faster restarts)
preload_app = True
