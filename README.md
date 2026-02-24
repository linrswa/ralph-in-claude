# 🤖 Ralph for Claude Code

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Claude Code Plugin](https://img.shields.io/badge/Claude_Code-Plugin-blue.svg)](https://claude.com/claude-code)

[繁體中文](README.zh-TW.md)

An autonomous AI agent system for [Claude Code](https://claude.ai/code) that iteratively implements features from a PRD. Inspired by [Geoffrey Huntley's Ralph pattern](https://ghuntley.com/ralph/).

Packaged as a **Claude Code plugin** with three namespaced skills: `ralph:prd`, `ralph:convert`, `ralph:run`.

## 📰 Recent Updates

**v0.3.4** — Default max parallel agents increased from 3 to 5.

**v0.3.2 ~ v0.3.3** — Switched ralph-worker model from Opus to Sonnet for better cost/speed balance.

**v0.3.0 ~ v0.3.1** — Worktree isolation for parallel workers. Added `sharedFiles` / `conflictStrategy` fields to prd.json, append-only conflict auto-resolve, and conflict-resolver agent (experimental, untested).

## 💡 Motivation

The original [Ralph](https://github.com/snarktank/ralph) was built for Amp — an autonomous loop that picks up stories from a PRD and implements them one by one, each in a fresh context to avoid exhaustion. This project started as a Claude Code adaptation of that pattern (a simple bash loop), and is now evolving to leverage Claude Code's native agentic primitives (Task system, Skills, Hooks, plugin marketplace) for **dependency-aware parallel execution** and **schema-validated data integrity**.

It works today, but there are still rough edges around hook scoping, subagent coordination, and error recovery. Work in progress.

## 🏛️ Architecture

### Bash Loop (fallback)

```
┌──────────────────────────────────────────────────────────────────────┐
│ ralph.sh                                                             │
│                                                                      │
│  ┌─ Iteration 1 (fresh Claude instance) ──────────────────────────┐  │
│  │                                                                │  │
│  │   prd.json ──→ Pick highest-priority ──→ Implement ──→ Commit  │  │
│  │                incomplete story          & typecheck           │  │
│  │                                              │                 │  │
│  │                                              ▼                 │  │
│  │                               Set passes: true in prd.json     │  │
│  │                               Append to progress.txt           │  │
│  └────────────────────────────────────────────────────────────────┘  │
│                                  │                                   │
│                                  ▼                                   │
│  ┌─ Iteration 2 (fresh Claude instance, same flow) ───────────────┐  │
│  │  ...                                                           │  │
│  └────────────────────────────────────────────────────────────────┘  │
│                                  │                                   │
│                                  ▼                                   │
│          All passes=true ──→ EXIT   or   Max iterations ──→ EXIT     │
└──────────────────────────────────────────────────────────────────────┘
```

Each iteration is a fresh Claude instance with no shared memory. State persists via `prd.json`, `progress.txt`, and git history.

### Native Plugin (`/ralph:run`)

```
┌───────────────────────────────────────────────────────────────────────────┐
│ /ralph:run  (dispatcher)                                                  │
│                                                                           │
│  ┌─ 1. Read prd.json & Build Dependency DAG ──────────────────────────┐   │
│  │                                                                    │   │
│  │   US-001 (no deps) ──┐                                             │   │
│  │   US-002 (no deps) ──┼── Wave 1                                    │   │
│  │   US-005 (no deps) ──┘                                             │   │
│  │                                                                    │   │
│  │   US-003 (needs US-001) ──┐── Wave 2                               │   │
│  │   US-004 (needs US-002) ──┘                                        │   │
│  │                                                                    │   │
│  │   US-006 (needs US-003, US-004) ── Wave 3                          │   │
│  └────────────────────────────────────────────────────────────────────┘   │
│                                                                           │
│  ┌─ 2. Wave Execution (up to 5 workers in parallel) ───────────────────┐  │
│  │                                                                     │  │
│  │   ┌─ Worktree A ─────┐  ┌─ Worktree B ─────┐  ┌─ Worktree C ─────┐  │  │
│  │   │  ralph-worker    │  │  ralph-worker    │  │  ralph-worker    │  │  │
│  │   │  US-001          │  │  US-002          │  │  US-005          │  │  │
│  │   │  implement +     │  │  implement +     │  │  implement +     │  │  │
│  │   │  typecheck +     │  │  typecheck +     │  │  typecheck +     │  │  │
│  │   │  commit          │  │  commit          │  │  commit          │  │  │
│  │   └───────┬──────────┘  └───────┬──────────┘  └───────┬──────────┘  │  │
│  │           └─────────────────────┼─────────────────────┘             │  │
│  │                                 ▼                                   │  │
│  │   ┌─ 3. Merge Pipeline ────────────────────────────────────────┐    │  │
│  │   │  Tier 1: git merge --no-ff (clean merge)                   │    │  │
│  │   │  Tier 2: append-only auto-resolve                          │    │  │
│  │   │  Tier 3: conflict-resolver agent *                         │    │  │
│  │   │  Tier 4: abort & retry as failed story                     │    │  │
│  │   │                                                            │    │  │
│  │   │  * experimental, untested — see Conflict Resolution below  │    │  │
│  │   └────────────────────────────────────────────────────────────┘    │  │
│  │                                 │                                   │  │
│  │                                 ▼                                   │  │
│  │   4. Typecheck ──→ Update prd.json ──→ Append progress.txt          │  │
│  └─────────────────────────────────────────────────────────────────────┘  │
│                                    │                                      │
│                                    ▼                                      │
│   Repeat waves until: all passes=true  or  max waves exhausted            │
└───────────────────────────────────────────────────────────────────────────┘
```

See [docs/plan.md](docs/plan.md) for the full design document.

## 📦 Installation

### Prerequisites

- [Claude Code CLI](https://claude.ai/code) installed and authenticated
- `jq` installed (`brew install jq` / `apt install jq`)
- A git repository for your project

### Install as Plugin

1. Register the local marketplace (if not already done):

```bash
# From Claude Code, run:
/plugin marketplace add /path/to/your/marketplace
```

2. Install the ralph plugin:

```bash
/plugin install ralph@local
```

3. Enable in `~/.claude/settings.json`:

```json
{
  "enabledPlugins": {
    "ralph@local": true
  }
}
```

This enables `/ralph:prd`, `/ralph:convert`, and `/ralph:run` commands in any project.

## 🚀 Workflow

**1. Create a PRD**

```
/ralph:prd [your feature description]
```

Answer the clarifying questions. Output saves to `tasks/prd-[feature-name].md`.

**2. Convert to Ralph format**

```
/ralph:convert tasks/prd-[feature-name].md
```

This creates `.ralph-in-claude/prd.json` with user stories structured for autonomous execution.

**3. Run Ralph**

**Native Plugin (recommended) — parallel execution:**

```
/ralph:run                          # uses .ralph-in-claude/prd.json, default 5 agents
/ralph:run path/to/prd.json        # custom prd path
/ralph:run .ralph-in-claude/prd.json 8  # custom prd path + max 8 parallel agents
```

The dispatcher reads `.ralph-in-claude/prd.json`, builds a dependency DAG, and spawns subagent workers in parallel waves (default 5 per wave, configurable via the second argument). Each worker runs in an isolated git worktree, commits its changes independently, and reports back. The dispatcher verifies results, merges each worker's branch via `git merge --no-ff`, updates prd.json, and spawns the next wave.

**Bash Loop (fallback) — sequential execution:**

```bash
./ralph.sh [max_iterations]  # default: 10
```

Spawns one fresh Claude instance per story, sequentially. Useful for CI/headless environments.

## 🏗️ Plugin Structure

```
ralph-in-claude/
├── .claude-plugin/
│   └── plugin.json                     # Plugin manifest
├── agents/
│   ├── ralph-worker.md                 # Worker agent definition (shipped with plugin)
│   └── conflict-resolver.md            # Conflict resolution agent (experimental, untested)
├── hooks/
│   └── hooks.json                      # Plugin-level PreToolUse hooks (prd.json validation)
├── scripts/
│   ├── ensure-ralph-dir.sh             # Hook: auto-creates .ralph-in-claude/ dir
│   └── validate-prd-write.sh           # Hook: validates prd.json schema (6 checks)
├── skills/
│   ├── prd/
│   │   └── SKILL.md                    # ralph:prd — PRD generator
│   ├── convert/
│   │   └── SKILL.md                    # ralph:convert — PRD-to-JSON converter
│   └── run/
│       ├── SKILL.md                    # ralph:run — parallel dispatcher
│       └── references/
│           ├── subagent-prompt-template.md  # Worker prompt (dynamic context only)
│           └── conflict-resolver-prompt-template.md  # Conflict resolver prompt (experimental)
├── docs/
│   ├── plan.md                         # Native Plugin design document
│   └── WIP.md                          # Open issues & backlog
├── CLAUDE.md                           # Project instructions (auto-read by Claude Code)
├── ralph.sh                            # Bash Loop fallback
└── prompt.md                           # Bash Loop worker prompt
```

> **Note on hooks:** SKILL.md frontmatter hooks don't fire for marketplace-installed plugins
> ([#17688](https://github.com/anthropics/claude-code/issues/17688)). Hooks are defined at
> plugin level (`hooks/hooks.json`) as a workaround. When the bug is fixed, hooks can be
> moved back to SKILL.md for skill-scoped execution.

## 🧩 Core Concepts

### Story Sizing

Each story must be completable in **one iteration** (one context window). If the LLM runs out of context, it produces broken code.

**Right-sized:** Add a DB column, create a UI component, update a server action, add a filter dropdown.

**Too big (split these):** "Build entire dashboard", "Add authentication", "Refactor the API".

**Rule of thumb:** If you can't describe the change in 2-3 sentences, it's too big.

### Dependency Graph

Stories declare dependencies via `dependsOn`:

```json
{
  "id": "US-003",
  "dependsOn": ["US-001", "US-002"],
  "priority": 3
}
```

- `dependsOn: []` — no dependencies, can execute immediately
- Stories won't be picked until all dependencies have `passes: true`
- `priority` breaks ties among stories at the same dependency level

### Knowledge Transfer

Between iterations, knowledge persists through:
- **`.ralph-in-claude/progress.txt`** (Native Plugin) / **`progress.txt`** (Bash Loop) — append-only learnings and codebase patterns
- **`CLAUDE.md`** — reusable patterns that Claude Code auto-reads
- **Git history** — committed code from previous iterations

### Shared Files & Conflict Resolution (experimental, untested)

> **Note:** This feature has been implemented but has **not yet been triggered in any real-world run**. All test scenarios so far had clean merges or append-only changes that resolved automatically. Use with caution.

Stories can declare shared files via `sharedFiles` to indicate files that multiple stories may modify:

```json
{
  "id": "US-003",
  "sharedFiles": [
    { "file": "src/index.ts", "conflictType": "append-only", "reason": "import registration" },
    "src/config.ts"
  ]
}
```

The project-level `conflictStrategy` controls how the dispatcher handles overlapping stories:

- **`"conservative"`** (default) — defers all stories with overlapping `sharedFiles` to separate waves
- **`"optimistic"`** — allows `append-only` overlaps to run in parallel, with a tiered merge pipeline:
  1. **Tier 1:** `git merge` — if it succeeds cleanly, done
  2. **Tier 2:** Append-only auto-resolve — automatically resolves conflict markers in files tagged `append-only`
  3. **Tier 3:** Conflict resolver agent — spawns `conflict-resolver` subagent to intelligently resolve structural conflicts
  4. **Tier 4:** Abort and retry — treats the story as failed

### Quality Gates

- **Dispatcher:** typecheck after each wave, `git merge --no-ff` per worker branch, retries failed stories up to 3 times
- **Hooks:** validates prd.json schema on every Write/Edit (JSON integrity, required fields, `dependsOn` referential check)

## 🐛 Debugging

```bash
# See story status (Native Plugin path; use prd.json for Bash Loop)
jq '.userStories[] | {id, title, passes, dependsOn}' .ralph-in-claude/prd.json

# See learnings
cat .ralph-in-claude/progress.txt

# Check git history
git log --oneline -10
```

## 🔗 References

- [Geoffrey Huntley's Ralph article](https://ghuntley.com/ralph/) — the original concept
- [Original Amp-based Ralph](https://github.com/snarktank/ralph) — the Amp implementation this project was inspired by
- [Claude Code documentation](https://docs.anthropic.com/en/docs/claude-code)
