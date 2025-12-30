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


@app.route("/dump", methods=["GET", "POST", "PUT", "PATCH", "DELETE"])
def dump_json():
    """
    Receive a payload and write it to a file.

    Accepts any content type and HTTP method. JSON payloads are pretty-printed,
    form data is converted to JSON, other content types are saved as raw data.

    Returns the filename of the created file.
    """
    # Ensure data directory exists
    ensure_data_dir()

    content_type = request.content_type or "application/octet-stream"
    is_json_content = False
    is_form_data = False
    data = None
    raw_data = None

    # Try to parse as JSON if content type suggests it
    if request.is_json:
        try:
            data = request.get_json(force=False)
            is_json_content = True
        except Exception:
            pass

    # If not JSON, check for form data (application/x-www-form-urlencoded or multipart/form-data)
    if not is_json_content and request.form:
        data = {
            "_type": "form_data",
            "_method": request.method,
            "_content_type": content_type,
            "fields": dict(request.form)
        }
        # Include file metadata if present (not file contents for security)
        if request.files:
            data["files"] = {
                name: {
                    "filename": f.filename,
                    "content_type": f.content_type,
                    "size": f.content_length
                }
                for name, f in request.files.items()
            }
        is_form_data = True
        is_json_content = True  # We'll save it as JSON

    # Check for query parameters (useful for GET requests)
    if not is_json_content and not is_form_data and request.args:
        data = {
            "_type": "query_params",
            "_method": request.method,
            "_content_type": content_type,
            "params": dict(request.args)
        }
        is_json_content = True

    # If still nothing, try to parse raw body as JSON
    if not is_json_content and request.data:
        try:
            data = json.loads(request.data)
            is_json_content = True
        except (json.JSONDecodeError, UnicodeDecodeError):
            # Not JSON, treat as raw data
            raw_data = request.data

    # If we still have nothing, grab raw data
    if not is_json_content and not raw_data:
        raw_data = request.data

    # Determine what to save
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
    elif raw_data:
        # Save raw data
        filename = generate_filename("dat")
        filepath = DATA_DIR / filename
        try:
            with open(filepath, "wb") as f:
                f.write(raw_data)
            os.chmod(filepath, 0o640)
        except OSError as e:
            return jsonify({"error": f"Failed to write file: {str(e)}"}), 500
    else:
        return jsonify({"error": "Empty payload"}), 400

    return jsonify({
        "success": True,
        "filename": filename,
        "size": filepath.stat().st_size,
        "content_type": content_type,
        "method": request.method,
        "parsed_as_json": is_json_content,
        "was_form_data": is_form_data
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
