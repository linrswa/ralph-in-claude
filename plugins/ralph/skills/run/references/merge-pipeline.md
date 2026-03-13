# Four-Tier Merge Pipeline (Section 3.4)

**Capture wave-start commit before processing:**
```bash
WAVE_START_COMMIT=$(git rev-parse HEAD)
```

When all subagents return, process each story **sequentially** (to serialize merges). Merge stories one at a time, never in parallel. Look up dispatch info from §3.3.

For each completed worker:

1. **Parse subagent report** — extract: Status (PASS/FAIL), Commit hash, Files changed, Summary, Learnings.

2. **If PASS:**

   a. `TYPECHECK(on_fail: see step 2e for direct mode, Tier 2/3 for worktree mode)`

   b. **Merge** (mode-dependent):
      - **Direct:** skip merge — verify commit hash matches HEAD via `git log -1 --format=%H`
      - **Worktree:** `git -c merge.conflictStyle=diff3 merge --no-ff ralph-worker-<STORY_ID> -m "feat: <STORY_ID> - <STORY_TITLE>"`

   c. **Tier 1 — Clean merge:** `MARK_PASS(story)`. Continue to next story.

   d. **Tier 2 — Append-only auto-resolve** (worktree mode only):
      1. List conflicted files: `git diff --name-only --diff-filter=U`
      2. Check if ALL hunks are append-only: the base section (between `|||||||` and `=======` markers from diff3) is empty for ALL hunks in ALL files
      3. If yes: strip conflict markers (`<<<<<<<`, `|||||||`, `=======`, `>>>>>>>`), `git add <files>`, `git commit --no-edit`, log auto-resolve, `MARK_PASS(story)`
      4. If any non-empty base → fall through to Tier 3

   e. **Direct-mode typecheck failure** (direct mode only):
      If typecheck fails in direct mode: `git reset --hard HEAD~1`, treat as FAIL (step 3). Do not proceed to Tier 2/3.

   f. **Tier 3 — Defer to wave review** (worktree mode only):
      1. `git merge --abort`
      2. **Do NOT call `CLEANUP_WORKTREE`** — worktree/branch needed for Phase A re-merge
      3. Track: `deferredStories.push({storyId, storyTitle, branch, worktreePath, conflictedFiles, reason: "merge conflict"})`
      4. Log deferral. Do NOT update task status — stays `in_progress`.

3. **If FAIL** (worker reported FAIL or typecheck failed):
   - Worktree mode: `CLEANUP_WORKTREE(story)`
   - Direct mode (dirty state): `git checkout -- . && git clean -fd`
   - `TaskUpdate(taskId: storyIdToTaskId[story.id], status: "pending")`
   - Append `"Attempt N failed: <reason>"` to story's `notes` in prd.json
   - If retry count >= 3: report to user with all attempt reasons and suggest: split the story, add implementation notes, or skip. Error report format by scenario:
     - **Retry exhaustion:** list each attempt number + actions taken + failure reason
     - **Cycle detection:** list the story IDs forming the cycle (e.g., `US-003 → US-005 → US-003`)
     - **Blocked stories:** list each blocked story ID with its unmet `dependsOn` IDs

**After each story result**, update state.json: set worker `status`/`completedAt`, add to `failedStories` if failed, update `lastUpdated`.
