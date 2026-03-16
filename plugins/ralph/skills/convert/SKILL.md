---
name: convert
description: "Convert an existing PRD document into Ralph's prd.json execution format. Use when you have a PRD and need to prepare it for Ralph's autonomous execution."
argument-hint: "[prd-file-path]"
# hooks: see plugin-level hooks/hooks.json
---

# Ralph PRD Converter

Converts existing PRDs to the prd.json format that Ralph uses for autonomous execution.

The key difference between a mediocre conversion and a great one is **codebase awareness**: knowing which files exist, how the project is structured, and what patterns workers should follow. A prd.json with accurate `sharedFiles`, concrete `notes`, and validated dependencies leads to smooth execution. One with guessed file paths and empty notes leads to worker failures.

**CRITICAL: When asking the user questions, ALWAYS use the `AskUserQuestion` tool. Do NOT output questions as plain text.**

---

## The Job

1. **Locate the PRD:**
   - **If an argument was provided** → use that path directly
   - **If no argument** → scan `.ralph-in-claude/tasks/prd-*.md`:
     - **0 files found** → tell the user to run `/ralph:prd` first, then stop
     - **1 file found** → auto-select it and confirm to the user
     - **2+ files found** → use `AskUserQuestion` with file list as options
2. **Validate the input file:**
   - Read the file and verify it contains PRD-like content (user stories, requirements, features).
   - If **empty**, inform the user and stop.
   - If **already a prd.json** (valid JSON with `userStories` array), tell the user and stop.
   - If **no actionable requirements**, stop and explain what is missing.
