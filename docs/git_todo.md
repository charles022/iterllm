### Objective

Safely integrate **Codex Cloud–generated changes** into a local Git repository without risking accidental application to the wrong directory or contaminating existing local work.

---

### Intent

Because `codex cloud apply` writes changes to **whatever directory it is executed in**, the workflow must:

1. **Preserve any existing local changes**
2. **Apply Codex changes to a clean branch based on `origin/main`**
3. **Merge Codex changes back into the local working branch**
4. **Push all resulting history to the remote repository**

---

### High-Level Procedure

1. **Capture current local state**
   Commit or stash any uncommitted local changes to ensure a clean working tree.

2. **Create a clean Codex branch**
   Fetch from `origin` and create a new branch directly from `origin/main` to match Codex’s assumed baseline.

3. **Apply Codex changes in isolation**
   Run `codex cloud apply` from the repository root while on the new branch, then commit the applied changes.

4. **Merge into local working branch**
   Switch back to the original local branch, restore stashed changes if applicable, and merge the Codex branch.

5. **Push to origin**
   Push both the updated working branch and the Codex branch for traceability and auditability.

---

### Outcome

* Codex changes are **isolated, reviewable, and reversible**
* Local work is **never overwritten or lost**
* The repository history clearly distinguishes **human changes vs. Codex-applied changes**
* All results are safely synchronized with `origin`

This procedure ensures correctness, reproducibility, and minimal risk when using `codex cloud apply`.

