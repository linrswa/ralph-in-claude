#!/usr/bin/env bash
# Validates prd.json schema.
#
# Usage:
#   bash validate-prd-write.sh <file>        — validate a prd.json file on disk
#   echo '{"tool_input":...}' | validate-prd-write.sh  — hook mode via stdin (Write or Edit)
#
# Exit 0 = valid, Exit 2 = block (invalid).
set -euo pipefail

# --- Determine content source ---
if [[ $# -ge 1 ]]; then
  # CLI mode: first argument is a file path
  FILE="$1"
  if [[ ! -f "$FILE" ]]; then
    echo "FAILED: file not found: $FILE" >&2
    exit 2
  fi
  CONTENT=$(cat "$FILE")
else
  # Stdin hook mode (PreToolUse JSON payload)
  INPUT=$(cat)
  FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

  # Only validate prd.json files
  if [[ -z "$FILE_PATH" ]] || [[ "$(basename "$FILE_PATH")" != "prd.json" ]]; then
    exit 0
  fi

  # Try Write tool first (.tool_input.content)
  CONTENT=$(echo "$INPUT" | jq -r '.tool_input.content // empty')

  if [[ -z "$CONTENT" ]]; then
    # Edit tool: simulate the edit and validate the result
    OLD_STR=$(echo "$INPUT" | jq -r '.tool_input.old_string // empty')

    if [[ -n "$OLD_STR" ]] && [[ -f "$FILE_PATH" ]]; then
      CONTENT=$(echo "$INPUT" | python3 -c "
import sys, json

inp = json.load(sys.stdin)
ti = inp.get('tool_input', {})
old = ti.get('old_string', '')
new = ti.get('new_string', '')
replace_all = ti.get('replace_all', False)

with open(ti['file_path']) as f:
    content = f.read()

if replace_all:
    result = content.replace(old, new)
else:
    result = content.replace(old, new, 1)

print(result)
")
    fi
  fi
fi

if [[ -z "$CONTENT" ]]; then
  echo "prd.json validation FAILED: content is empty." >&2
  exit 2
fi

# 1. Valid JSON
if ! echo "$CONTENT" | jq . > /dev/null 2>&1; then
  echo "prd.json validation FAILED: content is not valid JSON." >&2
  exit 2
fi

# 2. .project (string)
PROJECT=$(echo "$CONTENT" | jq -r '.project // empty')
if [[ -z "$PROJECT" ]]; then
  echo "prd.json validation FAILED: missing or empty .project field." >&2
  exit 2
fi

# 3. .branchName (string)
BRANCH=$(echo "$CONTENT" | jq -r '.branchName // empty')
if [[ -z "$BRANCH" ]]; then
  echo "prd.json validation FAILED: missing or empty .branchName field." >&2
  exit 2
fi

# 4. .userStories (non-empty array)
STORY_COUNT=$(echo "$CONTENT" | jq '.userStories | if type == "array" then length else -1 end')
if [[ "$STORY_COUNT" -le 0 ]]; then
  echo "prd.json validation FAILED: .userStories must be a non-empty array." >&2
  exit 2
fi

# 5. Each story has required fields
MISSING=$(echo "$CONTENT" | jq -r '
  .userStories | to_entries[] |
  select(
    (.value.id | type) != "string" or
    (.value.title | type) != "string" or
    (.value.acceptanceCriteria | type) != "array" or
    (.value.dependsOn | type) != "array" or
    (.value.sharedFiles | type) != "array" or
    (.value.priority == null) or
    (.value.passes == null)
  ) |
  "Story at index \(.key): missing required fields (need id, title, acceptanceCriteria, dependsOn, sharedFiles, priority, passes)"
')

if [[ -n "$MISSING" ]]; then
  echo "prd.json validation FAILED:" >&2
  echo "$MISSING" >&2
  exit 2
fi

# 6. dependsOn references must exist
INVALID_DEPS=$(echo "$CONTENT" | jq -r '
  [.userStories[].id] as $ids |
  .userStories[] |
  .id as $sid |
  .dependsOn[] |
  select(. as $dep | $ids | index($dep) | not) |
  "Story \($sid) depends on non-existent story: \(.)"
')

if [[ -n "$INVALID_DEPS" ]]; then
  echo "prd.json validation FAILED:" >&2
  echo "$INVALID_DEPS" >&2
  exit 2
fi

# 7. sharedFiles entries: accept string or {file: string, conflictType: "append-only"|"structural-modify", reason: string}
INVALID_SF=$(echo "$CONTENT" | jq -r '
  .userStories | to_entries[] |
  .key as $idx | .value.id as $sid |
  .value.sharedFiles | to_entries[] |
  .value |
  if type == "string" then empty
  elif type == "object" then
    if (.file | type) != "string" then
      "Story \($sid) sharedFiles: object entry missing \"file\" string field"
    elif (.conflictType | type) != "string" then
      "Story \($sid) sharedFiles: object entry missing \"conflictType\" string field"
    elif (.conflictType | IN("append-only", "structural-modify") | not) then
      "Story \($sid) sharedFiles: invalid conflictType \"\(.conflictType)\" (must be \"append-only\" or \"structural-modify\")"
    elif (.reason | type) != "string" then
      "Story \($sid) sharedFiles: object entry missing \"reason\" string field"
    else empty
    end
  else
    "Story \($sid) sharedFiles: entry must be a string or {file, conflictType, reason} object, got \(type)"
  end
')

if [[ -n "$INVALID_SF" ]]; then
  echo "prd.json validation FAILED:" >&2
  echo "$INVALID_SF" >&2
  exit 2
fi

# 8. conflictStrategy (optional): must be "conservative" or "optimistic"
CONFLICT_STRATEGY=$(echo "$CONTENT" | jq -r '.conflictStrategy // empty')
if [[ -n "$CONFLICT_STRATEGY" ]]; then
  if [[ "$CONFLICT_STRATEGY" != "conservative" && "$CONFLICT_STRATEGY" != "optimistic" ]]; then
    echo "prd.json validation FAILED: conflictStrategy must be \"conservative\" or \"optimistic\", got \"$CONFLICT_STRATEGY\"" >&2
    exit 2
  fi
fi

# 9. Per-story optional fields: isRemediation (boolean), remediationDepth (number, max 2)
INVALID_REM=$(echo "$CONTENT" | jq -r '
  .userStories | to_entries[] |
  .value.id as $sid | .value |
  (
    if has("isRemediation") and (.isRemediation | type) != "boolean" then
      "Story \($sid): isRemediation must be a boolean, got \(.isRemediation | type)"
    else empty end
  ),
  (
    if has("remediationDepth") then
      if (.remediationDepth | type) != "number" then
        "Story \($sid): remediationDepth must be a number, got \(.remediationDepth | type)"
      elif .remediationDepth > 2 then
        "Story \($sid): remediationDepth must be <= 2, got \(.remediationDepth)"
      else empty end
    else empty end
  )
')

if [[ -n "$INVALID_REM" ]]; then
  echo "prd.json validation FAILED:" >&2
  echo "$INVALID_REM" >&2
  exit 2
fi

echo "prd.json validation passed." >&2
exit 0
