# interllm

## Project Overview

`interllm` is a Python-based sequential agentic workflow designed to process a list of data-transfer scenarios. It acts as an orchestrator that reads scenarios, processes them using the Codex CLI (via the OpenAI Agents SDK), and aggregates the results.

The system uses an **Orchestrator** (`src/orchestrator.py`) to:
1.  Parse scenarios from a Markdown file (`input/DataTransferScenarioList.md`).
2.  Calibrate a prompt template.
3.  Run each scenario through an AI agent.
4.  Collect outputs into `outputs/`.

## Setup & Installation

### Prerequisites
*   Python 3.10+
*   Node.js 18+ (for `npx` / Codex CLI)
*   OpenAI API Key

### Installation
1.  Create and activate a virtual environment:
    ```bash
    python -m venv .venv
    source .venv/bin/activate
    ```
2.  Install dependencies:
    ```bash
    pip install -r src/requirements.txt
    ```
3.  **Credential Setup:**
    The project uses systemd credentials for API key security.
    ```bash
    sudo install -d /etc/credstore.encrypted
    printf '%s' "$OPENAI_API_KEY" | sudo systemd-creds encrypt - /etc/credstore.encrypted/codex_key
    ```
4.  **Configuration:**
    Ensure `src/.env` exists with the following structure:
    ```json
    {
      "CREDENTIAL_PATH": "/etc/credstore.encrypted/codex_key",
      "CREDENTIAL_NAME": "codex_key",
      "INTERLLM_MODEL": "gpt-5-codex",
      "INTERLLM_REASONING_EFFORT": "medium"
    }
    ```

## Building & Running

There is no build step. The project is run directly via Python scripts.

### Main Execution
Use the provided wrapper script:
```bash
./src/run.sh
```

### Common Flags
*   `--max-scenarios <N>`: Run only the first N scenarios (useful for testing).
*   `--overwrite`: Regenerate existing outputs.
*   `--input <path>`: Specify a different scenario list file.
*   `--output-dir <path>`: Change the output directory.

### Example
Run the first 2 scenarios and overwrite previous results:
```bash
./src/run.sh --max-scenarios 2 --overwrite
```

## Project Structure

*   **`src/`**: Source code.
    *   `orchestrator.py`: Main entry point and logic.
    *   `run.sh`: Wrapper script for execution.
    *   `requirements.txt`: Python dependencies.
    *   `.env`: Configuration file.
*   **`input/`**: Input data.
    *   `DataTransferScenarioList.md`: The list of scenarios to process.
    *   `prompt_template.txt`: Editable prompt template.
*   **`outputs/`**: Generated artifacts (cleared at the start of each run).
    *   `MASTER_RESULTS.md`: Aggregated results.
*   **`logs/`**: Runtime logs and telemetry.

## Development Conventions

*   **Code Style**: Python code follows standard PEP 8 conventions.
*   **Documentation**: Markdown files are used extensively for documentation.
*   **Testing**: Currently, there are no automated tests. Verification is done by running scenarios and checking `outputs/`.
