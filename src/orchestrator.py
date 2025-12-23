#!/usr/bin/env python3
from __future__ import annotations

import argparse
import asyncio
import json
import logging
import os
import re
import shutil
import sys
from dataclasses import dataclass
from datetime import datetime, timezone
from functools import lru_cache
from pathlib import Path
from typing import Iterable, List, Mapping, Optional

from openai.types.shared import Reasoning

from agents import Agent, ModelSettings, Runner, set_default_openai_key
from agents.mcp import MCPServerStdio

ROOT_DIR = Path(__file__).resolve().parent.parent

SCENARIO_HEADER_RE = re.compile(
    r"^(?P<hashes>#{1,6})\s+(?P<number>\d+(?:\.\d+)*)\)\s+(?P<title>.+?)\s*$"
)

DEFAULT_PROMPT_TEMPLATE = """\
You are the Executor. Produce a concise, implementation-ready guidance note.

Scenario: {SCENARIO_ID}) {SCENARIO_TITLE}
Scenario details:
{SCENARIO_BODY}

Output requirements:
- Write the result to {OUTPUT_PATH}.
- Use Markdown headings and bullet lists.
- Sections: Scenario, When to use, Recommended approach, Implementation outline, Tradeoffs/risks, Validation checklist.
- Keep it under 250 words.
- ASCII only.
- Do not invent requirements beyond the scenario text.

After writing the file, reply with "DONE".
"""

REQUIRED_TEMPLATE_KEYS = {
    "{SCENARIO_ID}",
    "{SCENARIO_TITLE}",
    "{SCENARIO_BODY}",
    "{OUTPUT_PATH}",
}
REASONING_EFFORT_LEVELS = {"minimal", "low", "medium", "high"}
DEFAULT_INPUT_PATH = ROOT_DIR / "input/DataTransferScenarioList.md"
DEFAULT_INPUT_TEMPLATE_PATH = ROOT_DIR / "input/prompt_template.txt"
DEFAULT_BASE_TEMPLATE_PATH = ROOT_DIR / "src/prompt_template_base.txt"


@dataclass(frozen=True)
class Scenario:
    index: int
    number: str
    title: str
    body: str

    def display_title(self) -> str:
        return f"{self.number}) {self.title}".strip()


@dataclass(frozen=True)
class RunLogConfig:
    run_id: str
    log_dir: Path
    events_path: Path
    runs_path: Path
    agent_log_path: Path

    def log_event(self, event: str, payload: Mapping[str, object] | None = None) -> None:
        data = {"ts": utc_timestamp(), "event": event}
        if payload:
            data.update(payload)
        append_jsonl(self.events_path, data)

    def log_run(self, payload: Mapping[str, object]) -> None:
        append_jsonl(self.runs_path, payload)


def utc_timestamp() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def make_run_id() -> str:
    return datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")


