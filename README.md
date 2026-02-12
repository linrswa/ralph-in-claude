# Ralph for Claude Code

An autonomous AI agent system for [Claude Code](https://claude.ai/code) that iteratively implements features from a PRD. Inspired by [Geoffrey Huntley's Ralph pattern](https://ghuntley.com/ralph/).

## Background

The original [Ralph](https://github.com/snarktank/ralph) was built for Amp. This project started as a Claude Code adaptation of that pattern — a simple bash loop (`ralph.sh`) that spawns fresh Claude instances sequentially.

Now it's evolving into something more: leveraging Claude Code's native capabilities (Task system, Skills, Hooks) to build a smarter orchestration layer with **dependency-aware parallel execution** and **schema-validated data integrity**.

## Architecture

### v1: Sequential Bash Loop (current, stable)

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

### v2: Native Claude Code Integration (`/ralph-run`)

```
User invokes /ralph-run
  └─ Main Claude session (dispatcher)
       ├─ Read ralph/prd.json, build dependency DAG
       ├─ Wave 1: spawn up to 3 senior-engineer subagents (parallel)
       │    ├─ US-001 (schema)
       │    ├─ US-002 (config)
       │    └─ US-005 (independent)
       ├─ Verify: check git commits, run typecheck
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
| Quality checks | Soft (prompt instructions) | Skill hooks validate prd.json writes |
| Dependencies | Linear priority numbers | `dependsOn` DAG with topological ordering |
| Error recovery | Blind retry next iteration | Orchestrator can intervene and re-dispatch |

See [plan.md](plan.md) for the full v2 design document.

## Quick Start

### Prerequisites

- [Claude Code CLI](https://claude.ai/code) installed and authenticated
- `jq` installed (`brew install jq` / `apt install jq`)
- A git repository for your project

### Install Skills

Copy skills to your Claude Code config for use across all projects:

```bash
cp -r .claude/skills/prd ~/.claude/skills/
cp -r .claude/skills/ralph ~/.claude/skills/
cp -r .claude/skills/ralph-run ~/.claude/skills/
```

This enables `/prd`, `/ralph`, and `/ralph-run` commands in any project.

### Workflow

**1. Create a PRD**

```
/prd [your feature description]
```

Answer the clarifying questions. Output saves to `tasks/prd-[feature-name].md`.

**2. Convert to Ralph format**

```
/ralph tasks/prd-[feature-name].md
```

This creates `ralph/prd.json` with user stories structured for autonomous execution.

**3. Run Ralph**

**v2 (recommended) — parallel execution:**

```
/ralph-run
```

The dispatcher reads `ralph/prd.json`, builds a dependency DAG, and spawns up to 3 subagent workers per wave. Workers implement stories in parallel, commit, and report back. The dispatcher verifies results, updates prd.json, and spawns the next wave.

**v1 (fallback) — sequential execution:**

```bash
./ralph.sh [max_iterations]  # default: 10
```

Spawns one fresh Claude instance per story, sequentially. Useful for CI/headless environments.

## Key Files

| File | Purpose |
|------|---------|
| `.claude/skills/ralph-run/` | **v2 dispatcher** — parallel story orchestration (`/ralph-run`) |
| `.claude/skills/ralph/` | Skill for converting PRDs to JSON (`/ralph`) |
| `.claude/skills/prd/` | Skill for generating PRDs (`/prd`) |
| `.claude/hooks/` | Validation hooks (prd.json schema, directory setup) |
| `ralph.sh` | v1 bash loop — spawns fresh Claude instances |
| `prompt.md` | v1 instructions given to each Claude instance |
| `ralph/prd.json` | v2 user stories with status tracking and dependency graph |
| `prd.json` | v1 user stories (root-level, used by `ralph.sh`) |
| `prd.json.example` | Example format for reference |
| `ralph/progress.txt` | v2 append-only learnings across iterations |
| `progress.txt` | v1 append-only learnings (root-level) |
| `plan.md` | v2 architecture design document |

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
- **`ralph/progress.txt`** (v2) / **`progress.txt`** (v1) — append-only learnings and codebase patterns
- **`CLAUDE.md`** — reusable patterns that Claude Code auto-reads
- **Git history** — committed code from previous iterations

### Quality Gates

v2 enforces quality at two levels:

**Dispatcher-level** (after each wave):
- Verifies git commits exist for each completed story
- Runs project typecheck to catch regressions
- Retries failed stories up to 3 times with failure context

**Hook-level** (on every prd.json write):
- **prd.json validation hook** — blocks writes with invalid JSON or missing fields
- **`dependsOn` integrity check** — ensures all referenced story IDs exist
- **`ensure-ralph-dir` hook** — auto-creates `ralph/` directory before writes

## Debugging

```bash
# See story status (v2 path; use prd.json for v1)
jq '.userStories[] | {id, title, passes, dependsOn}' ralph/prd.json

# See learnings
cat ralph/progress.txt

# Check git history
git log --oneline -10
```

## References

- [Geoffrey Huntley's Ralph article](https://ghuntley.com/ralph/) — the original concept
- [Original Amp-based Ralph](https://github.com/snarktank/ralph) — the Amp implementation this project was inspired by
- [Claude Code documentation](https://docs.anthropic.com/en/docs/claude-code)
