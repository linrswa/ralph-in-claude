---
name: prd
description: "Generate a Product Requirements Document (PRD) for a new feature or project. Use when planning features, defining requirements, or speccing out work."
argument-hint: "[feature-description]"
---

# PRD Generator

Create detailed Product Requirements Documents that are clear, actionable, and suitable for autonomous AI implementation via `ralph:convert` and `ralph:run`.

**CRITICAL: When asking clarifying questions, ALWAYS use the `AskUserQuestion` tool. Do NOT output questions as plain text.**

## The Job

1. Receive a feature description from the user
2. **Explore the codebase** to understand structure, patterns, and related code
3. Ask 2-5 clarifying questions (with lettered options), informed by what you found. Skip questions the user's description already answers.
4. Generate a structured PRD based on answers and codebase context
5. Save to `.ralph-in-claude/tasks/prd-[feature-slug].md`

**Important:** Do NOT start implementing. Just create the PRD.

---

## Step 1: Codebase Exploration

Before asking questions or writing anything, explore the project to understand what exists. This context directly feeds into better stories, accurate notes, and correct dependency ordering — all of which reduce worker failures downstream.

Use **Glob** and **Grep** to quickly answer:

1. **Project structure:** What framework, language, and build tools? What are the key directories?
   - Check `package.json`, `Cargo.toml`, `go.mod`, `pyproject.toml`, etc.
   - List top-level and `src/` directories to understand the layout
2. **Existing patterns:** How does the codebase handle routing, state management, data access, components?
   - Read 1-2 existing features similar to what the user is requesting — these become reference patterns for workers
3. **Related existing code:** What files and modules relate to the requested feature?
   - Search for relevant keywords, types, function names
   - These become the file paths and patterns in story Notes

Keep it focused — 3-5 minutes, not an exhaustive audit. If the project is unfamiliar: framework → directory layout → one similar feature.

---

## Step 2: Clarifying Questions

If no feature description is provided, use `AskUserQuestion` to ask the user to describe the feature first.

Ask only critical questions where the initial prompt is ambiguous. Focus on:

- **Problem/Goal:** What problem does this solve?
- **Core Functionality:** What are the key actions?
- **Scope/Boundaries:** What should it NOT do?
- **Success Criteria:** How do we know it's done?

Use your codebase exploration to ask **specific** questions rather than generic ones. For example, if you found the project uses Prisma, ask "Should the new model follow the pattern in `schema.prisma`?" rather than "What database technology?"

Structure questions with 2-4 options each via `AskUserQuestion`.

---

## Step 3: PRD Structure

Generate the PRD with these sections:

### 1. Introduction/Overview
Brief description of the feature and the problem it solves.

### 2. Goals
Specific, measurable objectives (bullet list).

### 3. User Stories

Each story is implemented by an **autonomous AI worker in a single context window** with no memory of other stories. This means every story must be self-contained and include enough context for a worker to succeed independently.

#### Sizing Rules

- **1-3 files** per story (max 5 for complex integration stories)
- Describable in **2-3 sentences**
- If it requires understanding more than **~200 lines** of existing code, consider splitting
- More than **5 acceptance criteria** suggests the story is too large

**Good sizes:**
- "Add a `status` column to the tasks table with a Prisma migration" (1-2 files)
- "Create a `StatusBadge` component that renders colored badges" (1-2 files)
- "Add a filter dropdown to the task list page" (2-3 files)

**Too large — split:**
- "Build entire dashboard with charts, filters, and tables" → schema, data queries, individual chart components, filter controls, layout
- "Add authentication" → schema, middleware, login UI, session management, protected routes

#### Ordering and Dependencies

Order stories by implementation phase:
1. **Schema/Types** — database migrations, type definitions, shared interfaces
2. **Backend/Logic** — API endpoints, server actions, business logic
3. **UI/Components** — individual components, pages, client-side logic
4. **Integration** — wiring things together, final assembly

Mark dependencies explicitly: `Depends on: US-001, US-002`. Only declare a dependency when a story directly uses something another story creates.

#### Implementation Notes

