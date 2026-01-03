
---

# Secure API Key Handling (On-Demand Scripts)

**Standard Operating Procedure (SOP)**

## Purpose

This document defines the **standard, approved method** for storing and using API keys securely for **on-demand scripts** on Fedora systems.

This approach is intended for scenarios where:

* A script is run **infrequently and on demand**
* The script may use the API key **many times during execution**
* The script is **not a long-running service**
* Use of `sudo` is acceptable and appropriate
* The API key **must not be stored in plaintext**
* The API key **must not appear in Git repositories**
* We want to rely on **systemd-native tooling**, not custom crypto or password managers

---

## Design Summary (Authoritative)

**We store API keys encrypted at rest using systemd’s credential system and decrypt them on demand inside the script when run via `sudo`.**

### Key properties

* 🔐 **Encrypted at rest**
* 🔑 **No additional passwords or key systems**
* 🧠 **Plaintext exists only in process memory**
* 🧾 **Auditable via sudo**
* 🔁 **Reusable during execution**
* 🧹 **No services, no wrappers, no background processes**
* 🧑 **Simple mental model for engineers**

---

## High-Level Architecture

```
+-------------------------------+
| /etc/credstore.encrypted/     |
|   my_api_key                  |  <-- Encrypted at rest (root-only)
+---------------+---------------+
                |
                | sudo
                v
+-------------------------------+
| Python Script (on demand)     |
|                               |
| systemd-creds decrypt         |
|   -> plaintext in memory      |
|   -> cached for runtime       |
+-------------------------------+
```

---

## Security Model

* **Access control** is enforced by:

  * File permissions (`root:root`, `0600`)
  * `sudo` policy
* **Encryption** is provided by systemd:

  * Uses authenticated encryption
  * Bound to the local machine (TPM and/or system credential secret)
* **Threat model addressed**:

  * No plaintext secrets on disk
  * No secrets in source control
  * No secrets in environment files
  * No long-lived secret holders

---

### Credential Naming Convention (Mandatory)

systemd credentials enforce a strict naming rule:

> **The credential filename MUST exactly match the embedded credential name.**

This means:
- If the credential is created with `--name=codexkey`
- The file MUST be stored as: /etc/credstore.encrypted/codexkey
- **Do NOT** add extensions such as `.cred`, `.key`, or `.enc`
- using lowercase names is recommended for consistency with filenames

If the filename does not exactly match the embedded credential name,
`systemd-creds decrypt` will refuse to operate.

This is an intentional safety check that prevents accidental or ambiguous
credential loading.

---

## Step 1 — Store the API Key (Encrypted at Rest)

This is a **one-time setup**, repeated only when rotating the key.

### 1.1 Create the encrypted credential store (if not present)

```bash
sudo mkdir -p /etc/credstore.encrypted
sudo chmod 0700 /etc/credstore.encrypted
```

### 1.2 Encrypt the API key

**Preferred**
```bash
sudo systemd-ask-password "Enter API key:" \
  | sudo systemd-creds encrypt --name=my_api_key - \
    /etc/credstore.encrypted/my_api_key
```

**if currently stored unencrypted in a plaintext file*
```bash
sudo systemd-creds encrypt \
  --name=my_api_key \
  /home/myuser/insecurekey \
  /etc/credstore.encrypted/my_api_key
```

### 1.3 Lock down permissions

```bash
sudo chmod 0600 /etc/credstore.encrypted/my_api_key
sudo chown root:root /etc/credstore.encrypted/my_api_key
```

### Result

* The API key is encrypted at rest
* Only root can access or decrypt it
* Safe to back up (restore requires same machine credentials)

### Validation note

If decryption fails with an error indicating a name mismatch, verify that:
- The `--name` used during encryption exactly matches the filename
- No file extensions were added

Example:
```
--name=codexkey  →  /etc/credstore.encrypted/codexkey
```



---

## Step 2 — Use the API Key in an On-Demand Script

### 2.1 Design rules for scripts

All scripts that require API keys **MUST**:

1. Be run via `sudo`
2. Decrypt the key **once**
3. Cache the key **in memory**
4. Never write the key to disk
5. Never print or log the key

---

### 2.2 Reference Python implementation (approved pattern)

```python
import subprocess
from pathlib import Path
from functools import lru_cache

CRED_FILE = Path("/etc/credstore.encrypted/my_api_key")


def _decrypt_credential(path: Path) -> str:
    p = subprocess.Popen(
        ["systemd-creds", "decrypt", str(path)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    out, err = p.communicate()
    if p.returncode != 0:
        raise RuntimeError(f"Credential decryption failed: {err.strip()}")
    return out.strip()


@lru_cache(maxsize=1)
def load_api_key() -> str:
    if not CRED_FILE.exists():
        raise FileNotFoundError(f"Encrypted credential not found: {CRED_FILE}")
    return _decrypt_credential(CRED_FILE)
```

### Usage

```python
API_KEY = load_api_key()

# Safe to reuse API_KEY many times during execution
```

### Why this works

* Decryption happens **once per process**
* Plaintext key never touches disk
* Key is garbage-collected when the process exits
* Repeated API calls are efficient

---

## Step 3 — Run the Script

```bash
sudo python3 your_script.py
```

* Uses existing sudo authentication
* No additional passwords
* No prompts during execution
* Fully auditable

---

## Key Rotation Procedure

When the API key must be changed:

```bash
sudo systemd-ask-password "Enter NEW API key:" \
  | sudo systemd-creds encrypt --name=MY_API_KEY - \
    /etc/credstore.encrypted/my_api_key
```

No code changes required.
No service restarts required.

---

## Git Hygiene (Mandatory)

### Required rules

* **No secrets in source files**
* **No secrets in `.env` files**
* **No secrets in Git history**

### If a plaintext key was ever committed

1. **Rotate the key immediately**
2. **Rewrite Git history** (do not rely on deletion alone)

> Treat any committed key as compromised.

---

## When NOT to Use This Pattern

Do **not** use this SOP if:

* The script must run **without sudo**
* The key must be accessible to unprivileged users
* The key must be shared across machines
* The program is a long-running service (use `LoadCredentialEncrypted=` instead)

---

## Summary (Canonical)

> **For on-demand scripts requiring API keys, we store the key encrypted using systemd credentials in `/etc/credstore.encrypted`, decrypt it on demand under sudo using `systemd-creds decrypt`, and cache it in memory for the lifetime of the process.**

This is the **official, approved, and repeatable** approach for this class of problem.

---

