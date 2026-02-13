# Ralph for Claude Code

An autonomous AI agent system for [Claude Code](https://claude.ai/code) that iteratively implements features from a PRD. Inspired by [Geoffrey Huntley's Ralph pattern](https://ghuntley.com/ralph/).

Packaged as a **Claude Code plugin** with three namespaced skills: `ralph:prd`, `ralph:convert`, `ralph:run`.

## Background

The original [Ralph](https://github.com/snarktank/ralph) was built for Amp. This project started as a Claude Code adaptation of that pattern — a simple bash loop (`ralph.sh`) that spawns fresh Claude instances sequentially.

Now it's evolving into something more: leveraging Claude Code's native capabilities (Task system, Skills, Hooks) to build a smarter orchestration layer with **dependency-aware parallel execution** and **schema-validated data integrity**.

## Architecture

### v1: Sequential Bash Loop (fallback)

```
ralph.sh
  └─ for loop (max N iterations)
       └─ claude -p prompt.md
            └─ Read prd.json → pick highest-priority story
            └─ Implement → typecheck → commit → set passes: true
            └─ Write progress.txt
       └─ Check <promise>COMPLETE</promise> → exit or continue
```

Each iteration is a fresh Claude instance with no shared memory. State persists via `prd.json`, `progress.txt`, and git history.

### v2: Native Claude Code Integration (`/ralph:run`)

```
User invokes /ralph:run
  └─ Main Claude session (dispatcher)
       ├─ Read .ralph-in-claude/prd.json, build dependency DAG
       ├─ Wave 1: spawn up to N ralph-worker subagents (parallel, default 3)
       │    ├─ US-001 (schema)
       │    ├─ US-002 (config)
       │    └─ US-005 (independent)
       ├─ Verify: check files, run typecheck, dispatcher commits per story
       ├─ Update prd.json passes, append progress.txt
       ├─ Wave 2: spawn newly unblocked stories
       │    ├─ US-003 (depended on US-001)
       │    └─ US-004 (depended on US-002)
       ├─ Verify, update, repeat
       └─ All stories done → report completion
```

Key improvements over v1:

| | v1 (ralph.sh) | v2 (native) |
|---|---|---|
| Orchestration | External bash loop | Main Claude session |
| Execution | Strictly sequential | Parallel via dependency DAG |
| Quality checks | Soft (prompt instructions) | Plugin hooks validate prd.json writes |
| Dependencies | Linear priority numbers | `dependsOn` DAG with topological ordering |
| Error recovery | Blind retry next iteration | Orchestrator can intervene and re-dispatch |

See [plan.md](plan.md) for the full v2 design document.

## Installation

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

## Workflow

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

**v2 (recommended) — parallel execution:**

```
/ralph:run                          # uses .ralph-in-claude/prd.json, default 3 agents
/ralph:run path/to/prd.json        # custom prd path
/ralph:run .ralph-in-claude/prd.json 5  # custom prd path + max 5 parallel agents
```

The dispatcher reads `.ralph-in-claude/prd.json`, builds a dependency DAG, and spawns subagent workers in parallel waves (default 3 per wave, configurable via the second argument). If max agents is set above 3, the dispatcher will prompt for confirmation about increased file race condition risk. Workers implement stories in parallel and report back. The dispatcher verifies results, commits each story's files, updates prd.json, and spawns the next wave.

**v1 (fallback) — sequential execution:**

```bash
./ralph.sh [max_iterations]  # default: 10
```

Spawns one fresh Claude instance per story, sequentially. Useful for CI/headless environments.

## Plugin Structure

```
ralph-in-claude/
├── .claude-plugin/
│   └── plugin.json                     # Plugin manifest
├── agents/
│   └── ralph-worker.md                 # Worker agent definition (shipped with plugin)
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
│           └── subagent-prompt-template.md  # Worker prompt (dynamic context only)
├── CLAUDE.md                           # Project instructions (auto-read by Claude Code)
├── ralph.sh                            # v1 fallback loop
├── prompt.md                           # v1 worker prompt
└── plan.md                             # v2 design document
```

> **Note on hooks:** SKILL.md frontmatter hooks don't fire for marketplace-installed plugins
> ([#17688](https://github.com/anthropics/claude-code/issues/17688)). Hooks are defined at
> plugin level (`hooks/hooks.json`) as a workaround. When the bug is fixed, hooks can be
> moved back to SKILL.md for skill-scoped execution.

## Key Files

| File | Purpose |
|------|---------|
| `.claude-plugin/plugin.json` | Plugin manifest |
| `agents/ralph-worker.md` | Worker agent definition (role, rules, report format) |
| `hooks/hooks.json` | Plugin-level hooks — validates prd.json on Write/Edit |
| `scripts/ensure-ralph-dir.sh` | Auto-creates `.ralph-in-claude/` directory |
| `scripts/validate-prd-write.sh` | Validates prd.json schema (JSON, fields, dependsOn integrity) |
| `skills/prd/SKILL.md` | `ralph:prd` — PRD generator |
| `skills/convert/SKILL.md` | `ralph:convert` — PRD-to-JSON converter |
| `skills/run/SKILL.md` | `ralph:run` — parallel story dispatcher |
| `skills/run/references/subagent-prompt-template.md` | Worker prompt template (dynamic story context) |
| `ralph.sh` | v1 bash loop — spawns fresh Claude instances |
| `prompt.md` | v1 instructions given to each Claude instance |
| `.ralph-in-claude/prd.json` | User stories with status tracking and dependency graph |
| `.ralph-in-claude/progress.txt` | Append-only learnings across iterations |

## Core Concepts

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
- **`.ralph-in-claude/progress.txt`** (v2) / **`progress.txt`** (v1) — append-only learnings and codebase patterns
- **`CLAUDE.md`** — reusable patterns that Claude Code auto-reads
- **Git history** — committed code from previous iterations

### Quality Gates

v2 enforces quality at two levels:

**Dispatcher-level** (after each wave):
- Verifies reported files exist, runs project typecheck
- Dispatcher stages and commits each story's files sequentially (workers don't touch git)
- Retries failed stories up to 3 times with failure context

**Hook-level** (on every prd.json write):
- **prd.json validation hook** — blocks writes with invalid JSON or missing fields
- **`dependsOn` integrity check** — ensures all referenced story IDs exist
- **`ensure-ralph-dir` hook** — auto-creates `.ralph-in-claude/` directory before writes

## Debugging

```bash
# See story status (v2 path; use prd.json for v1)
jq '.userStories[] | {id, title, passes, dependsOn}' .ralph-in-claude/prd.json

# See learnings
cat .ralph-in-claude/progress.txt

# Check git history
git log --oneline -10
```

## References

- [Geoffrey Huntley's Ralph article](https://ghuntley.com/ralph/) — the original concept
- [Original Amp-based Ralph](https://github.com/snarktank/ralph) — the Amp implementation this project was inspired by
- [Claude Code documentation](https://docs.anthropic.com/en/docs/claude-code)
