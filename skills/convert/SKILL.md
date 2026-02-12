---
name: convert
description: "Convert PRDs to prd.json format for the Ralph autonomous agent system. Use when you have an existing PRD and need to convert it to Ralph's JSON format. Triggers on: convert this prd, turn this into ralph format, create prd.json from this, ralph json."
argument-hint: "[prd-file-path]"
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

# Ralph PRD Converter

Converts existing PRDs to the prd.json format that Ralph uses for autonomous execution.

**CRITICAL: When asking the user questions (e.g., confirming baseBranch), ALWAYS use the `AskUserQuestion` tool. Do NOT output questions as plain text. The `AskUserQuestion` tool provides an interactive UI with selectable options.**

---

## The Job

1. Take a PRD (markdown file or text)
2. **Ask the user to confirm the `baseBranch`** using the `AskUserQuestion` tool. Provide options based on:
   - The current git branch (check with `git branch --show-current`)
   - `main` branch
   - Other common branches if relevant
3. **Extract implementation details** from the PRD (architecture decisions, APIs, data structures, code patterns) and include them in relevant story `notes` fields
4. **Record the source PRD path** in `sourcePrd` field so Ralph can reference it during implementation
5. Write the output to `ralph/prd.json` (the hook auto-creates the `ralph/` directory)

**IMPORTANT:** Always use the `AskUserQuestion` tool when asking for user input. This provides an interactive UI with selectable options.

---

## Output Format

```json
{
  "project": "[Project Name]",
  "branchName": "ralph/[feature-name-kebab-case]",
  "baseBranch": "[base branch to create from, e.g. main or feature-branch]",
  "sourcePrd": "[path to original PRD file, e.g. docs/prd/feature.md]",
  "description": "[Feature description from PRD title/intro]",
  "userStories": [
    {
      "id": "US-001",
      "title": "[Story title]",
      "description": "As a [user], I want [feature] so that [benefit]",
      "acceptanceCriteria": [
        "Criterion 1",
        "Criterion 2",
        "Typecheck passes"
      ],
      "dependsOn": [],
      "priority": 1,
      "passes": false,
      "notes": ""
    }
  ]
}
```

---

## Story Size: The Number One Rule

**Each story must be completable in ONE Ralph iteration (one context window).**

Ralph spawns a fresh Claude instance per iteration with no memory of previous work. If a story is too big, the LLM runs out of context before finishing and produces broken code.

### Right-sized stories:
- Add a database column and migration
- Add a UI component to an existing page
- Update a server action with new logic
- Add a filter dropdown to a list

### Too big (split these):
- "Build the entire dashboard" - Split into: schema, queries, UI components, filters
- "Add authentication" - Split into: schema, middleware, login UI, session handling
- "Refactor the API" - Split into one story per endpoint or pattern

**Rule of thumb:** If you cannot describe the change in 2-3 sentences, it is too big.

---

## Story Ordering: Dependencies First

Stories execute in priority order, filtered by dependency readiness. Use `dependsOn` to express inter-story dependencies explicitly.

- **`dependsOn`** (required): An array of story IDs that must have `passes: true` before this story can be picked. Use `[]` for root stories with no dependencies.
- **`priority`**: Among stories whose dependencies are all satisfied, the lowest priority number is picked first.

**Correct order:**
1. Schema/database changes (migrations) — `dependsOn: []`
2. Server actions / backend logic — `dependsOn: ["US-001"]`
3. UI components that use the backend — `dependsOn: ["US-001"]` or `["US-002"]`
4. Dashboard/summary views that aggregate data — `dependsOn: ["US-002", "US-003"]`

**Wrong order:**
1. UI component (depends on schema that does not exist yet)
2. Schema change

---

## Acceptance Criteria: Must Be Verifiable

Each criterion must be something Ralph can CHECK, not something vague.

### Good criteria (verifiable):
- "Add `status` column to tasks table with default 'pending'"
- "Filter dropdown has options: All, Active, Completed"
- "Clicking delete shows confirmation dialog"
- "Typecheck passes"
- "Tests pass"

### Bad criteria (vague):
- "Works correctly"
- "User can do X easily"
- "Good UX"
- "Handles edge cases"

### Always include as final criterion:
```
"Typecheck passes"
```

For stories with testable logic, also include:
```
"Tests pass"
```

### For stories that change UI, also include:
```
"Verify in browser"
```

---

## Conversion Rules

