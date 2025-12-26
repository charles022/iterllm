import os

try:
    with os.fdopen(3, "r") as f:
        API_KEY = f.read().strip()
except OSError as e:
    raise RuntimeError(
        "API key FD not available. Launch via run_with_api_key_fd.sh "
        "(or provide OPENAI_API_KEY via environment)."
    ) from e

if not API_KEY:
    raise RuntimeError("API key was empty")

