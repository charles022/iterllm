## Updated Project Todo List

---

### 1. Image and Container Scripts

* **`image_build_script.sh`**
* Use `buildah` to build an image from scratch.
* **Inclusion:** Copy required repo files/scripts into the container.
* **Mounting:** Configure to mount the current working directory (`$PWD`) for development.
* **Portability:** Ensure mount points can be updated for service-level execution.


* **`run_container_from_image.sh`**
* Initialize/build a new container instance from the local image.
* Execute the startup sequence and enter the container shell.


* **`run_existing_container.sh`**
* Check for a currently running or stopped container.
* Restart and/or enter the existing container if available.



---

### 2. Core Logic and Task Management

* **`main` script**
* **Preprocessing:** Pass input through a light model to generate:
1. A uniform task list (line-separated text document).
2. A uniform prompt string with a placeholder for task insertion.


* **Execution:** Initialize a new "codex task" for every item in the task list.


* **Git Workflow Integration**
* **Sync:** Commit all local changes, then pull the repo from origin to the current working directory.
* **Branching Strategy:** * Create a dedicated branch for the **service**.
* Create individual branches for **each task**.


* **Merging:** Each task script must apply changes, commit to its specific branch, and merge back into the service branch.



---

### 3. Service and Security

* **`build_service.sh`**
* **Initialization:** Create or replace a `systemd` unit file.
* **Security:** Configure the service to access encrypted API keys.
* **Execution:** Start and enable the service to manage the container.


* **`place_keys.sh` (or `KEYS_GUIDE.md`)**
* Document/script the required method for placing encrypted API keys on the system.
* Define how the service retrieves these keys at runtime.



---

Would you like me to outline the logic for the Git branching and merging sequence in the main script?
