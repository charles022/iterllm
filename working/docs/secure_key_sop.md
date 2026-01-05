# Secure API Key Management Proposal

This document outlines the standard operating procedures for managing API keys securely using systemd native tooling. In all scenarios, keys are stored **encrypted at rest** and are never exposed in plaintext on the disk. Access is strictly controlled via `systemd-creds` and systemd unit configurations.

We identify three distinct patterns for API key access:

1.  **Interactive On-Demand Access:** For scripts run manually by an engineer (requires `sudo`).
2.  **Standard Service Access:** For background services starting at boot (automated decryption).
3.  **Isolated Service Access:** For services requiring maximum security isolation (using `DynamicUser`).

---

## 1. Interactive On-Demand Access

This approach is designed for maintenance scripts or administrative tools that run infrequently and require an API key.

### Characteristics
*   **Trigger:** Manual execution by a user.
*   **Privilege:** Requires `sudo` to decrypt the key.
*   **Lifetime:** Key exists in process memory only for the duration of the script.
*   **Storage:** Encrypted file in `/etc/credstore.encrypted/`.

### Setup Procedure
Store the key encrypted at rest. The filename **must** match the name used in the `--name` flag.

```bash
# 1. Create the credential store directory
sudo mkdir -p /etc/credstore.encrypted
sudo chmod 0700 /etc/credstore.encrypted

# 2. Encrypt the key (interactive input)
# Note: We use 'my_api_key' as the standard name across all examples.
sudo systemd-ask-password "Enter API Key:" \
  | sudo systemd-creds encrypt --name=my_api_key - \
    /etc/credstore.encrypted/my_api_key

# 3. Secure the file
sudo chmod 0600 /etc/credstore.encrypted/my_api_key
sudo chown root:root /etc/credstore.encrypted/my_api_key
```

### Access Implementation (Python Example)
This unified script works for both **interactive** (sudo) and **service** (automated) modes. It checks for the service-provided credentials directory first.

```python
import os
import subprocess
from pathlib import Path
from functools import lru_cache

CRED_NAME = "my_api_key"
CRED_FILE = Path(f"/etc/credstore.encrypted/{CRED_NAME}")

def _decrypt_credential(path: Path) -> str:
    # Decrypts the key using systemd-creds. Requires sudo.
    p = subprocess.Popen(
        ["systemd-creds", "decrypt", str(path), "-"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    out, err = p.communicate()
    if p.returncode != 0:
        raise RuntimeError(f"Decryption failed: {err.strip()}")
    return out.strip()

@lru_cache(maxsize=1)
def load_api_key() -> str:
    # 1. Try Standard Service Access (CREDENTIALS_DIRECTORY)
    creds_dir = os.environ.get("CREDENTIALS_DIRECTORY")
    if creds_dir:
        key_path = Path(creds_dir) / CRED_NAME
        if key_path.exists():
            return key_path.read_text().strip()

    # 2. Fallback to Interactive On-Demand Access
    if not CRED_FILE.exists():
        raise FileNotFoundError(f"Credential not found: {CRED_FILE}")
    return _decrypt_credential(CRED_FILE)

# Usage
if __name__ == "__main__":
    try:
        key = load_api_key()
        print("Key loaded successfully into memory.")
        # Proceed with logic using 'key'
    except Exception as e:
        print(f"Error: {e}")
```

---

## 2. Standard Service Access

This approach is for standard system services (like a custom web server or background worker) that need to start automatically at boot without user intervention.

### Characteristics
*   **Trigger:** System boot or `systemctl start`.
*   **Privilege:** `sudo` required only for service configuration/control. Runtime decryption is handled by systemd (PID 1).
*   **Lifetime:** Key is available as a read-only file in a temporary file system (`ramfs`) while the service is running.
*   **Isolation:** Uses `PrivateMounts=yes` to hide the key from other processes.

### Setup Procedure
(Refer to the "Setup Procedure" in Section 1 to create and encrypt the `my_api_key` credential.)

### Service Configuration
Edit the systemd unit file (e.g., `/etc/systemd/system/my_service.service`).

```ini
[Service]
# Point to the encrypted credential file
LoadCredentialEncrypted=my_api_key:/etc/credstore.encrypted/my_api_key

# Application binary
ExecStart=/usr/bin/python3 /opt/my_service/main.py

# Security: Ensure the credential mount is invisible to other processes
PrivateMounts=yes
```

### Access Implementation
(Use the unified Python implementation from Section 1. It automatically supports loading the key from the service environment.)

### Security Note
With `PrivateMounts=yes`, the `$CREDENTIALS_DIRECTORY` is visible **only** to the service process. Even a user logging in as `root` or the service user (e.g., `www-data`) in a different session will not see the files in `/run/credentials/...` because they reside in a separate mount namespace.

---

## 3. Isolated Service Access (DynamicUser)

This builds upon the Standard Service Access approach by adding complete user isolation. It is the recommended default for network-facing services that do not need to own persistent files.

### Characteristics
*   **Trigger:** System boot or `systemctl start`.
*   **Privilege:** Service runs as a **transient, unique User ID (UID)** allocated on the fly.
*   **Isolation:** Maximum. The service has no permanent identity and cannot access resources owned by other users (including standard users like `ubuntu` or `www-data`).

### Service Configuration
Add `DynamicUser=yes` to the unit file.

```ini
[Service]
# ... (Include all configuration from Section 2) ...

# Enable Dynamic User
DynamicUser=yes
```

### Why this is Superior
1.  **UID Isolation:** If the service is compromised, the attacker gains control of a UID that exists only for that specific process. This UID has no permissions to read files owned by `root`, `www-data`, or any other static user.
2.  **Anti-Sideways Movement:** In a standard setup, if two services run as `www-data`, compromising one allows access to the other's data. With `DynamicUser=yes`, every service instance gets a mathematically unique UID, preventing this "sideways" attack vector.

### Limitations
*   **Persistence:** Because the UID changes every time the service restarts, the service cannot easily own files on disk (e.g., it cannot write to `/var/lib/myservice` and expect to read it back after a restart unless `StateDirectory=` is explicitly configured).
*   **Usage:** Best for stateless workers, web servers, or API gateways.

---

## Summary Comparison

| Feature | Interactive (Approach 1) | Standard Service (Approach 2) | Isolated Service (Approach 3) |
| :--- | :--- | :--- | :--- |
| **Primary Use Case** | Admin Scripts / Maintenance | Databases / Stateful Apps | Web Servers / Stateless Apps |
| **Access Method** | `sudo` + `systemd-creds decrypt` | `LoadCredentialEncrypted` | `LoadCredentialEncrypted` |
| **User Identity** | Calling User (e.g., `chuck`) | Static (e.g., `www-data`) | Ephemeral (e.g., `run-u1234`) |
| **Filesystem View** | Host default | Private (`PrivateMounts`) | Private (`PrivateMounts`) |
| **Secrets on Disk** | **Encrypted** | **Encrypted** | **Encrypted** |
| **Secrets in Memory** | Process RAM | `ramfs` (tmpfs) | `ramfs` (tmpfs) |
