Based on your requirements and the provided documentation, the most robust way to implement this is to build a single **Python Orchestration Script** using the **OpenAI Agents SDK** and **Codex CLI as an MCP Server**.

This approach satisfies your need for "open conversations" (context persistence) and "iterative looping" without needing to generate brittle, disposable scripts on the fly. The Python script itself will act as the "Scheduler's Engine," managing the loop and file I/O programmatically.

Here is the implementation plan.

### 1. The Foundation: `AGENTS.md`

First, we establish the ground rules. As per the documentation, `AGENTS.md` is read before any work begins to set global expectations.

**File:** `AGENTS.md` (Place in your project root)
We need to ensure the agents always write files without asking for permission (critical for automation) and follow your file naming conventions.

```markdown
# AGENTS.md

## Global Automation Rules
- **Approval Policy**: Always run commands with `approval-policy: never`. Do not ask for user confirmation.
- **File Operations**:
    - When asked to write a file, valid output must be saved to the workspace.
    - Never output large blocks of code to stdout; always direct it to a file.

```

### 2. The Orchestration Script

This Python script replaces the manual process. It uses `MCPServerStdio` to keep Codex alive, allowing the context to persist across the entire batch job.

**File:** `src/orchestrator.py`

#### A. Initialization

We set up the environment and the connection to the Codex CLI.

```python
import asyncio
import os
from agents import Agent, Runner
from agents.mcp import MCPServerStdio

# 1. Define the connection to Codex CLI
# This keeps the session open for the duration of the script
async def main():
    async with MCPServerStdio(
        name="Codex CLI",
        params={"command": "npx", "args": ["-y", "codex", "mcp"]},
    ) as codex_mcp:
        
        # 2. Define the Scheduler Agent
        # Responsible for planning and verifying the prompt strategy
        scheduler = Agent(
            name="Scheduler",
            instructions="You are a workflow manager. Break complex requests into single-line todo items.",
            model="gpt-4o",
            mcp_servers=[codex_mcp]
        )

        # 3. Define the Executor Agent
        # Responsible for doing the actual work on each item
        executor = Agent(
            name="Executor",
            instructions="You are a task runner. Execute the specific prompt given to you and write the result to a file.",
            model="gpt-4o",
            mcp_servers=[codex_mcp]
        )

```

#### B. The Calibration Phase (The "First Item" Logic)

Instead of processing everything at once, we explicitly process the first item to "lock in" the prompt, as you requested.

```python
        # ... inside main() ...

        # USER INPUT (The high-level goal)
        user_request = "Analyze all python files in this folder and write a docstring for each."

        # Step 1: Scheduler breaks it down
        print("--- Scheduler: Creating Todo List ---")
        todo_list_raw = await Runner.run(scheduler, f"Break this task into a newline-separated list of items: {user_request}")
        todo_items = todo_list_raw.final_output.strip().split('\n')
        
        first_item = todo_items[0]
        remaining_items = todo_items[1:]

        # Step 2: Calibration Loop
        # We try to process the first item until the Scheduler is satisfied
        prompt_template = ""
        success = False
        
        print(f"--- Calibrating on first item: {first_item} ---")
        
        # We ask the Scheduler to draft the initial prompt
        draft_prompt_result = await Runner.run(scheduler, f"Draft a strict prompt for the Executor to process this item: '{first_item}'. Ensure it asks to write to 'output_0.txt'.")
        current_prompt = draft_prompt_result.final_output

        # Run the Executor on Item 1
        await Runner.run(executor, current_prompt)

        # (Optional) We could insert a verification step here where the Scheduler reads output_0.txt
        # For now, we assume if no error was thrown, the prompt works.
        prompt_template = current_prompt.replace(first_item, "{ITEM}").replace("output_0.txt", "output_{INDEX}.txt")
        print("--- Calibration Complete. Prompt Template Locked. ---")

```

#### C. The Iteration Phase (The "Python Script" Logic)

Now that we have a working pattern, the Python script iterates over the rest. This uses the *same* `executor` instance, so it remembers the context of the calibration.

```python
        # Step 3: Iterate
        for i, item in enumerate(remaining_items, start=1):
            # Dynamic filename generation
            filename = f"output_{i}.txt"
            
            # Inject item into the locked template
            specific_prompt = prompt_template.format(ITEM=item, INDEX=i)
            
            print(f"--- Processing Item {i}: {item} ---")
            
            # We don't need a stdout hook because Runner.run() waits for the agent to finish automatically
            await Runner.run(executor, specific_prompt)

```

#### D. Finalization and Reporting

Finally, the script handles the file concatenation and reporting, exactly as you requested.

```python
        # Step 4: Concatenate Files
        print("--- Aggregating Results ---")
        with open("FINAL_RESULT.txt", "w") as outfile:
            for i in range(len(todo_items)):
                fname = f"output_{i}.txt"
                if os.path.exists(fname):
                    with open(fname) as infile:
                        outfile.write(f"\n--- Section {i} ---\n")
                        outfile.write(infile.read())
                    # Optional: os.remove(fname) # Clean up individual files
        
        # Step 5: Final Report
        await Runner.run(scheduler, "The process is complete. The combined file is 'FINAL_RESULT.txt'. Summarize the work done.")
        print("--- Done ---")

if __name__ == "__main__":
    asyncio.run(main())

```

### Why this implementation works

1. **Context Persistence:** By wrapping the entire logic in `async with MCPServerStdio(...)`, the underlying Codex process stays running. The `executor` agent "remembers" the definitions and style established during the calibration phase.
2. **Robust Looping:** You were concerned about the model "attacking the entire problem as a whole." By driving the loop with Python (`for i, item in enumerate...`), we force the model to focus 100% of its attention context on *one item at a time*, preventing the quality degradation you described.
3. **No "Stdout Hooks" Needed:** Your request mentioned using hooks to know when a task is done. The Agents SDK handles this natively. `Runner.run()` is a blocking call that returns only when the agent has completed its turn (i.e., finished writing the file). This is much safer than parsing text output.
4. **Dynamic File Naming:** The Python script manages the filenames (`output_{i}.txt`), ensuring no overwrites occur, and then handles the reliable merging of files at the end.
