#!/usr/bin/env python3
from __future__ import annotations

import argparse
import asyncio
import json
import logging
import os
import re
import shutil
import subprocess
import sys
from dataclasses import dataclass
from datetime import datetime, timezone
from functools import lru_cache
from pathlib import Path
from typing import Iterable, List

from openai.types.shared import Reasoning

from agents import Agent, ModelSettings, Runner, set_default_openai_api
from agents.mcp import MCPServerStdio

ROOT_DIR = Path(__file__).resolve().parent.parent
CRED_FILE = Path("/etc/credstore.encrypted/codex_key")

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

When creating files, call Codex MCP with {"approval-policy":"never","sandbox":"workspace-write"}.
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


def _decrypt_credential(path: Path) -> str:
    process = subprocess.Popen(
        ["systemd-creds", "decrypt", str(path)]
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    out, err = process.communicate()
    if process.returncode != 0:
        raise RuntimeError(f"Credential decryption failed: {err.strip()}")
    s = out.strip()
    if not s:
        raise RuntimeError("Decryption produced no output; verify systemd-creds decrypt behavior on this host")
    return s


@lru_cache(maxsize=1)
def load_api_key() -> str:
    if not CRED_FILE.exists():
        raise FileNotFoundError(f"Encrypted credential not found: {CRED_FILE}")
    return _decrypt_credential(CRED_FILE)


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


async def build_prompt_template(
    scheduler: Agent, base_template: str, prompt_template_path: Path
) -> str:
    request = (
        "Improve the following prompt template for an Executor agent.\n"
        "Return only the updated template text, with no commentary.\n"
        "Keep these placeholders exactly as-is: "
        "{SCENARIO_ID}, {SCENARIO_TITLE}, {SCENARIO_BODY}, {OUTPUT_PATH}.\n"
        "Use ASCII only.\n\n"
        "Template:\n"
        f"{base_template}\n"
    )
    result = await Runner.run(scheduler, request)
    candidate = normalize_ascii(result.final_output.strip())
    if not validate_template(candidate):
        candidate = base_template
    prompt_template_path.write_text(candidate + "\n", encoding="utf-8")
    return candidate


async def run_executor(
    scenarios: List[Scenario],
    output_dir: Path,
    prompt_template: str,
    executor: Agent,
    overwrite: bool,
    max_scenarios: int | None,
) -> None:
    limit = len(scenarios) if max_scenarios is None else max_scenarios
    for scenario in scenarios[:limit]:
        output_path = output_dir / output_filename(scenario.index)
        if output_path.exists() and not overwrite:
            continue
        prompt = render_prompt(prompt_template, scenario, output_path)
        await Runner.run(executor, prompt)


async def calibrate_executor(
    scenario: Scenario,
    output_dir: Path,
    prompt_template: str,
    executor: Agent,
    overwrite: bool,
) -> None:
    output_path = output_dir / output_filename(scenario.index)
    if output_path.exists() and not overwrite:
        return
    prompt = render_prompt(prompt_template, scenario, output_path)
    await Runner.run(executor, prompt)
    if not output_path.exists():
        raise RuntimeError(
            "Calibration failed: executor did not write the expected output file."
        )


def build_arg_parser() -> argparse.ArgumentParser:
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
        default=os.getenv("INTERLLM_MODEL", "gpt-4o"),
        help="Model name for Scheduler and Executor agents.",
    )
    parser.add_argument(
        "--reasoning-effort",
        default=os.getenv("INTERLLM_REASONING_EFFORT", ""),
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
    args: list[str] = ["-y", "codex", "--model", model_name]
    codex_effort = resolve_codex_reasoning_effort(effort)
    if codex_effort:
        args.extend(["--config", f'model_reasoning_effort="{codex_effort}"'])
    args.append("mcp-server")
    return args


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
    args = build_arg_parser().parse_args()

    api_key = load_api_key()
    set_default_openai_api(api_key)
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

    scenarios = parse_scenarios(input_path)
    prepare_output_dir(output_dir)
    write_todo_list(scenarios, todo_path)
    write_manifest(scenarios, output_dir, input_path, output_dir / "scenario_manifest.json")

    codex_args = build_codex_args(args.model, args.reasoning_effort)
    async with MCPServerStdio(
        name="Codex CLI",
        params={"command": "npx", "args": codex_args},
        client_session_timeout_seconds=360000,
    ) as codex_mcp:
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
            scheduler, input_template, prompt_template_path
        )
        await calibrate_executor(
            scenarios[0], output_dir, prompt_template, executor, args.overwrite
        )
        await run_executor(
            scenarios,
            output_dir,
            prompt_template,
            executor,
            args.overwrite,
            args.max_scenarios,
        )

    aggregate_outputs(scenarios, output_dir, results_path)


if __name__ == "__main__":
    asyncio.run(main())
