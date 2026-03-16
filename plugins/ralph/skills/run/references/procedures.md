# Dispatcher Procedures

Named subroutines referenced throughout the dispatcher flow. Execute exactly as defined when invoked.

## TYPECHECK(on_fail)

Detect and run the project's typecheck command (look for `package.json` scripts, `tsconfig.json`, `Cargo.toml`, etc.):
```bash
npm run typecheck  # or tsc --noEmit, cargo check, etc.
```
If the project has no typecheck tooling, skip — counts as passed.
On failure, execute the `on_fail` action specified at the call site.

## TIMESTAMP()

Run `date +"%Y-%m-%dT%H:%M:%S%z"` — use local time, not UTC.

## CLEANUP_WORKTREE(story)

**Worktree mode only** — skip in direct mode. Uses dispatch tracking from §3.3.
**Exception:** Tier 3 deferred stories retain their worktrees until conflict resolution completes — do not call this procedure for them.
```bash
git worktree remove --force <worktree-path>
git branch -D ralph-worker-<STORY_ID>
```

## MARK_PASS(story)

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

## GENERATE_REVIEW_PROMPT(extra_context)

Read `references/wave-review-prompt-template.md` and substitute all placeholders:
- `{{WAVE_NUMBER}}` → current wave number
- `{{PROJECT_NAME}}` → prd.json `project`
- `{{SOURCE_PRD}}` → prd.json `sourcePrd`
- `{{PASSED_STORIES}}` → formatted list of passed stories (id, title, description, files changed)
- `{{WAVE_DIFF}}` → output of `git diff $WAVE_START_COMMIT..HEAD`
- `{{CODEBASE_PATTERNS}}` → extracted from progress.txt, or "None yet"
- `{{CONFLICT_CONTEXT}}` → from `extra_context`, or empty string
- `{{NEXT_WAVE_CONTEXT}}` → from `extra_context`, or empty string

## ESCALATE_TO_COORDINATOR(conflict_context)

1. Generate prompt from `references/wave-coordinator-prompt-template.md` — substitute:
   - `{{REVIEWER_REPORT}}` → the complete escalation report from the wave reviewer
   - `{{CONFLICT_CONTEXT}}` → `conflict_context` parameter (or empty string)
   - All other placeholders (`{{WAVE_NUMBER}}`, `{{PROJECT_NAME}}`, `{{SOURCE_PRD}}`, `{{PASSED_STORIES}}`, `{{WAVE_DIFF}}`, `{{CODEBASE_PATTERNS}}`) — same values as the review prompt
2. Spawn Opus wave-coordinator:
   ```
   Task(subagent_type: "ralph:wave-coordinator", description: "Resolve escalated: <context>", prompt: <generated>)
   ```
3. Return the coordinator's report.

## CREATE_REMEDIATION(story, context)

1. **Depth check:** if `story.remediationDepth >= 2`, treat as FAIL instead (prevents infinite remediation chains that burn context without converging).
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
