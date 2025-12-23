# interllm

## Overview
This project implements a sequential agentic workflow for processing a list of
data-transfer scenarios. The orchestrator reads `input/DataTransferScenarioList.md`,
builds a todo list, runs each scenario through Codex CLI (via the OpenAI Agents
SDK), and aggregates the outputs into a single results file.

## Requirements
- Python 3.10+
- Node.js 18+ (for `npx`)
- Codex CLI available via `npx`
- An OpenAI API key

## Setup
```bash
python -m venv .venv
source .venv/bin/activate
pip install -r src/requirements.txt
```

Store your API key in a systemd credential:

```bash
sudo install -d /etc/credstore.encrypted
printf '%s' "$OPENAI_API_KEY" | sudo systemd-creds encrypt - /etc/credstore.encrypted/codex_key
```

Configuration is managed via `src/.env`. Ensure it contains the path to your credential and your model preferences:
```json
{
  "CREDENTIAL_PATH": "/etc/credstore.encrypted/codex_key",
  "INTERLLM_MODEL": "gpt-5-codex",
  "INTERLLM_REASONING_EFFORT": "medium"
}
```

## Run
```bash
python src/orchestrator.py
```

Useful flags:
- `--input` to point at a different scenario list file
- `--input-template` to point at an alternate editable prompt template
- `--base-template` to point at a different baseline prompt template
- `--output-dir` to change where per-scenario outputs are written
- `--max-scenarios` to run a smaller batch for testing
- `--overwrite` to regenerate existing outputs
- `--reasoning-effort` to set GPT-5/o-series reasoning level (minimal|low|medium|high)

## Inputs
- `input/DataTransferScenarioList.md` – scenario inventory
- `input/prompt_template.txt` – editable prompt template used for calibration
- `src/prompt_template_base.txt` – baseline prompt template to revert to

## Outputs
- `outputs/` – per-scenario guidance notes and run artifacts
- `outputs/todo_scenarios.txt` – one line per scenario (generated from the markdown file)
- `outputs/MASTER_RESULTS.md` – concatenated results
- `outputs/prompt_template.txt` – calibrated prompt template
- `outputs/scenario_manifest.json` – scenario metadata and output mapping

## Logs
- `logs/error_output/` – captured stderr and failure traces from full runs
- `logs/run-*/` – per-run artifacts (JSONL event logs, agent call logs, MCP traffic, SDK debug logs)
- `run-status-and-next-steps.md` – current state, observed failures, and follow-up plan

## Notes
- The scenario list is parsed from `input/DataTransferScenarioList.md` at runtime;
  do not hard-code items.
- The first scenario is used to calibrate the prompt template before the full
  run.
- The `outputs/` directory is cleared at the start of each run.
- Relative paths are resolved from the repository root.
- Reasoning effort is optional and only applied for GPT-5 or o-series models.
- The Codex MCP server is launched with the configured model and reasoning effort.
- Future target: once validated, we plan to move to `gpt-5.2-codex` with medium reasoning effort.
