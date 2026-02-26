# Wave {{WAVE_NUMBER}} Review — {{PROJECT_NAME}}

## Assignment

Review the combined output of wave {{WAVE_NUMBER}} for cross-cutting consistency issues.

---

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
