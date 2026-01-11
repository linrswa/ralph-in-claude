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
  "description": "[Feature description]",
  "userStories": [
    {
      "id": "US-001",
      "title": "[Story title]",
      "description": "As a [user], I want [feature] so that [benefit]",
      "acceptanceCriteria": ["Criterion 1", "Typecheck passes"],
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

## Key Files

| File | Purpose |
|------|---------|
| `ralph.sh` | Main loop script - spawns Claude iterations |
| `prompt.md` | Instructions given to each Claude iteration |
| `prd.json` | Current PRD with story status tracking |
| `progress.txt` | Append-only log of learnings |

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

```bash
./ralph.sh [max_iterations]  # default: 10
```

Ralph continues until:
- All stories have `passes: true`, or
- Max iterations reached