def append_jsonl(path: Path, payload: Mapping[str, object]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as f:
        f.write(json.dumps(payload, ensure_ascii=True) + "\n")


def initialize_run_logs(log_dir: Path, run_id: str) -> RunLogConfig:
    log_dir.mkdir(parents=True, exist_ok=True)
    return RunLogConfig(
        run_id=run_id,
        log_dir=log_dir,
        events_path=log_dir / "run_events.jsonl",
        runs_path=log_dir / "agent_runs.jsonl",
        agent_log_path=log_dir / "agents_sdk.log",
    )


def configure_agents_logging(run_logs: RunLogConfig) -> None:
    formatter = logging.Formatter(
        fmt="%(asctime)sZ %(levelname)s %(name)s: %(message)s",
        datefmt="%Y-%m-%dT%H:%M:%S",
    )
    handler = logging.FileHandler(run_logs.agent_log_path, encoding="utf-8")
    handler.setFormatter(formatter)
    for logger_name in ("openai.agents", "openai.agents.tracing", "openai.agents.mcp"):
        logger = logging.getLogger(logger_name)
        logger.setLevel(logging.DEBUG)
        logger.propagate = False
        if not any(
            isinstance(h, logging.FileHandler)
            and getattr(h, "baseFilename", None) == handler.baseFilename
            for h in logger.handlers
        ):
            logger.addHandler(handler)


def load_configuration(env_path: Path) -> dict[str, str]:
    """Loads configuration from a JSON formatted .env file."""
    if not env_path.exists():
        raise FileNotFoundError(f"Configuration file not found: {env_path}")
    try:
        with env_path.open("r", encoding="utf-8") as f:
            return json.load(f)
    except json.JSONDecodeError as e:
        raise RuntimeError(f"Failed to parse configuration file: {e}")


def normalize_ascii(text: str) -> str:
    replacements = {
        "\u2018": "'",
        "\u2019": "'",
        "\u201c": '"',
        "\u201d": '"',
        "\u2013": "-",
        "\u2014": "--",
        "\u2026": "...",
    }
    for src, dst in replacements.items():
        text = text.replace(src, dst)
    return text.encode("ascii", "ignore").decode("ascii")


@lru_cache(maxsize=1)
def load_api_key(credential_path: str) -> str:
    """Loads the API key strictly from file descriptor 3."""
    import os
    try:
        with os.fdopen(3, "r") as f:
            key = f.read().strip()
            if not key:
                raise RuntimeError("API key read from FD 3 was empty.")
            return key
    except OSError as e:
        raise RuntimeError(
            "API key FD 3 not available. This application must be launched "
            "via the secure wrapper script (src/run_with_api_key_fd.sh)."
        ) from e


def escape_braces(text: str) -> str:
    return text.replace("{", "{{").replace("}", "}}")


def display_path(path: Path) -> str:
    try:
        return path.relative_to(ROOT_DIR).as_posix()
    except ValueError:
        return path.as_posix()


def parse_scenarios(path: Path) -> List[Scenario]:
    lines = path.read_text(encoding="utf-8").splitlines()
    scenarios: List[Scenario] = []
    current_number = ""
    current_title = ""
    current_body: List[str] = []

    def flush() -> None:
        nonlocal current_number, current_title, current_body
        if not current_number:
            return
        body_text = "\n".join(current_body).strip()
        scenarios.append(
            Scenario(
                index=len(scenarios),
                number=normalize_ascii(current_number),
                title=normalize_ascii(current_title),
                body=normalize_ascii(body_text),
            )
        )
        current_number = ""
        current_title = ""
        current_body = []

    for line in lines:
        match = SCENARIO_HEADER_RE.match(line)
        if match:
            flush()
            current_number = match.group("number").strip()
            current_title = match.group("title").strip()
            continue
        if current_number:
            current_body.append(line.rstrip())

    flush()
    if not scenarios:
        raise ValueError(f"No numbered scenarios found in {path}.")
    return scenarios


def write_todo_list(scenarios: Iterable[Scenario], path: Path) -> None:
    lines = [scenario.display_title() for scenario in scenarios]
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def output_filename(index: int) -> str:
    return f"scenario_{index + 1:03d}.md"


def render_prompt(template: str, scenario: Scenario, output_path: Path) -> str:
    replacements = {
        "{SCENARIO_ID}": escape_braces(scenario.number),
        "{SCENARIO_TITLE}": escape_braces(scenario.title),
        "{SCENARIO_BODY}": escape_braces(scenario.body or "(No extra details provided.)"),
        "{OUTPUT_PATH}": escape_braces(display_path(output_path)),
    }
    rendered = template
    for key, value in replacements.items():
        rendered = rendered.replace(key, value)
    return rendered


def validate_template(template: str) -> bool:
    return all(key in template for key in REQUIRED_TEMPLATE_KEYS)


def resolve_base_template(base_template_path: Path) -> str:
    if base_template_path.exists():
        return base_template_path.read_text(encoding="utf-8").strip()
    base_template_path.parent.mkdir(parents=True, exist_ok=True)
    base_template_path.write_text(DEFAULT_PROMPT_TEMPLATE.strip() + "\n", encoding="utf-8")
    return DEFAULT_PROMPT_TEMPLATE.strip()


def resolve_input_template(input_template_path: Path, base_template: str) -> str:
    if input_template_path.exists():
        return input_template_path.read_text(encoding="utf-8").strip()
    input_template_path.parent.mkdir(parents=True, exist_ok=True)
    input_template_path.write_text(base_template.strip() + "\n", encoding="utf-8")
    return base_template.strip()


def write_manifest(
    scenarios: Iterable[Scenario],
    output_dir: Path,
    input_path: Path,
    manifest_path: Path,
) -> None:
    utc_now = datetime.now(timezone.utc).replace(microsecond=0).isoformat()
    manifest = {
        "source": normalize_ascii(display_path(input_path)),
        "generated_at": utc_now,
        "output_dir": normalize_ascii(display_path(output_dir)),
        "scenarios": [
            {
                "index": scenario.index,
                "number": scenario.number,
                "title": scenario.title,
                "output_file": output_filename(scenario.index),
            }
            for scenario in scenarios
        ],
    }
    manifest_path.write_text(
        json.dumps(manifest, indent=2, ensure_ascii=True) + "\n",
        encoding="utf-8",
    )


def aggregate_outputs(
    scenarios: Iterable[Scenario], output_dir: Path, results_path: Path
) -> None:
    content: List[str] = ["# Scenario Results", ""]
    for scenario in scenarios:
        filename = output_filename(scenario.index)
        output_path = output_dir / filename
        content.append(f"## {scenario.display_title()}")
        content.append("")
        if output_path.exists():
            content.append(output_path.read_text(encoding="utf-8").strip())
        else:
            content.append(f"_Missing output: {output_path.as_posix()}_")
        content.append("")
        content.append("---")
        content.append("")
    results_path.write_text("\n".join(content).rstrip() + "\n", encoding="utf-8")


def capture_usage(result: object) -> Optional[dict[str, int]]:
    usage = getattr(getattr(result, "context_wrapper", None), "usage", None)
    if not usage:
        return None
    return {
        "requests": getattr(usage, "requests", None),
        "input_tokens": getattr(usage, "input_tokens", None),
        "output_tokens": getattr(usage, "output_tokens", None),
        "total_tokens": getattr(usage, "total_tokens", None),
    }


async def run_agent_with_logging(
    agent: Agent,
    prompt: str,
    run_logs: RunLogConfig,
    run_kind: str,
    metadata: Mapping[str, object] | None = None,
) -> object:
    payload = {
        "ts": utc_timestamp(),
        "event": "agent_run_start",
        "run_kind": run_kind,
        "agent": agent.name,
        "prompt": prompt,
    }
    if metadata:
        payload.update(metadata)
    run_logs.log_run(payload)
    try:
        result = await Runner.run(agent, prompt)
    except Exception as exc:
        run_logs.log_run(
            {
                "ts": utc_timestamp(),
                "event": "agent_run_error",
                "run_kind": run_kind,
                "agent": agent.name,
                "error": str(exc),
                **(metadata or {}),
            }
        )
        raise
    output_value = getattr(result, "final_output", None)
    if output_value is not None and not isinstance(output_value, str):
        output_value = str(output_value)
    run_logs.log_run(
        {
            "ts": utc_timestamp(),
            "event": "agent_run_end",
            "run_kind": run_kind,
            "agent": agent.name,
            "output": output_value,
            "last_response_id": getattr(result, "last_response_id", None),
            "usage": capture_usage(result),
            **(metadata or {}),
        }
    )
    return result


async def build_prompt_template(
    scheduler: Agent,
    base_template: str,
    prompt_template_path: Path,
    run_logs: RunLogConfig,
) -> str:
    print("[orchestrator] Sending prompt calibration request to Scheduler...", file=sys.stderr)
    request = (
        "Improve the following prompt template for an Executor agent.\n"
        "Return only the updated template text, with no commentary.\n"
        "Keep these placeholders exactly as-is: "
        "{SCENARIO_ID}, {SCENARIO_TITLE}, {SCENARIO_BODY}, {OUTPUT_PATH}.\n"
        "Use ASCII only.\n\n"
        "Template:\n"
        f"{base_template}\n"
    )
    result = await run_agent_with_logging(
        scheduler,
        request,
        run_logs,
        run_kind="prompt_calibration",
        metadata={"prompt_template_path": display_path(prompt_template_path)},
    )
    candidate = normalize_ascii(result.final_output.strip())
    if not validate_template(candidate):
        candidate = base_template
    prompt_template_path.write_text(candidate + "\n", encoding="utf-8")
    print("[orchestrator] Prompt calibration complete.", file=sys.stderr)
    return candidate


async def run_executor(
    scenarios: List[Scenario],
    output_dir: Path,
    prompt_template: str,
    executor: Agent,
    overwrite: bool,
    max_scenarios: int | None,
    run_logs: RunLogConfig,
) -> None:
    limit = len(scenarios) if max_scenarios is None else max_scenarios
    print(f"[orchestrator] Starting execution of {limit} scenarios...", file=sys.stderr)
    for scenario in scenarios[:limit]:
        output_path = output_dir / output_filename(scenario.index)
        if output_path.exists() and not overwrite:
            continue
        print(f"[orchestrator] Processing scenario {scenario.number}: {scenario.title}...", file=sys.stderr)
        prompt = render_prompt(prompt_template, scenario, output_path)
        await run_agent_with_logging(
            executor,
            prompt,
            run_logs,
            run_kind="scenario_run",
            metadata={
                "scenario_number": scenario.number,
                "scenario_title": scenario.title,
                "output_path": display_path(output_path),
            },
        )


async def calibrate_executor(
    scenario: Scenario,
    output_dir: Path,
    prompt_template: str,
    executor: Agent,
    overwrite: bool,
    run_logs: RunLogConfig,
) -> None:
    output_path = output_dir / output_filename(scenario.index)
    if output_path.exists() and not overwrite:
        return
    print(f"[orchestrator] Sending calibration task (Scenario {scenario.number}) to Executor...", file=sys.stderr)
    prompt = render_prompt(prompt_template, scenario, output_path)
    await run_agent_with_logging(
        executor,
        prompt,
        run_logs,
        run_kind="executor_calibration",
        metadata={
            "scenario_number": scenario.number,
            "scenario_title": scenario.title,
            "output_path": display_path(output_path),
        },
    )
    if not output_path.exists():
        raise RuntimeError(
            "Calibration failed: executor did not write the expected output file."
        )


def build_arg_parser(config: dict[str, str]) -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Sequential scenario orchestration using Codex MCP + Agents SDK."
    )
    parser.add_argument(
        "--input",
        default=DEFAULT_INPUT_PATH,
        help="Path to the scenario list markdown file.",
    )
    parser.add_argument(
        "--input-template",
        default=DEFAULT_INPUT_TEMPLATE_PATH,
        help="Path to the editable prompt template used for calibration.",
    )
    parser.add_argument(
        "--base-template",
        default=DEFAULT_BASE_TEMPLATE_PATH,
        help="Path to the baseline prompt template for safe rollback.",
    )
    parser.add_argument(
        "--output-dir",
        default=ROOT_DIR / "outputs",
        help="Directory for per-scenario outputs.",
    )
    parser.add_argument(
        "--log-dir",
        default=None,
        help="Directory for run logs. Defaults to logs/run-<timestamp>.",
    )
    parser.add_argument(
        "--todo-file",
        default=None,
        help="Path to write the scenario todo list. Defaults to outputs/todo_scenarios.txt.",
    )
    parser.add_argument(
        "--results-file",
        default=None,
        help="Path to write the aggregated results. Defaults to outputs/MASTER_RESULTS.md.",
    )
    parser.add_argument(
        "--prompt-template-file",
        default=None,
        help="Path to write the calibrated prompt template. Defaults to outputs/prompt_template.txt.",
    )
    parser.add_argument(
        "--model",
        default=config.get("INTERLLM_MODEL", "gpt-4o"),
        help="Model name for Scheduler and Executor agents.",
    )
    parser.add_argument(
        "--reasoning-effort",
        default=config.get("INTERLLM_REASONING_EFFORT", ""),
        help="Reasoning effort: minimal|low|medium|high (GPT-5/o-series only).",
    )
    parser.add_argument(
        "--max-scenarios",
        type=int,
        default=None,
        help="Process only the first N scenarios.",
    )
    parser.add_argument(
        "--overwrite",
        action="store_true",
        help="Overwrite existing scenario outputs.",
    )
    return parser


