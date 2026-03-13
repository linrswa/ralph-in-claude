---
name: run
description: "Run Ralph to implement all stories from prd.json. Orchestrates parallel subagent workers in dependency-aware waves. Use when asked to 'run ralph', 'start ralph', or 'implement all stories from prd.json'."
argument-hint: "[prd-path] [max-agents]"
# hooks: see plugin-level hooks/hooks.json
---

# Ralph Dispatcher — Parallel Story Execution

You are the Ralph dispatcher. Your job is to orchestrate the implementation of all user stories from a prd.json file by spawning subagent workers in parallel waves. You use the **TaskCreate/TaskUpdate/TaskList** tools to track story progress with visible, dependency-aware task management.

---

## Procedures

Named subroutines referenced throughout this document. Execute exactly as defined when invoked.

### TYPECHECK(on_fail)

Detect and run the project's typecheck command (look for `package.json` scripts, `tsconfig.json`, `Cargo.toml`, etc.):
```bash
npm run typecheck  # or tsc --noEmit, cargo check, etc.
```
If the project has no typecheck tooling, skip — counts as passed.
On failure, execute the `on_fail` action specified at the call site.

### TIMESTAMP()

Run `date +"%Y-%m-%dT%H:%M:%S%z"` — use local time, not UTC.

### CLEANUP_WORKTREE(story)

**Worktree mode only** — skip in direct mode. Uses dispatch tracking from §3.3.
**Exception:** Tier 3 deferred stories retain their worktrees until conflict resolution completes — do not call this procedure for them.
```bash
git worktree remove --force <worktree-path>
git branch -D ralph-worker-<STORY_ID>
```

### MARK_PASS(story)

1. `TaskUpdate(taskId: storyIdToTaskId[story.id], status: "completed")` — auto-unblocks dependents
2. Update `.ralph-in-claude/prd.json`: set the story's `passes` to `true`
3. Append to `.ralph-in-claude/progress.txt`:
   ```
   ## <TIMESTAMP> - <STORY_ID>: <STORY_TITLE>
   - <summary from subagent report>
   - Files changed: <from subagent report>
   - Learnings: <from subagent report>
   ---
   ```
4. `CLEANUP_WORKTREE(story)`

### GENERATE_REVIEW_PROMPT(extra_context)

Read `references/wave-review-prompt-template.md` and substitute all placeholders:
- `{{WAVE_NUMBER}}` → current wave number
- `{{PROJECT_NAME}}` → prd.json `project`
- `{{SOURCE_PRD}}` → prd.json `sourcePrd`
- `{{PASSED_STORIES}}` → formatted list of passed stories (id, title, description, files changed)
- `{{WAVE_DIFF}}` → output of `git diff $WAVE_START_COMMIT..HEAD`
- `{{CODEBASE_PATTERNS}}` → extracted from progress.txt, or "None yet"
- `{{CONFLICT_CONTEXT}}` → from `extra_context`, or empty string
- `{{NEXT_WAVE_CONTEXT}}` → from `extra_context`, or empty string

### ESCALATE_TO_COORDINATOR(conflict_context)

1. Generate prompt from `references/wave-coordinator-prompt-template.md` — substitute:
   - `{{REVIEWER_REPORT}}` → the complete escalation report from the wave reviewer
   - `{{CONFLICT_CONTEXT}}` → `conflict_context` parameter (or empty string)
   - All other placeholders (`{{WAVE_NUMBER}}`, `{{PROJECT_NAME}}`, `{{SOURCE_PRD}}`, `{{PASSED_STORIES}}`, `{{WAVE_DIFF}}`, `{{CODEBASE_PATTERNS}}`) — same values as the review prompt
2. Spawn Opus wave-coordinator:
   ```
   Task(subagent_type: "ralph:wave-coordinator", description: "Resolve escalated: <context>", prompt: <generated>)
   ```
3. Return the coordinator's report.

### CREATE_REMEDIATION(story, context)

