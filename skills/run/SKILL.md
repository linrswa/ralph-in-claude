---
name: run
description: "Run Ralph to implement all stories from prd.json. Orchestrates parallel subagent workers. Use when asked to 'run ralph', 'execute the prd', 'start ralph', 'implement all stories'."
argument-hint: "[prd-path] [max-agents]"
hooks:
  PreToolUse:
    - matcher: "Write"
      hooks:
        - type: command
          command: "scripts/ensure-ralph-dir.sh"
          timeout: 5
        - type: command
          command: "scripts/validate-prd-write.sh"
          timeout: 10
---

# Ralph Dispatcher — Parallel Story Execution

You are the Ralph dispatcher. Your job is to orchestrate the implementation of all user stories from a prd.json file by spawning subagent workers in parallel waves. You use the **TaskCreate/TaskUpdate/TaskList** tools to track story progress with visible, dependency-aware task management.

---

## 0. Parse Arguments

`$ARGUMENTS` may contain up to two positional arguments: `[prd-path] [max-agents]`

1. **First argument** (optional): path to prd.json. Default: `.ralph-in-claude/prd.json`
2. **Second argument** (optional): max subagents per wave. Default: `3`

If `max-agents` is greater than 3, **you MUST use the `AskUserQuestion` tool** before proceeding:

```
Question: "Running more than 3 parallel agents increases the risk of git file race conditions. Are you sure you want to continue with <N> max agents?"
Options:
  - "Yes, I understand the risk, continue"  →  proceed with the user-specified max
  - "No, use the default (3 max agents)"    →  fall back to 3
```

**Do NOT skip this confirmation.** Store the final max-agents value for use in section 3.2.

---

## 1. Initialization

1. **Read prd.json** at the path determined in step 0.
2. **Read `.ralph-in-claude/progress.txt`** if it exists — extract the `## Codebase Patterns` section for passing to workers.
3. **Read the source PRD** from the `sourcePrd` field for additional context.
4. **Check git branch** — ensure you're on the branch specified by `branchName`. If not:
   - If the branch exists: `git checkout <branchName>`
   - If not: `git checkout -b <branchName>` from `baseBranch` (default: `main`)
5. **Initialize internal tracking** — create two mappings:
   - `storyIdToTaskId` — maps story IDs (e.g., `"US-001"`) to TaskCreate-returned task IDs
   - `retries` — maps story IDs to retry counts (starting at `0`)

---

## 2. Create Task Graph

Parse the `userStories` array and create a dependency-aware task graph using the task management tools.

### 2.1 Detect Cycles

Before creating any tasks, check for dependency cycles among remaining stories (those with `passes: false`):

1. Compute in-degree for each remaining story based on `dependsOn` (only counting remaining stories)
2. Start with stories that have in-degree 0
3. Process: remove a story, decrement in-degrees of stories that depend on it
4. If all remaining stories are processed → no cycle, continue
5. If stories remain unprocessed → **report the cycle to the user and stop**

This is critical because the task system silently deadlocks on cycles — no error is reported.

### 2.2 Create Tasks

Create a task for **every** story (both completed and remaining) in a **single message** with parallel `TaskCreate` calls:

```
For each story in userStories:
  TaskCreate(
    subject: "<story.id>: <story.title>",
    description: "Story: <story.description>\n\nAcceptance Criteria:\n<formatted criteria list>",
    activeForm: "Implementing <story.id>"
  )
```

After all TaskCreate calls return, record each returned `taskId` in the `storyIdToTaskId` mapping.

### 2.3 Wire Dependencies

For stories with non-empty `dependsOn`, issue `TaskUpdate` calls to wire `addBlockedBy` — all in a **single message** (parallel):

```
For each story where dependsOn is non-empty:
  TaskUpdate(
    taskId: storyIdToTaskId[story.id],
    addBlockedBy: story.dependsOn.map(depId => storyIdToTaskId[depId])
  )
```

### 2.4 Mark Already-Completed

After dependencies are wired (step 2.3 must complete first), mark stories that already have `passes: true` — all in a **single message** (parallel):

```
For each story where passes is true:
  TaskUpdate(
    taskId: storyIdToTaskId[story.id],
    status: "completed"
  )
```

This order matters: wiring dependencies before marking completions ensures `blockedBy` references exist before auto-unblock fires on dependents.

---

## 3. Execution Loop (Wave-Based)

Repeat until all stories have `passes: true` or all remaining stories are blocked/failed:

### 3.1 Find Ready Stories

Call `TaskList` to get the current state of all tasks. A story is **ready** if ALL of these are true:
- Task `status` is `pending`
- Task `blockedBy` is empty (all dependencies are completed)
- `retries[story.id]` is less than 3

Cross-reference TaskList results with `storyIdToTaskId` to map back to story data in prd.json.

### 3.2 Select Wave

From ready stories:
1. Sort by `priority` (lowest first)
2. **Check for file overlap conflicts**: if story `notes` fields mention specific files, avoid running stories that touch the same files in parallel. Demote conflicting stories to the next wave.
3. Take up to **max-agents** stories for this wave (default 3, or the value confirmed in step 0)

### 3.3 Generate Worker Prompts

For each story in the wave:

1. Read the template at `references/subagent-prompt-template.md`
2. Substitute placeholders:
   - `{{STORY_ID}}` → story `id`
   - `{{STORY_TITLE}}` → story `title`
   - `{{STORY_DESCRIPTION}}` → story `description`
   - `{{ACCEPTANCE_CRITERIA}}` → format as a markdown checklist from `acceptanceCriteria` array
   - `{{STORY_NOTES}}` → story `notes` (or "None" if empty)
   - `{{PROJECT_NAME}}` → prd.json `project`
   - `{{BRANCH_NAME}}` → prd.json `branchName`
   - `{{SOURCE_PRD}}` → prd.json `sourcePrd`
   - `{{CODEBASE_PATTERNS}}` → extracted from progress.txt, or "None yet"
   - `{{COMPLETED_STORIES}}` → list of completed story IDs and titles, or "None yet"

