#!/usr/bin/env bash
# PreToolUse hook on Write: ensures ralph/ directory exists before writing.
# Exit 0 = allow, Exit 2 = block.
set -euo pipefail

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Only care about writes targeting ralph/
if [[ -z "$FILE_PATH" ]] || [[ "$FILE_PATH" != *ralph/* ]]; then
  exit 0
fi

# Resolve project root
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"

# Ensure ralph/ directory exists
mkdir -p "$PROJECT_DIR/ralph"

exit 0