1. **Depth check:** if `story.remediationDepth >= 2`, treat as FAIL instead (prevents infinite chains).
2. `git merge --abort`
3. Create remediation story in prd.json:
   ```json
   {
     "id": "US-REM-<NNN>",
     "title": "Remediate merge conflict: <STORY_ID>",
     "description": "Resolve merge conflict for <STORY_ID> (<STORY_TITLE>). Conflicted files: <files>. Re-apply the story's changes on top of the current branch state.",
     "acceptanceCriteria": ["All conflicted files are resolved", "Story <STORY_ID>'s functionality is preserved", "Typecheck passes"],
     "dependsOn": [<IDs of all passed stories in this wave>],
     "sharedFiles": [],
     "priority": <current story priority>,
     "passes": false,
     "isRemediation": true,
     "remediationDepth": <story.remediationDepth (default 0) + 1>,
     "notes": "Conflict context: <context>"
   }
   ```
4. Create corresponding task with `TaskCreate`, wire dependencies.
5. Mark original story as pending: `TaskUpdate(taskId: storyIdToTaskId[story.id], status: "pending")`
6. Append to story notes: `"Attempt N: merge conflict, remediation <US-REM-NNN> created"`
7. `CLEANUP_WORKTREE(story)`

---

## 0. Parse Arguments

`$ARGUMENTS` may contain up to two positional arguments: `[prd-path] [max-agents]`

1. **First argument** (optional): path to prd.json. Default: `.ralph-in-claude/prd.json`
2. **Second argument** (optional): max subagents per wave. Default: `5`

If `max-agents` is greater than 5, **you MUST use the `AskUserQuestion` tool** before proceeding:

```
Question: "Running more than 5 parallel agents uses significant system resources. Are you sure you want to continue with <N> max agents?"
Options:
  - "Yes, continue with <N> agents"  →  proceed with the user-specified max
  - "No, use the default (5 max agents)"    →  fall back to 5
```

**Do NOT skip this confirmation.** Store the final max-agents value for use in §3.2.

---

## 1. Initialization

1. **Read prd.json** at the path determined in §0.
2. **Verify all required template files exist:** `references/subagent-prompt-template.md`, `references/wave-review-prompt-template.md`, `references/wave-coordinator-prompt-template.md`. If any are missing, report the specific missing files to the user and stop.
3. **Read `.ralph-in-claude/progress.txt`** if it exists — extract the `## Codebase Patterns` section for passing to workers.
4. **Read the source PRD** from the `sourcePrd` field for additional context.
5. **Read `conflictStrategy`** from prd.json (defaults to `"conservative"` if absent). Log which mode is active:
   - `"conservative"` — all sharedFiles overlaps defer to separate waves (maximum safety)
   - `"optimistic"` — only `structural-modify` overlaps defer; `append-only` overlaps run in parallel
6. **Check git branch** — ensure you're on the branch specified by `branchName`. If not:
   - If the branch exists: `git checkout <branchName>`
   - If not: `git checkout -b <branchName>` from `baseBranch` (default: `main`)
7. **Clean up orphan worktrees** from crashed previous runs:
   ```bash
   if [ -d ".ralph-in-claude/worktrees" ]; then
     for wt in .ralph-in-claude/worktrees/*/; do
       git worktree remove --force "$wt" 2>/dev/null
     done
   fi
   git worktree prune
   git branch --list 'ralph-worker-*' | xargs -r git branch -D
   ```
8. **Initialize `storyIdToTaskId`** — internal mapping from story IDs (e.g., `"US-001"`) to TaskCreate-returned task IDs.
9. **Write `.ralph-in-claude/state.json`** — powers the WebGUI Kanban view. Schema (used throughout, updated at wave boundaries):
   ```json
   {
     "status": "running | completed",
     "conflictStrategy": "<conservative | optimistic>",
     "currentWave": 0,
     "workers": [
       {
         "storyId": "<story.id>", "storyTitle": "<story.title>",
         "status": "running | completed | failed",
         "mode": "direct | worktree",
         "worktreeBranch": "<ralph-worker-STORY_ID> | null",
         "worktreePath": "<absolute-path> | null",
         "startedAt": "<timestamp>", "completedAt": "<timestamp> | null",
         "retryCount": 0
       }
     ],
     "failedStories": {
       "<story.id>": { "storyId": "...", "reason": "...", "failedAt": "..." }
     },
     "lastUpdated": "<timestamp>"
   }
   ```
   Use `TIMESTAMP()` for all timestamp fields. Initialize with `status: "running"`, `currentWave: 0`, empty `workers` and `failedStories`.

10. **Subagent types reference:**

    | Subagent Type | Definition File | Purpose |
    |---|---|---|
    | ralph:ralph-worker | agents/ralph-worker.md | Implements a single story |
    | ralph:wave-reviewer | agents/wave-reviewer.md | Post-wave review & conflict resolution |
    | ralph:wave-coordinator | agents/wave-coordinator.md | Escalated issue resolution |

