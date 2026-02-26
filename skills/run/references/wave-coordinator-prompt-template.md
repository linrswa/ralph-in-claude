# Wave {{WAVE_NUMBER}} Coordination — {{PROJECT_NAME}}

## Escalation Report from Wave Reviewer

{{REVIEWER_REPORT}}

---

{{CONFLICT_CONTEXT}}

## Stories in This Wave

{{PASSED_STORIES}}

---

## Combined Wave Diff

```diff
{{WAVE_DIFF}}
```

---

## Context

- **Project:** {{PROJECT_NAME}}
- **Source PRD:** {{SOURCE_PRD}} (read for additional context if needed)

### Codebase Patterns

{{CODEBASE_PATTERNS}}

---

## Instructions

**If a "Conflict Resolution Task" section appears above**, you are handling an escalated merge conflict that the wave reviewer could not resolve:

1. Read each conflicted file in full to understand both sides of the conflict
2. Read the source PRD and the deferred story's details to understand intent
3. Decide: can you resolve the conflict directly, or does it need a remediation story?
4. **If fixing directly:**
   - Edit the conflicted files to remove ALL conflict markers while preserving both sides' intent
   - Stage and commit: `git add <resolved-files> && git commit --no-edit`
   - Run typecheck/lint/tests to verify
   - Report Status: FIXED
5. **If the conflict is too complex to resolve safely:**
   - Report Status: REMEDIATION
   - Provide a detailed remediation story spec (title, description, acceptance criteria, dependsOn)

**If no "Conflict Resolution Task" section appears**, handle the escalated consistency issues:

1. Analyze the escalation report above — understand each major issue
2. Read affected files in full to understand the complete context
3. Read the source PRD to understand overall feature goals
4. For each issue, decide: fix directly or recommend remediation
5. If fixing: make minimal, focused edits and verify with typecheck/lint/tests
6. If recommending remediation: provide detailed story specs (title, description, acceptance criteria, dependsOn)
7. Report your results in the required format
