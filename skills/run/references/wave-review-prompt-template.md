# Wave {{WAVE_NUMBER}} Review — {{PROJECT_NAME}}

## Assignment

Review the combined output of wave {{WAVE_NUMBER}}.

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

**If a "Conflict Resolution Task" section appears above**, your primary task is resolving the merge conflict:

1. Read each conflicted file in full to understand both sides of the conflict
2. Read the source PRD to understand the overall feature context and the deferred story's intent
3. Edit the conflicted files to remove ALL conflict markers (`<<<<<<<`, `|||||||`, `=======`, `>>>>>>>`) while preserving the intent of BOTH the existing branch code and the incoming story's changes
4. Stage the resolved files: `git add <resolved-files>`
5. Complete the merge: `git commit --no-edit`
6. Run the project's typecheck command to verify nothing breaks
7. As a secondary check, review the resolved code for any consistency issues with the rest of the wave
8. Report your results in the required format

**If no "Conflict Resolution Task" section appears**, perform a consistency review:

1. Read the wave diff above — this is the combined output of all stories in this wave
2. Read the source PRD to understand the overall feature context
3. For each affected file, read the full file (not just the diff) to understand context
4. Check for:
   - Naming inconsistencies across stories (functions, variables, files)
   - Duplicate utilities or helpers written by different workers
   - Import organization issues
   - Style inconsistencies
   - Integration gaps between stories
5. Categorize each issue as minor (you can fix) or major (needs escalation)
6. Fix minor issues or escalate major ones per your operational rules
7. Report your results in the required format