def model_supports_reasoning(model_name: str) -> bool:
    normalized = model_name.lower()
    return normalized.startswith("gpt-5") or normalized.startswith("o")


def resolve_model_settings(model_name: str, effort: str) -> ModelSettings | None:
    if not effort:
        return None
    normalized = effort.strip().lower()
    if normalized not in REASONING_EFFORT_LEVELS:
        raise ValueError(
            "INTERLLM_REASONING_EFFORT must be one of: minimal, low, medium, high."
        )
    if not model_supports_reasoning(model_name):
        print(
            f"Warning: reasoning effort requested for {model_name}, "
            "but this model may not support reasoning effort. Ignoring.",
            file=sys.stderr,
        )
        return None
    return ModelSettings(reasoning=Reasoning(effort=normalized))


def resolve_codex_reasoning_effort(effort: str) -> str | None:
    if not effort:
        return None
    normalized = effort.strip().lower()
    if normalized in {"low", "medium", "high", "xhigh"}:
        return normalized
    if normalized == "minimal":
        return None
    return None


def build_codex_args(model_name: str, effort: str) -> list[str]:
    args: list[str] = [
        "-y",
        "codex",
        "--model",
        model_name,
        "--ask-for-approval",
        "never",
        "--sandbox",
        "workspace-write",
    ]
    codex_effort = resolve_codex_reasoning_effort(effort)
    if codex_effort:
        args.extend(["--config", f'model_reasoning_effort="{codex_effort}"'])
    args.append("mcp-server")
    return args


