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


def generate_filename(extension="json"):
    """Generate a unique filename with timestamp and UUID."""
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    unique_id = uuid.uuid4().hex[:8]
    return f"{timestamp}_{unique_id}.{extension}"


@app.route("/dump", methods=["POST"])
def dump_json():
    """
    Receive a payload and write it to a file.

    Accepts any content type. JSON payloads are pretty-printed,
    other content types are saved as raw data.

    Returns the filename of the created file.
    """
    # Ensure data directory exists
    ensure_data_dir()

    content_type = request.content_type or "application/octet-stream"
    is_json_content = False
    data = None

    # Try to parse as JSON if content type suggests it, or try anyway
    if request.is_json:
        try:
            data = request.get_json(force=False)
            is_json_content = True
        except Exception:
            pass

    # If not JSON content type, still try to parse as JSON (in case client didn't set header)
    if not is_json_content and request.data:
        try:
            data = json.loads(request.data)
            is_json_content = True
        except (json.JSONDecodeError, UnicodeDecodeError):
            pass

    if is_json_content and data is not None:
        # Save as pretty-printed JSON
        filename = generate_filename("json")
        filepath = DATA_DIR / filename
        try:
            with open(filepath, "w", encoding="utf-8") as f:
                json.dump(data, f, indent=2, ensure_ascii=False)
            os.chmod(filepath, 0o640)
        except OSError as e:
            return jsonify({"error": f"Failed to write file: {str(e)}"}), 500
    else:
        # Save raw data
        raw_data = request.data
        if not raw_data:
            return jsonify({"error": "Empty payload"}), 400

        filename = generate_filename("dat")
        filepath = DATA_DIR / filename
        try:
            with open(filepath, "wb") as f:
                f.write(raw_data)
            os.chmod(filepath, 0o640)
        except OSError as e:
            return jsonify({"error": f"Failed to write file: {str(e)}"}), 500

    return jsonify({
        "success": True,
        "filename": filename,
        "size": filepath.stat().st_size,
        "content_type": content_type,
        "parsed_as_json": is_json_content
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
