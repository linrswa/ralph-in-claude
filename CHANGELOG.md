# Changelog

All notable changes to this project are documented in this file.

## v0.4.8

- Fixed review issues in prd, convert, and run skills.
- Added plugin update instructions to README.

## v0.4.7

- Improved all three ralph skills (`prd`, `convert`, `run`) based on quality review.

## v0.4.6

- Added cleanup rules to ralph-worker agent (remove debug artifacts, unused imports, etc.).

## v0.4.5

- Moved plugin files to `plugins/ralph/` sub-directory for clean marketplace install.
- Renamed marketplace from `ralph-marketplace` to `ralph-in-claude`.
- Added `marketplace.json` for plugin discovery.

## v0.4.4

- Added "no model override" constraint — dispatcher must not set the `model` parameter when spawning subagents; each agent definition controls its own model.
- Clarified phase/wave terminology: "phase" for PRD story grouping, "wave" reserved for `ralph:run` parallel execution.

## v0.4.3

- Strengthened §3.5 skip guard to prevent dispatcher from skipping Phase C.
- Updated Tier 3 documentation to reflect wave-reviewer pipeline.

## v0.4.2

- Fixed Phase C (bridge work) to run for single-story direct waves.

## v0.4.1

- Simplified skills, agents, and prompt templates (~25% reduction).
- Restored 8 specifications lost during refactor simplification.
- Added Phase C (bridge work) to wave review — prepares the codebase for the next wave's parallel workers.

## v0.4.0

- Post-wave code review system (Sonnet wave-reviewer + Opus wave-coordinator for escalation).
- Switched from Task tool's `isolation: "worktree"` to dispatcher-managed worktrees — the platform's worktree isolation creates from stale refs, so Wave N+1 workers couldn't see Wave N's merged changes, causing redundant re-implementation and merge conflicts.
- Removed experimental conflict-resolver agent (Tier 3) in favor of the wave-reviewer/coordinator pipeline.
- Orphan worktree cleanup at startup.

## v0.3.7

- Next-step prompts in `ralph:prd` and `ralph:convert` skills guide users through the workflow.

## v0.3.6

- PRD output centralized to `.ralph-in-claude/tasks/`.
- `ralph:convert` auto-detects PRD files from that directory.

## v0.3.5

- Tightened prd.json schema validation.

## v0.3.4

- Default max parallel agents increased from 3 to 5.

## v0.3.3

- Switched ralph-worker model from Opus to Sonnet for better cost/speed balance.

## v0.3.2

- Conflict-aware scheduling and resolution pipeline.

## v0.3.1

- Append-only conflict auto-resolve and `sharedFiles`-aware scheduling.

## v0.3.0

- Worktree isolation for parallel workers.
- Added `sharedFiles` / `conflictStrategy` fields to prd.json.

## v0.2.1

- Added `state.json` lifecycle tracking to dispatcher workflow.

## v0.2.0

- Moved hooks to plugin-level `hooks/hooks.json` (SKILL.md hooks don't fire for marketplace plugins).
- Added `ralph-worker` agent definition and slimmed down subagent prompt template.
- Moved git commit responsibility from subagents to dispatcher.

## v0.1.1

- Use exit 2 to block invalid prd.json, add Edit matcher, deduplicate hook scripts.

## v0.0.1

- Initial release: Ralph for Claude Code with `ralph:prd`, `ralph:convert`, and `ralph:run` skills.