1. **Each user story becomes one JSON entry**
2. **IDs**: Sequential (US-001, US-002, etc.)
3. **Priority**: Based on dependency order, then document order
4. **All stories**: `passes: false`
5. **notes field**: If the source PRD contains implementation details for a story (architecture decisions, specific APIs, data structures, code patterns, file locations), extract and include them in the notes field. Otherwise leave empty.
6. **sourcePrd**: Path to the original PRD file (relative to project root). Ralph will read this file during implementation for additional context.
7. **branchName**: Derive from feature name, kebab-case, prefixed with `ralph/`
8. **Always add**: "Typecheck passes" to every story's acceptance criteria
9. **dependsOn**: Analyze the PRD for inter-story dependencies. Set `dependsOn` to an array of story IDs that must be completed before this story can start. Root stories (no dependencies) use `[]`. If a story uses a schema added by another story, it depends on that story.

---

## Splitting Large PRDs

If a PRD has big features, split them:

**Original:**
> "Add user notification system"

**Split into:**
1. US-001: Add notifications table to database
2. US-002: Create notification service for sending notifications
3. US-003: Add notification bell icon to header
4. US-004: Create notification dropdown panel
5. US-005: Add mark-as-read functionality
6. US-006: Add notification preferences page

Each is one focused change that can be completed and verified independently.

---

## Example

**Input PRD:**
```markdown
# Task Status Feature

Add ability to mark tasks with different statuses.

## Requirements
- Toggle between pending/in-progress/done on task list
- Filter list by status
- Show status badge on each task
- Persist status in database
```

**Output prd.json:**
```json
{
  "project": "TaskApp",
  "branchName": "ralph/task-status",
  "baseBranch": "main",
  "sourcePrd": "docs/prd/task-status.md",
  "description": "Task Status Feature - Track task progress with status indicators",
  "userStories": [
    {
      "id": "US-001",
      "title": "Add status field to tasks table",
      "description": "As a developer, I need to store task status in the database.",
      "acceptanceCriteria": [
        "Add status column: 'pending' | 'in_progress' | 'done' (default 'pending')",
        "Generate and run migration successfully",
        "Typecheck passes"
      ],
      "dependsOn": [],
      "priority": 1,
      "passes": false,
      "notes": "Use Prisma enum type. See PRD section 2.1 for status transition rules."
    },
    {
      "id": "US-002",
      "title": "Display status badge on task cards",
      "description": "As a user, I want to see task status at a glance.",
      "acceptanceCriteria": [
        "Each task card shows colored status badge",
        "Badge colors: gray=pending, blue=in_progress, green=done",
        "Typecheck passes",
        "Verify in browser"
      ],
      "dependsOn": ["US-001"],
      "priority": 2,
      "passes": false,
      "notes": ""
    },
    {
      "id": "US-003",
      "title": "Add status toggle to task list rows",
      "description": "As a user, I want to change task status directly from the list.",
      "acceptanceCriteria": [
        "Each row has status dropdown or toggle",
        "Changing status saves immediately",
        "UI updates without page refresh",
        "Typecheck passes",
        "Verify in browser"
      ],
      "dependsOn": ["US-001"],
      "priority": 3,
      "passes": false,
      "notes": ""
    },
    {
      "id": "US-004",
      "title": "Filter tasks by status",
      "description": "As a user, I want to filter the list to see only certain statuses.",
      "acceptanceCriteria": [
        "Filter dropdown: All | Pending | In Progress | Done",
        "Filter persists in URL params",
        "Typecheck passes",
        "Verify in browser"
      ],
      "dependsOn": ["US-002", "US-003"],
      "priority": 4,
      "passes": false,
      "notes": ""
    }
  ]
}
```

---

## Checklist Before Saving

Before writing prd.json, verify:

- [ ] Each story is completable in one iteration (small enough)
- [ ] Stories are ordered by dependency (schema → backend → UI)
- [ ] Every story has "Typecheck passes" as criterion
- [ ] UI stories have "Verify in browser" as criterion
- [ ] Acceptance criteria are verifiable (not vague)
- [ ] No story depends on a later story
- [ ] sourcePrd points to the original PRD file path
- [ ] Implementation details from PRD are captured in relevant story notes
- [ ] Every story has a `dependsOn` array (use `[]` for root stories)
- [ ] `dependsOn` references are valid story IDs within this PRD
- [ ] `dependsOn` graph has no cycles (forms a valid DAG)
