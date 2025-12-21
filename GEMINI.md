# Gemini Context: interllm

## Project Overview
`interllm` is a Python-based application that implements a sequential agentic workflow. It uses the OpenAI Agents SDK and Codex CLI (via MCP) to process a list of data-transfer scenarios. The system orchestrates two main agents:
1.  **Scheduler:** Calibrates and optimizes the prompt template.
2.  **Executor:** Iterates through scenarios, generating guidance notes and artifacts for each using the Codex CLI.

## Key Files & Directories

### Source Code (`src/`)
*   `src/orchestrator.py`: The core application logic. It handles argument parsing, scenario parsing, agent coordination, and result aggregation.
*   `src/requirements.txt`: Python dependencies (`openai`, `openai-agents`).
*   `src/prompt_template_base.txt`: The baseline prompt template used for the Executor agent.

### Inputs (`input/`)
*   `input/DataTransferScenarioList.md`: The inventory of scenarios to be processed. **Note:** The program identifies scenarios dynamically from this file; do not hard-code them.
*   `input/prompt_template.txt`: An editable template file used for calibration.

### Outputs (`outputs/`)
*   Generated artifacts from the run, including `MASTER_RESULTS.md`, individual scenario files, and the calibrated prompt.
*   **Note:** This directory is cleared at the start of each run.

### Documentation & Config
*   `README.md`: Primary user entry point with setup and run instructions.
*   `AGENTS.md` & `AGENTS.override.md`: Repository guidelines, documentation standards, and Context7 details.
*   `agents-md.md` & `agents-sdk.md`: Source guides drawn from Codex CLI docs.
*   `goal.md`: Initial proposal and project goal.
*   `broad_code_proposal.md`: Initial code proposal derived from the goal.
*   `run-status-and-next-steps.md`: Current run status and follow-up plans.
*   `context7codexlib.txt`: Stores the Context7 library ID used for frequent lookups.
*   `logs/`: Stores error logs (`stderr` captures).

## Setup & Configuration

### Prerequisites
*   Python 3.10+
*   Node.js 18+ (for `npx` to run Codex CLI)
*   OpenAI API Key

### Installation
```bash
python -m venv .venv
source .venv/bin/activate
pip install -r src/requirements.txt
```

### Credentials
The application expects the OpenAI API key to be stored in a systemd credential file.
```bash
# Example setup (requires sudo)
sudo install -d /etc/credstore.encrypted
printf '%s' "$OPENAI_API_KEY" | sudo systemd-creds encrypt - /etc/credstore.encrypted/codex_key
```

## Usage

### Running the Orchestrator
To execute the full workflow:
```bash
python src/orchestrator.py
```

### Common Flags
*   `--input <path>`: Specify a different scenario list.
*   `--max-scenarios <int>`: Limit the run to the first N scenarios (useful for testing).
*   `--overwrite`: Force regeneration of existing outputs.
*   `--reasoning-effort <level>`: Set reasoning effort (minimal, low, medium, high) for supported models (e.g., GPT-5/o-series).

## Development Conventions

*   **Language:** Python 3.10+ with strict type hinting (`mypy` style).
*   **Style:**
    *   **Python:** Follows standard Python conventions (PEP 8).
    *   **Markdown:** This is a Markdown-first repo. Keep headings short, use sentence case, and prefer bullet lists. Wrap code in fenced blocks with language tags.
    *   **File Naming:** Use lowercase with hyphens (e.g., `agent-workflow-notes.md`).
*   **Architecture:**
    *   **Agents:** Defined using the `agents` library.
    *   **MCP:** The Codex CLI is integrated as an MCP server (`MCPServerStdio`).
    *   **Async:** The core logic is asynchronous (`asyncio`).
*   **Testing/Build:** No automated tests or build scripts exist currently. Use your editor’s preview for Markdown.
*   **Commits:** Use simple, lowercase, sentence-style commit messages (e.g., "init commit").

## Agent & Context7 Guidelines

*   **Context7 MCP:** Lean heavily on Context7 MCP for references. Prefer these library IDs:
    *   `openai/openai-cookbook`
    *   `websites/cookbook_openai`
    *   `websites/developers_openai_codex`
    *   `websites/codex_io`
    *   `openai/codex`
*   **Update Policy:** If relying on Context7, update `context7codexlib.txt` when the canonical library ID changes.
