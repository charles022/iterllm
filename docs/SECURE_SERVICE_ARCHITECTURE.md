# Secure API Key Management: The "Hardened Job Server" Pattern

This document outlines the standard engineering approach for deploying applications that require access to sensitive API keys or credentials on Linux systems. This pattern ensures that secrets are encrypted at rest, never exposed to unprivileged users (including the developers themselves), and accessed only by a transient, sandboxed process.

## 1. Architectural Overview

The core concept is to decouple **Job Submission** from **Job Execution**.

*   **The User (Developer/Operator):** Can edit code and trigger jobs but **cannot** access the API keys.
*   **The Service (Job Server):** A background systemd daemon that holds the decrypted keys in a secure memory enclave. It listens for trigger signals and executes the application logic within a strict sandbox.

### Security Guarantees
1.  **Encryption at Rest:** Keys are encrypted using the machine's hardware TPM or unique machine ID.
2.  **Isolation:** The service runs as a `DynamicUser` (transient UID), meaning no persistent user on the system (not even the service owner) has access to the process memory or credentials.
3.  **Sandboxing:** The service sees a Read-Only filesystem, with explicit "holes" poked only for the project directory it needs to manage.

---

## 2. Implementation Guide

### A. Credential Storage
Secrets are managed via `systemd-creds`.

1.  **Encrypt the Key:**
    ```bash
    # Binds the key to this specific machine's hardware
    printf '%s' "$MY_SECRET_KEY" | sudo systemd-creds encrypt - /etc/credstore.encrypted/my_app_key
    ```

### B. Service Configuration (`.service` file)
The systemd unit acts as the "Secure Enclave."

**Key Directives:**
*   `Type=simple`: The service runs continuously in the background.
*   `DynamicUser=yes`: Assigns a randomized, unique UID/GID every time the service starts. This prevents the "developer" user from accessing the service's private data.
*   `LoadCredentialEncrypted=my_key:/etc/credstore.encrypted/my_app_key`: Decrypts the key into a private `tmpfs` RAM disk at runtime.
*   **Sandboxing:**
    *   `ProtectSystem=strict` (Read-only OS)
    *   `ProtectHome=yes` (Hide user home directories)
    *   `BindPaths=/path/to/project`: Explicitly grant access to the project folder.
    *   `PrivateTmp=yes` & `Environment=HOME=/tmp`: Isolate temporary files and caches.

### C. The Application "Server" Mode
The application must be designed to run as a **daemon** or **listener**.

1.  **Startup:**
    *   Read configuration.
    *   Load API Key from `$CREDENTIALS_DIRECTORY/my_key` (only visible to this process).
    *   Initialize resources (DB connections, API clients).
    *   **Listen:** Open a control interface (e.g., Unix Domain Socket, HTTP on localhost:XXXX, or a file watcher).

2.  **Execution Loop:**
    *   Wait for a "Job Request" from the client.
    *   Execute the logic (using the secure API key).
    *   Write results to the project's output directory.
    *   Return status/logs to the client.

### D. The Client "Trigger"
A lightweight CLI tool (or simple script) used by the developer.

1.  **Action:** Sends a command to the running service (e.g., `curl localhost:8080/run` or writes to a named pipe).
2.  **Permissions:** The developer has permission to talk to the socket/port, but *not* permission to read the Service's memory or credential files.

---

## 3. Workflow Example

1.  **Development:**
    *   Engineer edits source code in `/home/user/project/src`.
    *   Service (running in background) has read-access to these files via `BindPaths`.

2.  **Execution:**
    *   Engineer runs: `./trigger_job.sh`
    *   The trigger sends a signal to the Service.

3.  **Processing:**
    *   Service picks up the *latest* code/scripts.
    *   Service performs the task using the securely held API key.
    *   Service writes output to `/home/user/project/outputs`.

4.  **Result:**
    *   Engineer views the output files.
    *   **Crucial:** If the engineer tries to run the application directly (e.g., `python src/main.py`), it **fails** because the environment variable `CREDENTIALS_DIRECTORY` is missing or empty. Only the Service has the key.

---

## 4. File Permissions Strategy

Since the Service runs as a random UID (e.g., `61942`), it cannot inherently write to directories owned by the Developer (UID `1000`).

**Strategy:**
*   **Input (Code):** Developer owns files. Service has `Read` access (standard "Others" permission).
*   **Output (Logs/Results):**
    *   Create dedicated `outputs/` and `logs/` directories.
    *   Set permissions to allow "Others" to write: `chmod o+w outputs/`
    *   *Result:* Service creates files owned by UID `61942`. Developer can read them (standard "Others" read permission).
    *   *Cleanup:* Developer uses `sudo` to delete files if necessary, or a cleanup script triggered via the Service.

## 5. Summary Checklist

- [ ] **Secret:** Encrypted via `systemd-creds` (not in `.env`).
- [ ] **Service:** `DynamicUser=yes` enabled.
- [ ] **Access:** `LoadCredentialEncrypted` used.
- [ ] **Sandbox:** `ProtectSystem` and `ProtectHome` enabled; `BindPaths` used for project scope.
- [ ] **App Logic:** Refactored to listen for events (Server/Daemon mode).
- [ ] **FileSystem:** Output directories configured with `o+w` permissions.