3. **Analyze the codebase** — see [Codebase Analysis](#codebase-analysis) below
4. **Confirm the `baseBranch`:**
   - If current branch is `main`/`master`, default without confirmation.
   - Otherwise, use `AskUserQuestion` with options including current branch and `main`.
5. **Generate story JSON** — combine PRD content with codebase analysis to produce each story's `notes`, `sharedFiles`, and `dependsOn`. See [Notes Generation](#notes-generation).
6. **Record the source PRD path** in `sourcePrd`
7. **Validate the generated JSON:**
   - Syntactically valid JSON
   - All `dependsOn` references point to existing story IDs
   - Dependency graph is acyclic (topological sort)
   - Fix any issues before proceeding
8. **Validate dependencies against code** — see [Dependency Validation](#dependency-validation)
9. **Validate story sizing** — see [Story Sizing Validation](#story-sizing-validation)
10. **Check for existing prd.json:** If exists, use `AskUserQuestion` to confirm overwrite
11. Write to `.ralph-in-claude/prd.json`

---

## Codebase Analysis

After validating the PRD, explore the actual codebase. This grounds the conversion in reality — real file paths, real patterns, real shared files — instead of guessing from PRD text alone.

**Shortcut:** If the PRD already contains concrete codebase context (file paths, patterns, Technical Considerations referencing actual code) — e.g., from a `ralph:prd` run that explored the codebase — you can use that as a starting point and focus exploration on gaps: verifying paths still exist, finding files not mentioned in the PRD, and identifying shared files across stories.

### 3a. Map project structure

Use **Glob** to understand the layout. Detect the language/framework first (check for `package.json`, `Cargo.toml`, `go.mod`, `pyproject.toml`, etc.), then search with appropriate patterns:
- Source files: `**/*.ts`, `**/*.tsx`, `**/*.rs`, `**/*.go`, `**/*.py`, etc. — match the project's language
- Config: `**/package.json`, `**/tsconfig.json`, `**/Cargo.toml`, `**/go.mod`, `**/*.config.*`
- Data layer: `**/schema.*`, `**/migration*/**`, `**/prisma/**`, `**/sqlx/**`, `**/alembic/**`
- Tests: `**/*.test.*`, `**/*.spec.*`, `**/*_test.*`, `**/test_*.*`

Build a mental map of key directories (e.g., `src/routes/`, `src/components/`, `src/lib/`).

### 3b. Identify files each story will touch

For each user story, use **Grep** and **Glob** to find:
- **Existing files** the story will modify — search for related function names, component names, route paths, models
- **Existing patterns** the story should follow — find a similar feature to use as a template
- **New files** the story will create — infer from directory conventions

Record these per story — they feed directly into `sharedFiles` and `notes`.

### 3c. Identify shared files across stories

Cross-reference per-story file lists:
- If two+ stories both modify the same file → that file is shared
- Classify based on what each story does:
  - Both add new entries (imports, routes, exports) → `append-only`
  - Any story modifies existing code → `structural-modify`
  - Uncertain → `structural-modify`

### 3d. Note patterns for workers

Identify conventions that workers must follow:
- Routing pattern (file-based? centralized?)
- Component organization (co-located styles? separate dirs?)
- ORM/database patterns
- Barrel files (index.ts re-exports?)
- Testing patterns

These go into story `notes`.

---

## Notes Generation

Workers receive `notes` as their primary implementation guidance. Empty or vague notes lead to bad implementations because workers start in a fresh context with no project knowledge.

For every story, notes should contain:

1. **File paths** — specific files to modify or create, from codebase analysis
   - `"Modify src/server/routes/tasks.ts to add the new endpoint"`

2. **Patterns to follow** — reference existing code as a template
   - `"Follow the pattern in src/server/routes/users.ts for route structure"`

3. **APIs/functions to use** — specific helpers, hooks, utilities
   - `"Use the db.query() helper in src/lib/db.ts. Import TaskStatus from src/types/task.ts"`

4. **PRD implementation details** — architecture, data structures, algorithms from the PRD
   - `"Use Prisma enum for status. Transitions: pending→in_progress→done (no backward)"`

5. **Gotchas** — anything that could trip up a worker
   - `"The tasks table already has a 'state' column — don't confuse with new 'status' column"`

**Notes must never be empty.** Even if the PRD provides no implementation details, codebase analysis always yields file paths, patterns, and relevant existing code.

---

## Dependency Validation

After building stories with `dependsOn`, validate against codebase analysis:

1. **Missing dependencies:** If story B imports/uses something story A creates (a type, module, table), B must depend on A. Check each story's file list for cross-references.
2. **Unnecessary dependencies:** If B depends on A but they touch completely different files with no cross-references, the dependency may be unnecessary. Unnecessary deps serialize execution and slow down runs.
3. **Ordering matches code structure:** Dependencies should flow: schema/migrations → backend services → frontend components → integration. A UI story with no dependency on the backend story creating its data source is likely missing a dep.

Fix issues found.

---

## Story Sizing Validation

After generating JSON, validate each story is appropriately sized:

1. **File count:** If a story touches >5 files (from analysis), it's likely too large.
2. **Complexity:** If notes reference complex existing code (>300 lines to understand), flag it.
3. **Present concerns:** If issues found, use `AskUserQuestion`:
   - "Keep as-is" — proceed
   - "Split story X" — let the converter suggest a split

Proceed silently if no issues.

---

## Output Format

```json
{
  "project": "[Project Name]",
  "branchName": "ralph/[feature-name-kebab-case]",
  "baseBranch": "[base branch]",
  "sourcePrd": "[path to PRD file]",
  "description": "[Feature description]",
  "conflictStrategy": "optimistic",
  "userStories": [
    {
      "id": "US-001",
      "title": "[Story title]",
      "description": "As a [user], I want [feature] so that [benefit]",
      "acceptanceCriteria": ["Criterion 1", "Typecheck passes"],
      "dependsOn": [],
      "sharedFiles": [
        { "file": "src/index.ts", "conflictType": "append-only", "reason": "import registration" }
      ],
      "priority": 1,
      "passes": false,
      "notes": "Modify src/models/task.ts — follow pattern in src/models/user.ts. Use Prisma enum per PRD section 2.1."
    }
  ]
}
```

> `conflictStrategy` is optional (defaults to `"conservative"`). Use `"optimistic"` when most overlaps are `append-only`. `sharedFiles` entries can be strings (treated as `structural-modify`) or objects with `{file, conflictType, reason}`.

---

> **Story sizing:** Each story should be completable by a single agent — roughly 1-3 files changed.

---

## Acceptance Criteria: Must Be Verifiable

Each criterion must be checkable, not vague.

**Good:** "Add `status` column with default 'pending'" / "Filter dropdown has: All, Active, Completed" / "Typecheck passes"

**Bad:** "Works correctly" / "Good UX" / "Handles edge cases"

Always end with `"Typecheck passes"`; add `"Tests pass"` for testable logic, `"Verify in browser"` for UI stories.

---

## Conversion Rules

1. **Each user story → one JSON entry**
2. **IDs**: Sequential (US-001, US-002, etc.)
3. **Priority**: By dependency order, then document order; lower = executes first
4. **All stories**: `passes: false`
5. **notes**: Combine PRD details with codebase analysis findings. File paths, patterns, APIs, gotchas. **Never leave empty.**
6. **sourcePrd**: Relative path to original PRD
7. **branchName**: Feature name in kebab-case, prefixed with `ralph/`
8. **Always add** `"Typecheck passes"` to every story's acceptance criteria
9. **dependsOn**: From PRD analysis AND codebase validation. Order: schema → backend → UI. Use `[]` for root stories.
10. **sharedFiles**: From codebase analysis — verify file paths exist (or note they'll be created). Use object format:
    ```json
    { "file": "src/index.ts", "conflictType": "append-only", "reason": "import registration" }
    ```
    - `"append-only"` — new independent content
    - `"structural-modify"` — changes existing code
    - See **Conflict Analysis** rules. Use `[]` if story only touches unique files.

---

## Conflict Analysis

Classify `sharedFiles` as `append-only` or `structural-modify`. Default to `structural-modify` when uncertain. Check for parallel unlock opportunities and structural conflicts across stories.

Read `references/conflict-analysis.md` for classification rules and strategy recommendations.

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

**Output prd.json** (note: every story has concrete notes from codebase analysis):
```json
{
  "project": "TaskApp",
  "branchName": "ralph/task-status",
  "baseBranch": "main",
  "sourcePrd": ".ralph-in-claude/tasks/prd-task-status.md",
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
      "sharedFiles": [{ "file": "prisma/schema.prisma", "conflictType": "structural-modify", "reason": "adds status field to Task model" }],
      "priority": 1,
      "passes": false,
      "notes": "Files: Modify prisma/schema.prisma, update src/types/task.ts\nPattern: Follow the existing Priority enum in schema.prisma for the new TaskStatus enum\nImplementation: Add TaskStatus enum (PENDING, IN_PROGRESS, DONE) above the Task model. Add a 'status' field to Task with @default(PENDING). Run `npx prisma migrate dev --name add-task-status`.\nGotcha: Update the TaskWithUser type in src/types/task.ts to include the new status field"
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
      "notes": "Files: Create src/components/StatusBadge.tsx, modify src/components/TaskCard.tsx\nPattern: Follow the exact pattern in src/components/PriorityBadge.tsx (color map + cn() utility)\nAPIs: Import TaskStatus from @prisma/client, cn() from src/lib/utils.ts\nImplementation: Add the badge to TaskCard.tsx next to the existing PriorityBadge"
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
      "notes": "Files: Modify src/components/TaskCard.tsx\nPattern: Use existing updateTask server action from src/server/actions/tasks.ts\nAPIs: Import TaskStatus from @prisma/client, cn() from src/lib/utils.ts\nImplementation: Add a status dropdown to each task card. Changing status should call updateTask and update UI without page refresh"
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
      "notes": "Files: Create src/components/StatusFilter.tsx, modify src/app/tasks/page.tsx, modify src/server/queries/tasks.ts\nPattern: Follow PriorityBadge pattern for filter component styling\nImplementation: Add filter dropdown to tasks/page.tsx reading searchParams. Update getTasks query to accept optional status filter via Prisma where clause.\nGotcha: Filter must persist in URL params for shareable links"
    }
  ]
}
```

---

## Checklist Before Saving

- [ ] Codebase analysis performed (project structure mapped, per-story files identified)
- [ ] Each story completable in one iteration (1-3 files, max 5)
- [ ] Stories ordered by dependency (schema → backend → UI)
- [ ] Every story has "Typecheck passes" as criterion
- [ ] UI stories have "Verify in browser" as criterion
- [ ] Acceptance criteria are verifiable (not vague)
- [ ] No story depends on a later story
- [ ] sourcePrd points to original PRD file
- [ ] Every story has **non-empty notes** with file paths, patterns, and guidance from codebase analysis
- [ ] Every story has `dependsOn` array (`[]` for root stories)
- [ ] `dependsOn` references are valid story IDs
- [ ] `dependsOn` graph has no cycles (valid DAG)
- [ ] Dependencies validated against code (no missing deps where B uses A's output)
- [ ] Every story has `sharedFiles` array (`[]` if no shared files)
- [ ] `sharedFiles` entries use object format `{file, conflictType, reason}`
- [ ] `sharedFiles` file paths verified against codebase
- [ ] `conflictType` is `"append-only"` or `"structural-modify"` per Conflict Analysis rules
- [ ] `conflictStrategy` set if append-only overlaps dominate
- [ ] Story sizing validated (flagged >5 files or high complexity)

---

## Next Step

After saving prd.json, tell the user:

> prd.json saved. Review the generated stories, then run `/ralph:run` to start execution.
