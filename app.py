"""
JSON Dump - A simple web application that receives JSON payloads and writes them to files.
"""

import json
import os
import uuid
from datetime import datetime
from pathlib import Path

from flask import Flask, request, jsonify

app = Flask(__name__)

# Configuration from environment variables with sensible defaults
DATA_DIR = Path(os.environ.get("JSON_DUMP_DIR", "./data"))
MAX_CONTENT_LENGTH = int(os.environ.get("JSON_DUMP_MAX_SIZE", 1024 * 1024))  # 1MB default

# Set Flask's max content length
app.config["MAX_CONTENT_LENGTH"] = MAX_CONTENT_LENGTH


def ensure_data_dir():
    """Create the data directory if it doesn't exist."""
    DATA_DIR.mkdir(parents=True, exist_ok=True)


def generate_filename():
    """Generate a unique filename with timestamp and UUID."""
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    unique_id = uuid.uuid4().hex[:8]
    return f"{timestamp}_{unique_id}.json"


@app.route("/dump", methods=["POST"])
def dump_json():
    """
    Receive a JSON payload and write it to a file.

    Returns the filename of the created file.
    """
    # Check content type
    if not request.is_json:
        return jsonify({"error": "Content-Type must be application/json"}), 400

    # Get the JSON data
    try:
        data = request.get_json(force=False)
    except Exception as e:
        return jsonify({"error": f"Invalid JSON: {str(e)}"}), 400

    if data is None:
        return jsonify({"error": "Empty or invalid JSON payload"}), 400

    # Ensure data directory exists
    ensure_data_dir()

    # Generate filename and write
    filename = generate_filename()
    filepath = DATA_DIR / filename

    try:
        with open(filepath, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2, ensure_ascii=False)

        # Set restrictive permissions (owner read/write, group read)
        os.chmod(filepath, 0o640)

    except OSError as e:
        return jsonify({"error": f"Failed to write file: {str(e)}"}), 500

    return jsonify({
        "success": True,
        "filename": filename,
        "size": filepath.stat().st_size
    }), 201


@app.route("/health", methods=["GET"])
def health_check():
    """Health check endpoint for monitoring."""
    return jsonify({"status": "healthy"}), 200


@app.errorhandler(413)
def request_entity_too_large(error):
    """Handle payload too large errors."""
    return jsonify({
        "error": f"Payload too large. Maximum size is {MAX_CONTENT_LENGTH} bytes"
    }), 413


@app.errorhandler(500)
def internal_error(error):
    """Handle internal server errors."""
    return jsonify({"error": "Internal server error"}), 500


if __name__ == "__main__":
    ensure_data_dir()
    # Development server only - use Gunicorn in production
    app.run(host="127.0.0.1", port=5000, debug=True)
