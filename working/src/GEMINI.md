# iterllm-v3

This project provides a secure, containerized service setup for `iterllm`, utilizing Podman and Systemd. It features a nested build process where a developer container builds a minimal runtime container.

## Project Structure

*   **`src/build_image.sh`**: The main build script. It creates a "dev" image containing build tools (`buildah`), which is then used to build the "runtime" image. This ensures a clean and reproducible build environment.
*   **`src/build_runtime_image.sh`**: The inner build script executed *inside* the dev container. It constructs the minimal runtime image (based on `scratch`, adding only `bash` and dependencies).
*   **`src/build_service.sh`**: Deploys the application as a systemd user service. It handles unit file generation, environment configuration, and service activation.
*   **`src/iterllm.service.template`**: Systemd unit template used by `build_service.sh`. It configures secure execution, including `LoadCredentialEncrypted` for passing API keys.

## Prerequisites

*   **Podman**: For running containers.
*   **Buildah**: For building container images.
*   **Git**: For version control and project naming.
*   **Systemd**: For service management.

## Building and Running

### 1. Build the Images

Run the build script to create both the developer and runtime images:

```bash
./src/build_image.sh
```

**Options:**
*   `--skip_rebuild`: Skips rebuilding the dev container if it already exists (useful for faster iteration).
*   `--copy-system`: Copies the resulting runtime image to system-wide storage (requires `sudo`).

### 2. Configure Credentials

The service expects an encrypted credential file. Ensure you have created it using `systemd-creds`:

```bash
# Example (see docs/secure_key_sop.md for details)
systemd-creds encrypt --name=my_api_key - ~/.config/credstore.encrypted/my_api_key
```

### 3. Deploy Service

Deploy the systemd user service:

```bash
./src/build_service.sh
```

This script will:
*   Verify prerequisites (podman, runtime image, credentials).
*   Generate the service unit file in `~/.config/systemd/user/`.
*   Reload systemd and start the service.

## Development Conventions

*   **Naming:** Image and service names are dynamically generated based on the Git repository name and current branch (e.g., `iterllm-v3-main-runtime-image`).
*   **Security:**
    *   **Minimal Runtime:** The runtime image is built `from scratch` to minimize attack surface.
    *   **Encrypted Credentials:** API keys are never stored in plain text in the image or environment variables; they are injected via `LoadCredentialEncrypted`.
    *   **Rootless:** The entire build and runtime process is designed to work with rootless Podman (user mode).
*   **Testing:** The `build_image.sh` script includes a basic test that runs the runtime container to verify it works.
