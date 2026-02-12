# Ralph - Claude Code Version

This is the Claude Code adaptation of the Ralph autonomous agent loop system.

## Overview

Ralph is an autonomous AI agent loop that iteratively implements features from a Product Requirements Document (PRD). Each iteration spawns a fresh Claude instance to avoid context exhaustion.

## How It Works

1. Create a PRD describing your feature
2. Convert to `prd.json` format
3. Run `./ralph.sh` to start the autonomous loop
4. Ralph picks the highest-priority incomplete story
5. Implements it, runs quality checks, commits
6. Repeats until all stories pass

## Commands

### Generate a PRD

When asked to create a PRD, follow these steps:

1. Ask 3-5 clarifying questions with lettered options (A, B, C, D)
2. Generate a structured PRD with these sections:
   - Introduction/Overview
   - Goals
   - User Stories (with acceptance criteria)
   - Functional Requirements (numbered FR-1, FR-2, etc.)
   - Non-Goals
   - Technical Considerations
   - Success Metrics

3. Save to `tasks/prd-[feature-name].md`

**User Story Format:**
```markdown
### US-001: [Title]
**Description:** As a [user], I want [feature] so that [benefit].

**Acceptance Criteria:**
- [ ] Specific verifiable criterion
- [ ] Another criterion
- [ ] Typecheck/lint passes
```

### Convert PRD to prd.json

Convert a PRD markdown file to Ralph's JSON format:

```json
{
  "project": "[Project Name]",
  "branchName": "ralph/[feature-name]",
  "baseBranch": "main",
  "sourcePrd": "tasks/prd-[feature-name].md",
  "description": "[Feature description]",
  "userStories": [
    {
      "id": "US-001",
      "title": "[Story title]",
      "description": "As a [user], I want [feature] so that [benefit]",
      "acceptanceCriteria": ["Criterion 1", "Typecheck passes"],
      "dependsOn": [],
      "priority": 1,
      "passes": false,
      "notes": ""
    }
  ]
}
```

**Critical Rules:**
- Each story must be completable in ONE iteration (one context window)
- Order by dependency: schema → backend → frontend
- Always include "Typecheck passes" in acceptance criteria
- For UI stories, include browser verification
- Every story must have a `dependsOn` array declaring inter-story dependencies (story IDs). Stories won't be picked until all dependencies have `passes: true`. Use `[]` for root stories with no dependencies.

## Key Files

| File | Purpose |
|------|---------|
| `.claude-plugin/plugin.json` | Plugin manifest |
| `skills/prd/SKILL.md` | `ralph:prd` — PRD generator |
| `skills/convert/SKILL.md` | `ralph:convert` — PRD-to-JSON converter |
| `skills/convert/scripts/` | Hooks for convert skill (ensure-ralph-dir, validate-prd-write) |
| `skills/run/SKILL.md` | `ralph:run` — parallel story dispatcher |
| `skills/run/scripts/` | Hooks for run skill |
| `skills/run/references/subagent-prompt-template.md` | Worker prompt template with placeholders |
| `ralph.sh` | v1 fallback loop script — spawns Claude iterations |
| `prompt.md` | v1 instructions given to each Claude iteration |
| `prd.json` | Current PRD with story status tracking |
| `progress.txt` | Append-only log of learnings |

## PRD Schema Validation

The `ralph:convert` and `ralph:run` skills define PreToolUse hooks in their SKILL.md frontmatter that fire before Write tool executions:

1. **`ensure-ralph-dir.sh`** — ensures `.ralph-in-claude/` directory exists
2. **`validate-prd-write.sh`** — validates prd.json schema (valid JSON, required fields, `dependsOn` referential integrity), blocks writes on failure

Hooks only fire during their respective skill's execution and don't affect other operations.

## Story Sizing

**Right-sized (one iteration):**
- Add a database column
- Create a UI component
- Add a filter dropdown
- Update server action

**Too big (split these):**
- "Build entire dashboard" → split into schema, queries, components
- "Add authentication" → split into schema, middleware, UI, sessions

**Rule:** If you can't describe the change in 2-3 sentences, it's too big.

## Running Ralph

### v2: `/ralph:run` (Recommended)

Use the `/ralph:run` skill to orchestrate parallel story execution:

```
/ralph:run              # uses .ralph-in-claude/prd.json
/ralph:run path/to/prd.json  # custom path
```

How it works:
1. Reads prd.json and builds a dependency DAG from `dependsOn` fields
2. Spawns up to 3 subagent workers in parallel per wave
3. Workers implement stories, run quality checks, and commit
4. Dispatcher verifies results, updates prd.json, and spawns next wave
5. Repeats until all stories pass or all are blocked/failed

### v1: `ralph.sh` (Fallback)

```bash
./ralph.sh [max_iterations]  # default: 10
```

Sequential execution — one story per iteration. Useful for CI/headless environments.

Both continue until:
- All stories have `passes: true`, or
- Max iterations/waves exhausted
