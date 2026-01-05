Plan: Secure Systemd Service for IterLLM

1.  **Analyze Prerequisites**:
    *   Current runtime image (`src/build_runtime_image.sh`) contains only `bash`.
    *   SOP (`docs/secure_key_sop.md`) requires `DynamicUser=yes` and encrypted credentials.
    *   Missing: The Python environment or application code in the image.
    *   **Decision**: The service script will use the existing image but override the command to a "verification loop" (checking for the key) to demonstrate success until the app is ready.

2.  **Develop `src/build_service.sh`**:
    *   **Purpose**: A standalone script to generate the systemd unit and start the service.
    *   **Key Features**:
        *   **Security**: Enforce `DynamicUser=yes`, `PrivateMounts=yes`, and `LoadCredentialEncrypted`.
        *   **Credential Handling**: Since `DynamicUser` creates a transient namespace, we must strictly map the decrypted credential (provided by systemd in `$CREDENTIALS_DIRECTORY`) into the container via a volume mount.
        *   **Performance**: Use `podman run --replace --rm` to ensure clean startups and shutdowns. Use systemd cgroup management.
    *   **Unit File Template**:
        ```ini
        [Unit]
        Description=IterLLM Runtime Service
        After=network-online.target

        [Service]
        Type=exec
        DynamicUser=yes
        LoadCredentialEncrypted=my_api_key:/etc/credstore.encrypted/my_api_key
        
        # Pass the decrypted credential path to the container
        ExecStart=/bin/sh -c '/usr/bin/podman run \
            --name iterllm-runtime \
            --replace \
            --rm \
            --cgroup-manager=systemd \
            -v ${CREDENTIALS_DIRECTORY}/my_api_key:/run/secrets/my_api_key:ro \
            iterllm-v3-working-runtime-image:latest \
            /bin/bash -c "if [ -f /run/secrets/my_api_key ]; then echo Key found; else echo Key missing; fi; sleep infinity"'
        
        [Install]
        WantedBy=multi-user.target
        ```

3.  **Execution Steps**:
    *   Create `src/build_service.sh`.
    *   Make it executable.
    *   (Optional) If you have the encrypted key ready, we can test it. If not, the script will warn/fail gracefully.

I will now create the `src/build_service.sh` script following this plan.

```