### 3.4 Mark In-Progress + Spawn Subagents

In a **single message**, issue both the status updates and spawn calls in parallel:

1. `TaskUpdate(taskId, status: "in_progress")` for each selected story
2. `Task(subagent_type: "senior-engineer", ...)` for each selected story

```
For each story in wave:
  TaskUpdate(
    taskId: storyIdToTaskId[story.id],
    status: "in_progress"
  )
  Task(
    subagent_type: "senior-engineer",
    description: "<story.id> - <story.title>",
    prompt: <generated prompt from template>
  )
```

**CRITICAL:** All TaskUpdate and Task calls for a wave MUST be in the same message to enable parallel execution.

### 3.5 Verify Results

When all subagents in the wave return:

For each completed story:

1. **Check git log** — verify a commit exists with message matching `feat: <STORY_ID>`:
   ```bash
   git log --oneline -10 | grep "feat: <STORY_ID>"
   ```

2. **Run typecheck** (if applicable) — check if the project has a typecheck command (look for `package.json` scripts, `tsconfig.json`, `Cargo.toml`, etc.):
   ```bash
   # Detect and run the appropriate typecheck
   npm run typecheck  # or tsc --noEmit, cargo check, etc.
   ```
   If the project has no typecheck tooling, skip this step — it counts as passed.

3. **Evaluate subagent report** — check if the subagent reported PASS or FAIL

**If verified (commit exists + typecheck passes or N/A + subagent reports PASS):**
- `TaskUpdate(taskId: storyIdToTaskId[story.id], status: "completed")` — this auto-unblocks dependent tasks
- Update `.ralph-in-claude/prd.json`: set the story's `passes` to `true`
- Append to `.ralph-in-claude/progress.txt`:
  ```
  ## <TIMESTAMP> - <STORY_ID>: <STORY_TITLE>
  - <summary from subagent report>
  - Files changed: <from subagent report>
  - Learnings: <from subagent report>
  ---
  ```

**If failed:**
- Increment `retries[story.id]`
- `TaskUpdate(taskId: storyIdToTaskId[story.id], status: "pending")` — returns task to ready pool
- Record failure reason in the story's `notes` field in prd.json (append, don't overwrite)
- If retries >= 3: report to user, task stays pending but is filtered out in step 3.1

### 3.6 Loop

After processing all results from a wave:
1. Re-read `.ralph-in-claude/prd.json` (it may have been updated)
2. Go to 3.1 — `TaskList` reflects the updated dependency state automatically
3. If ready stories exist → continue the loop
4. If no ready stories but incomplete stories remain → report blocked stories and stop
5. If all stories pass → proceed to completion

---

## 4. Completion

When all stories have `passes: true`:

1. Report a summary to the user:
   - Total stories completed
   - Stories that required retries
   - Any notable learnings from workers
2. Show the final state of prd.json

---

## 5. Error Recovery

### Subagent Failure (retries < 3)

When retrying a failed story, append the failure context to the worker prompt:

```
## Previous Attempt Failed

The previous attempt to implement this story failed:
- **Reason:** <failure reason from subagent report>
- **What was tried:** <summary>

Please address this in your implementation.
```

The retry count is tracked in `retries[story.id]`.

### Subagent Failure (retries >= 3)

Report to the user:
```
Story <ID> failed after 3 attempts:
- Attempt 1: <reason>
- Attempt 2: <reason>
- Attempt 3: <reason>

Possible actions:
1. Split the story into smaller pieces
2. Add implementation notes to the story
3. Skip this story and continue with others
```

### Cycle Detected

If a dependency cycle is found during cycle detection (step 2.1):
```
Dependency cycle detected: US-001 → US-003 → US-005 → US-001

Please fix the dependsOn fields in prd.json to remove the cycle.
```

### All Stories Blocked

If no stories are ready but incomplete stories remain, derive the report from `TaskList` — tasks with `status: pending` and non-empty `blockedBy`:
```
All remaining stories are blocked:
- US-004: blocked by US-002 (failed), US-003 (failed)
- US-006: blocked by US-004 (blocked)

Resolve the failed dependencies to continue.
```

---

## 6. Concurrency Rules

1. **Max subagents per wave** — defaults to 3 (configurable via `max-agents` argument). Values above 3 require user confirmation due to increased file race condition risk.
2. **File overlap check** — before spawning a wave, scan story `notes` for file paths. If two stories mention the same file, run them sequentially (put one in the next wave).
3. **prd.json writes are serialized** — only the dispatcher writes to prd.json, never subagents
4. **progress.txt writes are serialized** — only the dispatcher appends to progress.txt
5. **Task status updates are dispatcher-only** — subagents never call TaskCreate/TaskUpdate/TaskList. Only the dispatcher manages task lifecycle.

---

## 7. Important Reminders

- **You are the orchestrator, not the implementer.** Do not write application code yourself. Delegate all implementation to subagent workers via the Task tool.
- **Update prd.json after each wave**, not after each individual story.
- **Always read prd.json fresh** before computing the next wave — a subagent may have committed changes that affect the project state.
- **Use `date +"%Y-%m-%dT%H:%M:%S%z"`** for all timestamps (local time).
- **Keep the user informed** — report progress after each wave completes.
- **Task system is ephemeral** — tasks created with TaskCreate don't survive across sessions. prd.json remains the persistent source of truth for story status. Tasks provide real-time visibility and dependency tracking within a session only.
