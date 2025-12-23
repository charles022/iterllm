# Logging and telemetry notes (Codex MCP + Agents SDK)

## Why this exists
We want complete, durable records of:
- Agent prompts + outputs (conversation history we currently discard).
- MCP request/response traffic between the Agents SDK and the Codex MCP server.
- Codex CLI runtime logs + request telemetry for debugging.

This note summarizes what the upstream docs say and how the repo now captures data.

## What the docs say (Context7 references)

### Codex CLI (logging + telemetry)
- Codex supports OpenTelemetry log export via an `[otel]` config block. It is **disabled by default** and must be explicitly enabled. Exporters are `none`, `otlp-http`, or `otlp-grpc`. Events include API requests, SSE events, tool approval decisions, tool results, and user prompts (prompt content is redacted unless `log_user_prompt = true`).  
  Sources: Codex config + security + local-config docs.
- Codex emits event categories such as `codex.api_request`, `codex.sse_event`, `codex.user_prompt`, `codex.tool_decision`, and `codex.tool_result`.  
  Source: Codex security monitoring/telemetry docs.
- Codex honors `RUST_LOG` for verbose logging (e.g., `codex_core=info,...`).  
  Source: Codex advanced logging docs.
- Config layering is explicit: CLI flags override user config, which is overridden by managed config.  
  Source: Codex config docs.

### OpenAI Agents SDK (logging + tracing)
- Tracing is **enabled by default**. It captures spans for agent runs, LLM generations, and tool calls. MCP activity is automatically included in tracing metadata.  
  Sources: Agents SDK tracing + MCP docs.
- `RunConfig` can set `trace_include_sensitive_data` to include LLM/tool inputs and outputs.  
  Source: Agents SDK running_agents + tracing docs.
- You can add or replace tracing processors with `add_trace_processor()` / `set_trace_processors()` to send traces somewhere else (or only locally).  
  Source: Agents SDK tracing docs.
- Debug logging can be enabled via SDK loggers (`openai.agents`, `openai.agents.tracing`) or `enable_verbose_stdout_logging()`. Environment flags `OPENAI_AGENTS_DONT_LOG_MODEL_DATA=1` and `OPENAI_AGENTS_DONT_LOG_TOOL_DATA=1` suppress sensitive data in logs.  
  Source: Agents SDK config docs.
- Sessions (SQLite, SQLAlchemy, OpenAI Conversations) persist conversation history across runs.  
  Source: Agents SDK sessions docs.

## What we added in this repo

### 1) MCP traffic capture (stdio proxy)
- `src/mcp_stdio_logger.py` proxies stdio to the Codex MCP server and records every JSON line in both directions (client -> server, server -> client), plus stderr and lifecycle events.
- The orchestrator launches Codex via this proxy, so the traffic is captured without changing prompts or tool calls.
- Logs are written to `logs/run-*/codex_mcp_traffic.jsonl`.

### 2) Agent run capture (prompt/output history)
- `src/orchestrator.py` now writes per-run JSONL logs of each `Runner.run` call:
  - `agent_runs.jsonl`: prompt text, output text, usage stats (when available), and scenario metadata.
  - `run_events.jsonl`: high-level run lifecycle and the Codex command invocation.
  - `run_config.json`: frozen run configuration (paths, model, flags).
- These live in `logs/run-<timestamp>/`.

### 3) SDK debug logs to file
- The SDK loggers `openai.agents`, `openai.agents.tracing`, and `openai.agents.mcp` are configured to write to `logs/run-*/agents_sdk.log`.

## How to enable deeper telemetry (optional)

### Codex OTEL (external collector)
If you want Codex to emit OTEL events, add this to `~/.codex/config.toml` (or a managed config layer):

```toml
[otel]
environment = "dev"
exporter = "otlp-http"
log_user_prompt = true

[otel.otlp_http]
endpoint = "https://your-collector.example.com/v1/logs"
headers = { Authorization = "Bearer YOUR_TOKEN" }
```

Notes from the docs:
- `log_user_prompt` defaults to `false` for privacy; set it to `true` only if your policy allows.
- `exporter = "none"` keeps instrumentation enabled but does not emit.

### Agents SDK tracing processors (local storage)
If you want traces stored locally instead of (or in addition to) OpenAI, use `add_trace_processor()` or `set_trace_processors()` in the orchestrator to install a file-backed processor. Tracing already captures MCP activity and tool calls; pairing it with a local processor makes that data persistent without relying on external dashboards.

## Hard-coded parameters vs prompt text (control strategy)
- Use CLI and config parameters to control execution (approval policy, sandbox, model, OTEL exporter).  
  The prompt should reinforce behavior but **not be the only source of truth**.
- In this repo, the Codex MCP server is launched with explicit `--ask-for-approval` and `--sandbox` flags; we do not rely on prompt wording for those settings.
- Keep open-ended prompts aligned with the hard-coded controls to avoid contradictions.

## Files to inspect
- `src/orchestrator.py` (run logging + Codex launch)
- `src/mcp_stdio_logger.py` (MCP traffic proxy logger)
- `logs/run-*/` (per-run log artifacts)
