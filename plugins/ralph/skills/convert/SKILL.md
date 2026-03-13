---
name: convert
description: "Convert an existing PRD document into Ralph's prd.json execution format. Use when you have a PRD and need to prepare it for Ralph's autonomous execution."
argument-hint: "[prd-file-path]"
# hooks: see plugin-level hooks/hooks.json
---

# Ralph PRD Converter

Converts existing PRDs to the prd.json format that Ralph uses for autonomous execution.

**CRITICAL: When asking the user questions (e.g., confirming baseBranch), ALWAYS use the `AskUserQuestion` tool. Do NOT output questions as plain text. The `AskUserQuestion` tool provides an interactive UI with selectable options.**

---

## The Job

1. **Locate the PRD:**
   - **If an argument was provided** → use that path directly
   - **If no argument** → scan `.ralph-in-claude/tasks/prd-*.md`:
     - **0 files found** → tell the user to run `/ralph:prd` first, then stop
     - **1 file found** → auto-select it and confirm to the user (e.g., "Found `.ralph-in-claude/tasks/prd-foo.md` — using that.")
     - **2+ files found** → use the `AskUserQuestion` tool with the file list as options so the user can pick one
2. **Validate the input file:**
   - Read the file and verify it contains PRD-like content (user stories, requirements, features).
   - If the file is **empty**, inform the user and stop.
   - If the file is **already a prd.json** (valid JSON with `userStories` array), tell the user it is already converted and stop.
   - If the file has **no actionable requirements** (no user stories, features, or functional requirements), stop and explain what is missing.
3. **Confirm the `baseBranch`:**
   - Check the current branch with `git branch --show-current`.
   - If the current branch is `main` or `master`, default to it and inform the user (e.g., "Using `main` as baseBranch.") without requiring confirmation.
   - If the current branch is a feature branch or there is ambiguity, use the `AskUserQuestion` tool with options including the current branch, `main`, and other relevant branches.
4. **Extract implementation details** from the PRD (architecture decisions, APIs, data structures, code patterns) and include them in relevant story `notes` fields
5. **Record the source PRD path** in `sourcePrd` field so Ralph can reference it during implementation
6. **Validate the generated JSON** before writing:
   - Verify the JSON is syntactically valid.
   - Verify all `dependsOn` references point to existing story IDs within this PRD.
   - Verify the dependency graph is acyclic (perform a topological sort; if it fails, there is a cycle -- fix before proceeding).
   - If validation fails, fix the issues before writing.
7. **Check for existing prd.json:** If `.ralph-in-claude/prd.json` already exists, warn the user and ask for confirmation before overwriting using `AskUserQuestion`.
8. Write the output to `.ralph-in-claude/prd.json` (the hook auto-creates the `.ralph-in-claude/` directory)

---

## Output Format

```json
{
  "project": "[Project Name]",
  "branchName": "ralph/[feature-name-kebab-case]",
  "baseBranch": "[base branch to create from, e.g. main or feature-branch]",
  "sourcePrd": "[path to original PRD file, e.g. .ralph-in-claude/tasks/prd-feature.md]",
  "description": "[Feature description from PRD title/intro]",
  "conflictStrategy": "optimistic",
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
      "sharedFiles": [
        { "file": "src/index.ts", "conflictType": "append-only", "reason": "import registration" }
      ],
      "priority": 1,
      "passes": false,
      "notes": ""
    }
  ]
}
```

> **Note:** `conflictStrategy` is optional (defaults to `"conservative"`). Use `"optimistic"` when most shared-file overlaps are `append-only`. Each `sharedFiles` entry can be a plain string (treated as `structural-modify`) or an object with `{file, conflictType, reason}`.

---

> **Story sizing:** Each story should be completable by a single agent in one iteration -- roughly 1-3 files changed.

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

Always end with `"Typecheck passes"`; add `"Tests pass"` for testable logic, `"Verify in browser"` for UI stories.

---

## Conversion Rules

1. **Each user story becomes one JSON entry**
2. **IDs**: Sequential (US-001, US-002, etc.)
3. **Priority**: Based on dependency order, then document order; lower number executes first among ready stories.
4. **All stories**: `passes: false`
5. **notes field**: If the source PRD contains implementation details for a story (architecture decisions, specific APIs, data structures, code patterns, file locations), extract and include them in the notes field. Otherwise leave empty.
6. **sourcePrd**: Path to the original PRD file (relative to project root). Ralph will read this file during implementation for additional context.
7. **branchName**: Derive from feature name, kebab-case, prefixed with `ralph/`
8. **Always add**: "Typecheck passes" to every story's acceptance criteria
9. **dependsOn**: Analyze the PRD for inter-story dependencies (if a story uses a schema/resource created by another story, it depends on that story). Set `dependsOn` to an array of story IDs that must be completed before this story can start. Root stories (no dependencies) use `[]`. Order by dependency depth: schema/migrations first, then backend/services, then UI components.
10. **sharedFiles**: Identify files this story will modify that other stories in the same wave may also modify. Each entry can be a **string** (backward-compatible, treated as `structural-modify`) or an **object** with conflict classification:
    ```json
    { "file": "src/index.ts", "conflictType": "append-only", "reason": "import registration" }
    ```
    - `"append-only"` — story adds new independent content (imports, route entries, config keys, new models)
    - `"structural-modify"` — story modifies existing code structures (editing functions, changing schemas)
    - Use the **Conflict Analysis** rules below to classify each entry
    - Use `[]` if the story only modifies files unique to itself

---

## Conflict Analysis

Classify each `sharedFiles` entry as `append-only` (new independent content) or `structural-modify` (changes existing code). When uncertain, default to `structural-modify`. After classification, check for parallel unlock opportunities and structural conflicts across stories.

For conflict classification rules, cross-story analysis steps, and strategy recommendations, read `references/conflict-analysis.md`.

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
  "conflictStrategy": "conservative",
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
      "sharedFiles": [{ "file": "prisma/schema.prisma", "conflictType": "structural-modify", "reason": "modifies schema" }],
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
      "sharedFiles": [],
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
      "sharedFiles": [],
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
      "sharedFiles": [],
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
- [ ] Every story has a `sharedFiles` array (use `[]` if no shared files)
- [ ] `sharedFiles` entries use object format `{file, conflictType, reason}` with correct classification
- [ ] `conflictType` is `"append-only"` or `"structural-modify"` per the Conflict Analysis rules
- [ ] `conflictStrategy` is set at project level if append-only overlaps dominate

---

## Next Step

After saving prd.json, tell the user:

> prd.json saved. Review the generated stories, then run `/ralph:run` to start execution.
