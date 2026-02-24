# Merge Conflict Resolution

A merge conflict occurred while merging story {{FAILED_STORY_ID}} into the feature branch. A previously merged story ({{MERGED_STORY_ID}}) conflicts with the incoming changes.

## The Story Being Merged (Theirs)

- **ID:** {{FAILED_STORY_ID}}
- **Title:** {{FAILED_STORY_TITLE}}
- **Description:** {{FAILED_STORY_DESCRIPTION}}

### Acceptance Criteria

{{FAILED_STORY_CRITERIA}}

### Diff (changes this story made)

```diff
{{FAILED_STORY_DIFF}}
```

## The Previously Merged Story (Ours)

- **ID:** {{MERGED_STORY_ID}}
- **Title:** {{MERGED_STORY_TITLE}}
- **Description:** {{MERGED_STORY_DESCRIPTION}}

### Acceptance Criteria

{{MERGED_STORY_CRITERIA}}

### Diff (changes this story made, restricted to conflicted files)

```diff
{{MERGED_STORY_DIFF}}
```

---

## Conflict Details

- **Branch being merged:** {{BRANCH_NAME}}
- **Conflicted files:** {{CONFLICTED_FILES}}

## Context

- **Project:** {{PROJECT_NAME}}
- **Source PRD:** {{SOURCE_PRD}} (read for additional context if needed)

### Codebase Patterns

{{CODEBASE_PATTERNS}}

---

## Instructions

1. Read each conflicted file listed above — they contain diff3-style conflict markers
2. Understand both stories' intent from their descriptions, criteria, and diffs
3. Resolve each conflict to preserve BOTH stories' functionality
4. Edit the conflicted files to remove all conflict markers
5. Stage resolved files with `git add`
6. Run typecheck to verify the resolution compiles
7. Complete the merge with `git commit --no-edit`
8. Report your results in the required format