---

## 2. Create Task Graph

Parse the `userStories` array and create a dependency-aware task graph.

### 2.1 Detect Cycles

Before creating any tasks, check for dependency cycles among remaining stories (`passes: false`):

1. Compute in-degree for each remaining story based on `dependsOn` (only counting remaining stories)
2. Start with stories that have in-degree 0
3. Process: remove a story, decrement in-degrees of dependents
4. If all processed → no cycle, continue
5. If stories remain → **report the cycle to the user and stop**

This is critical because the task system silently deadlocks on cycles.

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

After all TaskCreate calls return, record each returned `taskId` in `storyIdToTaskId`.

### 2.3 Wire Dependencies

For stories with non-empty `dependsOn`, issue `TaskUpdate` calls — all in a **single message** (parallel):

```
For each story where dependsOn is non-empty:
  TaskUpdate(
    taskId: storyIdToTaskId[story.id],
    addBlockedBy: story.dependsOn.map(depId => storyIdToTaskId[depId])
  )
```

### 2.4 Mark Already-Completed

After §2.3 completes, mark stories with `passes: true` — all in a **single message** (parallel):

```
For each story where passes is true:
  TaskUpdate(taskId: storyIdToTaskId[story.id], status: "completed")
```

This order matters: wiring dependencies before marking completions ensures `blockedBy` references exist before auto-unblock fires.

---

## 3. Execution Loop (Wave-Based)

Repeat until all stories have `passes: true` or all remaining stories are blocked/failed.

### 3.1 Find Ready Stories

**First, rebuild `storyIdToTaskId` from TaskList** (done every wave to survive context compaction):
1. Call `TaskList` to get all tasks
2. For each task, parse `subject` field to extract story ID — match both `US-NNN` and `US-REM-NNN` formats (everything before the first `:`), map to task ID

**Then, determine retry counts** by reading prd.json and counting `"Attempt N failed:"` entries in each story's `notes` field.

A story is **ready** if ALL true:
- Task `status` is `pending`
- Task `blockedBy` is empty
- Retry count < 3

### 3.2 Select Wave

From ready stories:
1. Sort by `priority` (lowest first)
2. **Normalize sharedFiles** — string entry `"src/index.ts"` → `{ file: "src/index.ts", conflictType: "structural-modify" }`; object entries as-is
3. **Conflict-aware scheduling** — for each candidate, check overlaps with already-selected stories:

   **Conservative (default):** defer on ANY overlap.
   **Optimistic:** defer only if EITHER declares `structural-modify`. Allow parallel if BOTH are `append-only`.

   | Story A | Story B | Parallel? |
   |---------|---------|-----------|
   | append-only | append-only | Yes |
   | append-only | structural-modify | No |
   | structural-modify | structural-modify | No |

   Log deferrals and parallel allowances.
4. Take up to **max-agents** stories (default 5, or value from §0)

### 3.3 Prepare Wave + Spawn Workers

**1. Determine wave mode:**
- 1 story → **Direct mode** (commits on feature branch, no worktree)
- 2+ stories → **Worktree mode** (dispatcher-managed worktrees)

**2. Create worktrees** (worktree mode only):
```bash
git worktree add .ralph-in-claude/worktrees/<STORY_ID> -b ralph-worker-<STORY_ID> HEAD
```
If `git worktree add` fails because the worktree or branch already exists, remove it first with `git worktree remove --force .ralph-in-claude/worktrees/<STORY_ID>` and `git branch -D ralph-worker-<STORY_ID>`, then retry once.

**3. Track dispatch info** per story: `{storyId, mode, branch, worktreePath}`

**4. Generate worker prompts** — for each story:

a. Read `references/subagent-prompt-template.md`
b. Substitute placeholders:
   - `{{STORY_ID}}`, `{{STORY_TITLE}}`, `{{STORY_DESCRIPTION}}` → from story
   - `{{ACCEPTANCE_CRITERIA}}` → markdown checklist from `acceptanceCriteria`
   - `{{STORY_NOTES}}` → story `notes` (or "None")
   - `{{PROJECT_NAME}}` → prd.json `project`
   - `{{SOURCE_PRD}}` → prd.json `sourcePrd`
   - `{{CODEBASE_PATTERNS}}` → from progress.txt, or "None yet"
   - `{{COMPLETED_STORIES}}` → completed story IDs and titles, or "None yet"
   - `{{WORKING_DIRECTORY_INSTRUCTIONS}}` →
     - **Direct:** `"You are working directly on the feature branch. No need to change directories."`
     - **Worktree:** `"As your FIRST action, run: cd <absolute-worktree-path>. All subsequent commands must run from this directory. Do NOT create branches or switch branches."`
