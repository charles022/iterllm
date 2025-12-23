#!/usr/bin/env python3
from __future__ import annotations

import argparse
import asyncio
import json
import sys
from datetime import datetime, timezone
from pathlib import Path


def utc_timestamp() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


class JsonlLogger:
    def __init__(self, path: Path) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        self._path = path
        self._lock = asyncio.Lock()
        self._seq = 0
        self._file = path.open("a", encoding="utf-8")

    async def log(self, event: dict) -> None:
        async with self._lock:
            self._seq += 1
            payload = {"seq": self._seq, **event}
            self._file.write(json.dumps(payload, ensure_ascii=True) + "\n")
            self._file.flush()

    def close(self) -> None:
        self._file.close()


async def pipe_stdin(proc: asyncio.subprocess.Process, logger: JsonlLogger) -> None:
    loop = asyncio.get_running_loop()
    reader = asyncio.StreamReader()
    protocol = asyncio.StreamReaderProtocol(reader)
    await loop.connect_read_pipe(lambda: protocol, sys.stdin)
    while True:
        line = await reader.readline()
        if not line:
            if proc.stdin:
                proc.stdin.close()
            break
        await logger.log(
            {
                "ts": utc_timestamp(),
                "direction": "client_to_server",
                "bytes": len(line),
                "data": line.decode("utf-8", errors="replace").rstrip("\n"),
            }
        )
        if proc.stdin:
            try:
                proc.stdin.write(line)
                await proc.stdin.drain()
            except BrokenPipeError:
                break


async def pipe_output(
    stream: asyncio.StreamReader,
    output: object,
    logger: JsonlLogger,
    direction: str,
) -> None:
    write = getattr(output, "write")
    flush = getattr(output, "flush")
    while True:
        line = await stream.readline()
        if not line:
            break
        await logger.log(
            {
                "ts": utc_timestamp(),
                "direction": direction,
                "bytes": len(line),
                "data": line.decode("utf-8", errors="replace").rstrip("\n"),
            }
        )
        try:
            write(line)
            flush()
        except BrokenPipeError:
            break


async def run() -> int:
    parser = argparse.ArgumentParser(
        description="Log MCP stdio traffic while proxying to a child process."
    )
    parser.add_argument("--log-dir", required=True, help="Directory for log files.")
    parser.add_argument("--name", default="mcp", help="Label for the server.")
    parser.add_argument("command", nargs=argparse.REMAINDER, help="Command to run.")
    args = parser.parse_args()

    command = list(args.command)
    if command and command[0] == "--":
        command = command[1:]
    if not command:
        raise SystemExit("Expected a command to run after --.")

    log_dir = Path(args.log_dir)
    traffic_path = log_dir / f"{args.name}_traffic.jsonl"
    logger = JsonlLogger(traffic_path)
    await logger.log(
        {
            "ts": utc_timestamp(),
            "direction": "lifecycle",
            "event": "start",
            "command": command,
        }
    )

    proc = await asyncio.create_subprocess_exec(
        *command,
        stdin=asyncio.subprocess.PIPE,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
    )

    returncode: int | None = None
    try:
        stdin_task = asyncio.create_task(pipe_stdin(proc, logger))
        stdout_task = asyncio.create_task(
            pipe_output(proc.stdout, sys.stdout.buffer, logger, "server_to_client")
        )
        stderr_task = asyncio.create_task(
            pipe_output(proc.stderr, sys.stderr.buffer, logger, "server_stderr")
        )
        returncode = await proc.wait()
        if not stdin_task.done():
            stdin_task.cancel()
        await asyncio.gather(stdin_task, stdout_task, stderr_task, return_exceptions=True)
    finally:
        await logger.log(
            {
                "ts": utc_timestamp(),
                "direction": "lifecycle",
                "event": "exit",
                "returncode": returncode,
            }
        )
        logger.close()

    return returncode


def main() -> None:
    try:
        exit_code = asyncio.run(run())
    except KeyboardInterrupt:
        exit_code = 130
    raise SystemExit(exit_code)


if __name__ == "__main__":
    main()
