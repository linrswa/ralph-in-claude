# Wave Review Process (Section 3.5)

**Do NOT skip this section based on wave size or mode.** Each phase has its own skip condition — you MUST evaluate all three phases (A, B, C) independently, even for single-story or direct-mode waves. Phase C (bridge work) commonly applies to single-story waves.

## Phase A: Conflict Resolution

**Skip if** `deferredStories` is empty.

For each deferred story (sequentially):

1. Re-merge: `git -c merge.conflictStyle=diff3 merge --no-ff <branch> -m "feat: <STORY_ID> - <STORY_TITLE>"`
2. Capture conflicted files: `git diff --name-only --diff-filter=U`
3. Build `{{CONFLICT_CONTEXT}}`:
   ```markdown
   ## Conflict Resolution Task

   A merge conflict occurred when merging story **<STORY_ID>: <STORY_TITLE>** into the feature branch.

   **Story details:**
   - **ID:** <STORY_ID>
   - **Title:** <STORY_TITLE>
   - **Description:** <STORY_DESCRIPTION>
   - **Acceptance Criteria:** <formatted criteria list>

   **Conflicted files:** <list>

   **Your primary task:** Resolve the merge conflict in the working tree.
   **Both sides' functionality must be preserved.**
   ```
4. `GENERATE_REVIEW_PROMPT(extra_context: {CONFLICT_CONTEXT: <above>})`
5. Spawn: `Task(subagent_type: "ralph:wave-reviewer", description: "Resolve conflict: <STORY_ID>", prompt: <generated>)`
6. **Parse report:**
   - **FIXED/CLEAN:** `TYPECHECK(on_fail: git reset --hard HEAD~1, treat as ESCALATE)`. On pass → `MARK_PASS(story)`.
   - **ESCALATE:** `ESCALATE_TO_COORDINATOR(conflict_context)`. Parse coordinator report:
     - **FIXED:** `TYPECHECK(on_fail: git reset --hard HEAD~1, treat as REMEDIATION)`. On pass → `MARK_PASS(story)`.
     - **REMEDIATION/FAIL:** `CREATE_REMEDIATION(story, context)`

## Phase B: Consistency Review

**Skip if** fewer than 2 stories passed (including Phase A resolutions).

1. `GENERATE_REVIEW_PROMPT(extra_context: {})` — empty `CONFLICT_CONTEXT` and `NEXT_WAVE_CONTEXT`
2. Spawn: `Task(subagent_type: "ralph:wave-reviewer", description: "Review wave <N> consistency", prompt: <generated>)`
3. **Parse report:**
   - **CLEAN:** log, continue.
   - **FIXED:** `TYPECHECK(on_fail: git reset --hard HEAD~1, treat as ESCALATE)`. On pass → log fixes, append to progress.txt.
   - **ESCALATE:** `ESCALATE_TO_COORDINATOR(conflict_context: "")`. Parse coordinator report:
     - **FIXED:** `TYPECHECK(on_fail: git reset --hard HEAD~1, treat as REMEDIATION)`. On pass → log.
     - **REMEDIATION:** create `US-REM-NNN` stories in prd.json (`dependsOn` current wave's passed stories), create tasks with `TaskCreate`, wire dependencies.

## Phase C: Bridge Work

**Skip if:** all stories pass (no next wave) OR no stories are ready for the next wave.

1. Peek at Wave N+1 — identify ready stories using §3.1 logic on updated prd.json. Gather each story's id, title, description, acceptance criteria, sharedFiles.
2. Build `{{NEXT_WAVE_CONTEXT}}`:
   ```markdown
   ## Bridge Work — Prepare for Wave <N+1>

   The following stories are ready for the next wave and will be implemented in parallel by worker agents:

   <for each upcoming story:>
   - **<STORY_ID>: <STORY_TITLE>** — <STORY_DESCRIPTION>
     Acceptance criteria: <formatted criteria list>
     Shared files: <sharedFiles list or "none">

   Review the current codebase state after Wave <N> and prepare it for these upcoming stories. Use your judgment — typical bridge work includes installing new dependencies, creating shared scaffolding, setting up barrel files, or fixing anything that would cause redundant work across parallel workers.
   ```
3. `GENERATE_REVIEW_PROMPT(extra_context: {NEXT_WAVE_CONTEXT: <above>})`
4. Spawn: `Task(subagent_type: "ralph:wave-reviewer", description: "Bridge prep for wave <N+1>", prompt: <generated>)`
5. **Parse report:**
   - **CLEAN:** log, continue.
   - **FIXED:** `TYPECHECK(on_fail: git reset --hard HEAD~1, log "Bridge prep failed typecheck, rolling back")`. On pass → log, append to progress.txt.
   - **ESCALATE:** Do NOT escalate to coordinator. Log `"Bridge prep skipped (reviewer escalated)"`.