c. **If retry** (notes contains `"Attempt N failed:"` entries): append to prompt:
   ```
   ## Previous Attempt Failed
   The previous attempt to implement this story failed:
   - **Reason:** <failure reason from notes>
   - **What was tried:** <summary>
   Please address this in your implementation.
   ```

**5. Update state.json** — set `currentWave` (incremented), populate `workers` array per schema (§1 step 8), set `lastUpdated`.

**6. Spawn** — in a **single message**, issue all calls in parallel:
```
For each story in wave:
  TaskUpdate(taskId: storyIdToTaskId[story.id], status: "in_progress")
  Task(subagent_type: "ralph:ralph-worker", description: "<story.id> - <story.title>", prompt: <generated>)
```

**CRITICAL:** All TaskUpdate and Task calls for a wave MUST be in the same message.
**NOTE:** Workers are spawned **without** `isolation: "worktree"`. The dispatcher manages all worktree lifecycle.

### 3.4 Verify Results & Merge (Four-Tier Pipeline)

When all subagents return, process each story sequentially through the four-tier merge pipeline: Tier 1 (clean merge), Tier 2 (append-only auto-resolve), Tier 3 (defer to wave review), and FAIL handling. In direct mode, typecheck failure triggers a hard reset and FAIL — Tiers 2/3 do not apply.

Read `references/merge-pipeline.md` for the full four-tier merge pipeline.

### 3.5 Wave Review (Conflict Resolution + Consistency Check + Bridge Work)

After the merge pipeline, evaluate all three wave review phases independently — do not skip based on wave size or mode. Phase A resolves deferred merge conflicts via wave-reviewer (and coordinator escalation if needed). Phase B checks cross-story consistency when 2+ stories passed. Phase C prepares bridge work for the next wave's stories.

Read `references/wave-review-process.md` for Phase A (conflict resolution), Phase B (consistency review), and Phase C (bridge work).

### 3.6 Loop

After processing all results from a wave:
1. Re-read `.ralph-in-claude/prd.json`
2. Go to §3.1 — `TaskList` reflects updated dependency state
3. If ready stories exist → continue
4. If no ready stories but incomplete stories remain → report blocked stories and stop
5. If all stories pass → proceed to §4

---

## 4. Completion

When all stories have `passes: true`:
1. Write final state.json: `status: "completed"`, final wave number, all workers with terminal statuses.
2. Report summary: total stories, retries, notable learnings.
3. Show the final state of prd.json.

---

## 5. Constraints

1. **Dispatcher-only writes** — only the dispatcher writes to prd.json, progress.txt, state.json, and calls TaskCreate/TaskUpdate/TaskList.
2. **Worker single commit** — each worker must produce exactly one commit.
3. **Remediation depth cap** — `remediationDepth` capped at 2. Enforced in `CREATE_REMEDIATION`.
4. **Worktree isolation** — only the assigned worker may `cd` into a worktree. The dispatcher creates/removes worktrees and merges branches from the feature branch root — never by entering the worktree directory.
5. **Wave review serialization** — wave review and coordinator run sequentially — each must complete before the next wave begins. Never run reviews in parallel.
6. **No model override** — do NOT set the `model` parameter when spawning subagents. Let each agent's definition (e.g., `wave-reviewer.md`, `ralph-worker.md`) control its own model.
7. **Task tool error handling** — if any TaskCreate or TaskUpdate call fails, stop the current wave, report the error to the user, and do not proceed. Do not attempt to recover silently.
8. **Subagent timeout** — if a subagent does not return within a reasonable timeframe, treat it as a FAIL with reason "worker timeout".

---

## 6. Reminders

- **You are the orchestrator, not the implementer.** Do not write application code yourself. Delegate all implementation to subagent workers via the Task tool.
- **Keep the user informed** — report progress after each wave completes.
- **Task system is ephemeral** — prd.json is the persistent source of truth for story status. Tasks provide real-time visibility and dependency tracking within a session only.
