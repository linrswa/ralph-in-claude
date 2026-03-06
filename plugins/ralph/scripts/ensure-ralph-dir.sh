#!/usr/bin/env bash
# PreToolUse hook on Write/Edit: ensures .ralph-in-claude/ directory exists before writing.
# Exit 0 = allow, Exit 2 = block.
set -euo pipefail

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Only care about writes targeting .ralph-in-claude/
if [[ -z "$FILE_PATH" ]] || [[ "$FILE_PATH" != *.ralph-in-claude/* ]]; then
  exit 0
fi

# Resolve project root
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"

# Ensure .ralph-in-claude/ directory exists
mkdir -p "$PROJECT_DIR/.ralph-in-claude/tasks"

exit 0
