---
name: sync-task-state
description: Enforces reading and updating the project state log in Agent-task-record
license: MIT
compatibility: opencode
metadata:
  audience: builder-agents
  workflow: state-management
---

## What I do

- Force the agent to read `Agent-task-record/PROJECT_STATE.md` before starting any coding task to understand the architecture, milestones, and active context.
- Prevent the agent from losing track of the broader project goals during execution.
- Update `Agent-task-record/PROJECT_STATE.md` upon task completion, checking off finished items and defining the target for the next session.

## When to use me

Use this automatically at the beginning of a new development session, and at the very end before completing the interaction. Ask clarifying questions if the state file is missing or corrupted.

## Execution Rules

You MUST strictly follow this lifecycle for every task:

1. **Initialization (READ):** - Before writing or editing any source code, use the appropriate tool (e.g., `bash` or `read`) to output the contents of `Agent-task-record/PROJECT_STATE.md`.
   - Analyze the `# Current Active Context` to understand your immediate objective.

2. **Execution (ACT):** - Perform the requested coding tasks, keeping the project's architectural guidelines in mind. 
   - Ensure your code changes align with the current phase in the `# Milestone Tracker`.

3. **Finalization (WRITE):** - Once your coding task is completed and verified, you MUST update `Agent-task-record/PROJECT_STATE.md`.
   - Change `[ ]` to `[x]` for the specific tasks you just completed in the `# Milestone Tracker`.
   - Rewrite the `# Current Active Context` section. Clearly state the "Target for next session" so the next agent knows exactly where to pick up.
