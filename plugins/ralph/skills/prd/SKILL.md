---
name: prd
description: "Generate a Product Requirements Document (PRD) for a new feature. Use when planning a feature, starting a new project, or when asked to create a PRD. Triggers on: create a prd, write prd for, plan this feature, requirements for, spec out."
argument-hint: "[feature-description]"
---

# PRD Generator

Create detailed Product Requirements Documents that are clear, actionable, and suitable for implementation.

**CRITICAL: When asking clarifying questions, ALWAYS use the `AskUserQuestion` tool. Do NOT output questions as plain text. The `AskUserQuestion` tool provides an interactive UI with selectable options.**

## The Job

1. Receive a feature description from the user
2. Ask 3-5 essential clarifying questions (with lettered options)
3. Generate a structured PRD based on answers
4. Save to `.ralph-in-claude/tasks/prd-[feature-name].md`

**Important:** Do NOT start implementing. Just create the PRD.

---

## Step 1: Clarifying Questions

Ask only critical questions where the initial prompt is ambiguous. Focus on:

- **Problem/Goal:** What problem does this solve?
- **Core Functionality:** What are the key actions?
- **Scope/Boundaries:** What should it NOT do?
- **Success Criteria:** How do we know it's done?

**IMPORTANT:** You MUST use the `AskUserQuestion` tool to ask these questions. This provides an interactive UI with selectable options instead of plain text. Structure your questions with 2-4 options each.

e.g., "What's the scope?" (Minimal / Full / API only / UI only) — the user can always select "Other" for custom input.

---

## Step 2: PRD Structure

Generate the PRD with these sections:

### 1. Introduction/Overview
Brief description of the feature and the problem it solves.

### 2. Goals
Specific, measurable objectives (bullet list).

### 3. User Stories
Each story needs:
- **Title:** Short descriptive name
- **Description:** "As a [user], I want [feature] so that [benefit]"
- **Acceptance Criteria:** Verifiable checklist of what "done" means

Each story should be small enough to implement in one focused session.

**Terminology:** When grouping stories into sequential stages (e.g., schema first, then backend, then UI), use the word **"phase"** (Phase 1, Phase 2, etc.). Do NOT use "wave" — that term is reserved for `ralph:run`'s parallel execution scheduling.

**Format:**
```markdown
### US-001: [Title]
**Description:** As a [user], I want [feature] so that [benefit].

**Acceptance Criteria:**
- [ ] Specific verifiable criterion
- [ ] Another criterion
- [ ] Typecheck/lint passes
- [ ] **[UI stories only]** Verify in browser
```

**Important:** Acceptance criteria must be verifiable, not vague. "Works correctly" is bad. "Button shows confirmation dialog before deleting" is good.

### 4. Functional Requirements
Numbered list of specific functionalities:
- "FR-1: The system must allow users to..."
- "FR-2: When a user clicks X, the system must..."

Be explicit and unambiguous.

### 5. Non-Goals (Out of Scope)
What this feature will NOT include. Critical for managing scope.

### 6. Technical & Design Considerations (Optional)
- UI/UX requirements, mockups, existing components to reuse
- Known constraints, dependencies, integration points, performance requirements

### 7. Success Metrics
How will success be measured?
- "Reduce time to complete X by 50%"
- "Increase conversion rate by 10%"

### 8. Open Questions
Remaining questions or areas needing clarification.

## Writing for Junior Developers

- Be explicit and unambiguous — avoid jargon or explain it
- Provide enough detail to understand purpose and core logic
- Use concrete examples and number requirements for easy reference

## Checklist

Before saving the PRD:

- [ ] Asked clarifying questions with lettered options
- [ ] Incorporated user's answers
- [ ] User stories are small and specific (one focused session each)
- [ ] Functional requirements are numbered and unambiguous
- [ ] Non-goals section defines clear boundaries

---

## Next Step

Save as `.ralph-in-claude/tasks/prd-[feature-name].md`, then tell the user:

> PRD saved. Next step: run `/ralph:convert` to convert it to prd.json for execution.
