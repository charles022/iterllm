# Implementation Plan: API Key Integration and Configuration Refactor

**Date:** December 21, 2025
**Subject:** Response to Directive for Refactoring API Key Integration

## 1. Proposed Code Structure

We will refactor `src/orchestrator.py` to decouple configuration loading from application logic and adhere to the strict security requirements.

### 1.1 Configuration Loader
We will introduce a lightweight function, `load_configuration(env_path: Path)`, to parse the JSON-formatted configuration file. This centralizes all external settings.

```python
def load_configuration(env_path: Path) -> dict[str, str]:
    """Loads configuration from a JSON formatted .env file."""
    if not env_path.exists():
        raise FileNotFoundError(f"Configuration file not found: {env_path}")
    try:
        with env_path.open("r", encoding="utf-8") as f:
            return json.load(f)
    except json.JSONDecodeError as e:
        raise RuntimeError(f"Failed to parse configuration file: {e}")
```

### 1.2 Updated API Key Retrieval
The logic from `notes/how_to_get_api_key.py` will be integrated directly into `orchestrator.py`. Crucially, we will remove the hardcoded `CRED_FILE` constant. The `load_api_key` function will accept the path from our loaded configuration.

```python
@lru_cache(maxsize=1)
def load_api_key(credential_path: str) -> str:
    path = Path(credential_path)
    if not path.exists():
        raise FileNotFoundError(f"Encrypted credential not found: {path}")
    return _decrypt_credential(path)
```

### 1.3 Execution Flow Update
The `main` function will be updated to:
1.  Load the configuration immediately upon startup.
2.  Pass configuration values to `build_arg_parser` to set default arguments (replacing `os.getenv`).
3.  Retrieve the API key using the configured path.

## 2. Configuration Strategy

**Selected Approach:** Option B (JSON)

**Proposed Content for `src/.env`:**
```json
{
  "CREDENTIAL_PATH": "/etc/credstore.encrypted/codex_key",
  "INTERLLM_MODEL": "gpt-5-codex",
  "INTERLLM_REASONING_EFFORT": "medium"
}
```

**Rationale:**
*   **Robustness:** Python's native `json` library handles parsing edge cases (whitespace, special characters) far more reliably than a custom key-value parser.
*   **Zero Dependencies:** This approach requires no external libraries (like `python-dotenv`), keeping our `requirements.txt` lean.
*   **Performance:** `json.load` is highly optimized.

## 3. Impact Analysis

Modifications will be targeted to the following files:

*   **`src/orchestrator.py`**:
    *   **Remove:** `os.getenv` calls, hardcoded `CRED_FILE` path.
    *   **Add:** `load_configuration` function.
    *   **Modify:** `load_api_key` (to accept path arg), `build_arg_parser` (to accept defaults dict), `main` (wiring).
*   **`src/.env`**:
    *   **Rewrite:** Convert from shell-style key-value pairs to a valid JSON object.
*   **`README.md`**:
    *   **Update:** Documentation will be updated to reflect the new reliance on `src/.env` for configuration and the ability to customize the credential path.

## 4. Refactoring Opportunities

During the review, we identified specific improvements to ensure code quality and correctness:

1.  **Critical Bug Fix:** The reference logic in `notes/how_to_get_api_key.py` (and the current `orchestrator.py`) contains a `SyntaxError`. The `subprocess.Popen` call is missing a comma after the arguments list. This prevents execution and will be fixed during migration.
    *   *Current:* `["systemd-creds", "decrypt", str(path)] stdout=subprocess.PIPE`
    *   *Fix:* `["systemd-creds", "decrypt", str(path)], stdout=subprocess.PIPE`
2.  **Parser Decoupling:** We will refactor `build_arg_parser` to accept a dictionary of defaults rather than reading from global environment variables. This makes the function deterministic and testable.
3.  **Explicit Error Handling:** We will add specific error handling for the configuration loading step to provide clear user feedback if the `.env` file is missing or malformed.