def build_mcp_server_params(codex_args: list[str], log_dir: Path) -> dict[str, object]:
    wrapper_path = ROOT_DIR / "src/mcp_stdio_logger.py"
    return {
        "command": sys.executable,
        "args": [
            str(wrapper_path),
            "--log-dir",
            str(log_dir.resolve()),
            "--name",
            "codex_mcp",
            "--",
            "npx",
            *codex_args,
        ],
    }


def resolve_project_path(path: Path) -> Path:
    return path if path.is_absolute() else ROOT_DIR / path


def prepare_output_dir(output_dir: Path) -> None:
    resolved = output_dir.resolve()
    if resolved == Path.cwd().resolve():
        raise RuntimeError("Output dir cannot be the project root.")
    if output_dir.exists():
        shutil.rmtree(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)


async def main() -> None:
    logging.getLogger().setLevel(logging.ERROR)
    
    config = load_configuration(ROOT_DIR / "src/.env")
    args = build_arg_parser(config).parse_args()
    run_id = make_run_id()
    log_dir = (
        resolve_project_path(Path(args.log_dir))
        if args.log_dir
        else ROOT_DIR / "logs" / f"run-{run_id}"
    )
    run_logs = initialize_run_logs(log_dir, run_id)
    configure_agents_logging(run_logs)
    run_logs.log_event(
        "run_start",
        {
            "run_id": run_id,
            "log_dir": display_path(run_logs.log_dir),
            "model": args.model,
            "reasoning_effort": args.reasoning_effort,
        },
    )

    os.environ.setdefault("RUST_LOG", "codex_core=info,codex_rmcp_client=info")
    os.environ.setdefault("RUST_BACKTRACE", "1")

    print("[orchestrator] Starting orchestrator, attempting to load API key...", file=sys.stderr)
    api_key = load_api_key(config.get("CREDENTIAL_PATH", ""))
    set_default_openai_key(api_key)
    print("[orchestrator] API key loaded and configured.", file=sys.stderr)
    model_settings = resolve_model_settings(args.model, args.reasoning_effort)
    if model_settings is None:
        model_settings = ModelSettings()

    input_path = resolve_project_path(Path(args.input))
    input_template_path = resolve_project_path(Path(args.input_template))
    base_template_path = resolve_project_path(Path(args.base_template))
    output_dir = resolve_project_path(Path(args.output_dir))
    todo_path = (
        resolve_project_path(Path(args.todo_file))
        if args.todo_file
        else output_dir / "todo_scenarios.txt"
    )
    results_path = (
        resolve_project_path(Path(args.results_file))
        if args.results_file
        else output_dir / "MASTER_RESULTS.md"
    )
    prompt_template_path = (
        resolve_project_path(Path(args.prompt_template_file))
        if args.prompt_template_file
        else output_dir / "prompt_template.txt"
    )

    (run_logs.log_dir / "run_config.json").write_text(
        json.dumps(
            {
                "run_id": run_id,
                "input_path": display_path(input_path),
                "input_template_path": display_path(input_template_path),
                "base_template_path": display_path(base_template_path),
                "output_dir": display_path(output_dir),
                "todo_path": display_path(todo_path),
                "results_path": display_path(results_path),
                "prompt_template_path": display_path(prompt_template_path),
                "model": args.model,
                "reasoning_effort": args.reasoning_effort,
                "max_scenarios": args.max_scenarios,
                "overwrite": args.overwrite,
                "log_dir": display_path(run_logs.log_dir),
            },
            indent=2,
            ensure_ascii=True,
        )
        + "\n",
        encoding="utf-8",
    )

    scenarios = parse_scenarios(input_path)
    prepare_output_dir(output_dir)
    write_todo_list(scenarios, todo_path)
    write_manifest(scenarios, output_dir, input_path, output_dir / "scenario_manifest.json")

    codex_args = build_codex_args(args.model, args.reasoning_effort)
    run_logs.log_event(
        "codex_mcp_command",
        {"command": ["npx", *codex_args]},
    )
    print("[orchestrator] Connecting to Codex MCP...", file=sys.stderr)
    async with MCPServerStdio(
        name="Codex CLI",
        params=build_mcp_server_params(codex_args, run_logs.log_dir),
        client_session_timeout_seconds=360000,
    ) as codex_mcp:
        print("[orchestrator] Successfully connected to Codex MCP.", file=sys.stderr)
        scheduler = Agent(
            name="Scheduler",
            instructions=(
                "You calibrate prompts for downstream execution. "
                "Return only the prompt template text."
            ),
            model=args.model,
            model_settings=model_settings,
            mcp_servers=[codex_mcp],
        )
        executor = Agent(
            name="Executor",
            instructions=(
                "You execute one scenario at a time. "
                "Always use Codex MCP to write files with "
                '{"approval-policy":"never","sandbox":"workspace-write"}. '
                "Do not paste file contents in chat; write to disk."
            ),
            model=args.model,
            model_settings=model_settings,
            mcp_servers=[codex_mcp],
        )

        base_template = resolve_base_template(base_template_path)
        input_template = resolve_input_template(input_template_path, base_template)
        prompt_template = await build_prompt_template(
            scheduler, input_template, prompt_template_path, run_logs
        )
        await calibrate_executor(
            scenarios[0],
            output_dir,
            prompt_template,
            executor,
            args.overwrite,
            run_logs,
        )
        await run_executor(
            scenarios,
            output_dir,
            prompt_template,
            executor,
            args.overwrite,
            args.max_scenarios,
            run_logs,
        )

    aggregate_outputs(scenarios, output_dir, results_path)
    run_logs.log_event("run_complete", {"run_id": run_id})


if __name__ == "__main__":
    asyncio.run(main())
