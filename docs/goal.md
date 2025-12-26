### System Architecture: Sequential Agentic Workflow

**Objective**
To overcome the performance degradation common in LLMs (e.g., `codex-cli`) when processing large batches of tasks simultaneously. Instead of attempting all tasks in a single prompt, this system iterates through items sequentially to maintain high-quality attention on each individual unit of work.

**Core Components**

1. **`agent-scheduler`:** The manager responsible for task identification, prompt calibration, and final reporting.
2. **`agent-executor`:** The worker responsible for executing individual tasks and generating file outputs.
3. **Automation Script (Python):** A dynamic script generated to handle the iterative looping and file management.

---

### Workflow Process

#### 1. Initialization and Parsing

* **Input:** The user provides a high-level request to `agent-scheduler`.
* **Task breakdown:** `agent-scheduler` parses the request, identifies the specific items to be processed, and writes them to a **Todo List File** (one item per line).
* **Context:** `agent-scheduler` initializes a session with `agent-executor`. Both agent conversations remain open throughout the entire process to preserve context.

#### 2. Prompt Calibration (The "First Item" Loop)

Before automating the batch, `agent-scheduler` verifies the workflow using only the first item from the Todo List.

1. **Drafting:** `agent-scheduler` generates a specific prompt for the first item.
2. **Testing:** It sends this prompt to `agent-executor`.
3. **Evaluation:**
* **If the response is inadequate** (e.g., missing files, hallucinations): `agent-scheduler` adjusts the prompt and retries the first item.
* **If the response is adequate:** The prompt template is "locked in."


4. **Script Generation:** Once the prompt is verified, `agent-scheduler` generates a Python script designed to automate the remaining items using the successful prompt template.

#### 3. Automated Execution (The Python Script)

The generated Python script executes the bulk of the work to ensure consistency:

* **Input:** It ingests the "locked" prompt template and the Todo List File.
* **Iteration:** The script iterates through the remaining items sequentially.
* **Dynamic Prompting:** For each iteration, the script injects the current item into the prompt template and sends it to `agent-executor`.
* **Output Handling:**
* The prompt explicitly instructs `agent-executor` to write the result to a unique file (e.g., `output_[item_name].ext`).
* `agent-executor` communicates completion via stdout using a specific "hook" or termination signal (defined in `AGENTS.md`) so the Python script knows when to proceed to the next iteration.



#### 4. Aggregation and Finalization

* **Concatenation:** Once all items are processed, the Python script joins all individual output files into a single **Master Results File**, ensuring clear separation between parts and maintaining the correct file type.
* **Handoff:** The Python script prompts `agent-scheduler` with the name of the Master Results File, signaling that the batch process is complete.
* **Reporting:** `agent-scheduler` analyzes the completion status and provides a final summary to the user.

---

### Technical Requirements

* **Session Persistence:** The underlying infrastructure must allow both `agent-scheduler` and `agent-executor` sessions to remain active for the duration of the script's execution.
* **`AGENTS.md` Configuration:** Both agents must be configured to end their stdout responses with a distinct string/hook. This allows the Python script to programmatically detect when an agent has finished "speaking" and is ready for the next loop.
* **File Naming Logic:** The prompt template must support dynamic file naming so that `agent-executor` creates a distinct file for every iteration, preventing overwrites before concatenation.