Each story **must** include a **Notes** subsection. Workers start with zero project context — Notes are their roadmap. Draw from your codebase exploration:

- **Files to create or modify** — `"Modify src/lib/db/schema.ts to add the new table"`
- **Patterns to follow** — `"Follow the pattern in src/components/PriorityBadge.tsx"`
- **APIs/functions to use** — `"Use the createServerAction helper from src/lib/actions.ts"`
- **Gotchas** — `"This project uses path aliases — import from @/lib/... not relative paths"`

#### Shared Files

Flag files that multiple stories will touch. This is essential for `ralph:convert` to generate accurate conflict avoidance data.

- `Shared file: src/app/layout.tsx (also modified by US-005) — append-only`
- `Shared file: prisma/schema.prisma (also modified by US-001) — structural-modify`

Classify as:
- **append-only** — adding new independent content (imports, route entries, new models)
- **structural-modify** — changing existing code (editing functions, modifying schemas)

#### Story Format

**Terminology:** Use **"phase"** for sequential grouping. Do NOT use "wave" — reserved for `ralph:run`.

```markdown
### US-001: [Title]
**Description:** As a [user], I want [feature] so that [benefit].

**Depends on:** (none) | US-XXX, US-YYY

**Acceptance Criteria:**
- [ ] Specific verifiable criterion
- [ ] Another criterion
- [ ] Typecheck/lint passes
- [ ] **[UI stories only]** Verify in browser

**Notes:**
- Modify `src/lib/db/schema.ts` to add new table
- Follow the pattern in `src/lib/db/schema.ts` where `usersTable` is defined
- Shared file: `src/lib/db/schema.ts` (also modified by US-003) — append-only
```

Acceptance criteria must be **verifiable**, not vague. "Works correctly" is bad. "Button shows confirmation dialog before deleting" is good.

### 4. Functional Requirements
Numbered list: "FR-1: The system must allow users to..."

Be explicit and unambiguous.

### 5. Non-Goals (Out of Scope)
What this feature will NOT include.

### 6. Technical & Design Considerations
- Relevant findings from codebase exploration (framework, patterns, components to reuse)
- Known constraints, integration points, performance requirements
- Write "None identified" if nothing to note.

### 7. Success Metrics
How will success be measured?

### 8. Open Questions
Remaining questions or areas needing clarification.

### Non-Feature Requests

For refactors, migrations, or infrastructure tasks: use a task breakdown instead of User Stories, omit Success Metrics if N/A.

## Writing for AI Workers

Each story is implemented by an autonomous AI agent in a fresh context. The worker has no memory of other stories and limited initial codebase knowledge. Write accordingly:

- Spell out file paths, function names, and patterns — don't assume the worker knows the project
- The Notes section is the worker's primary roadmap — make it concrete and actionable
- When referencing existing code, say exactly where it is (file path and what to look for)

## Checklist

Before saving the PRD:

- [ ] Explored the codebase (structure, patterns, related code)
- [ ] Asked clarifying questions via `AskUserQuestion`
- [ ] Incorporated user's answers
- [ ] Stories are small (1-3 files, 2-3 sentences, ≤5 acceptance criteria)
- [ ] Stories ordered by phase (schema → backend → UI → integration)
- [ ] Dependencies marked explicitly (`Depends on: US-XXX`)
- [ ] Each story has Notes with file paths and patterns from codebase exploration
- [ ] Shared files flagged with conflict type (append-only / structural-modify)
- [ ] Functional requirements numbered and unambiguous
- [ ] Non-goals define clear boundaries
- [ ] Acceptance criteria are verifiable

---

## Next Step

Before writing, ensure `.ralph-in-claude/tasks/` exists (create if needed).

Slugify the feature name to lowercase-kebab-case, max 4-5 words. E.g., `prd-csv-export.md`.

If a file with the same slug exists, use `AskUserQuestion` to ask overwrite or rename.

Save as `.ralph-in-claude/tasks/prd-[feature-slug].md`, then tell the user:

> PRD saved. Next step: run `/ralph:convert` to convert it to prd.json for execution.
