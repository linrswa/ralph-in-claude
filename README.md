# 🤖 Ralph for Claude Code

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Claude Code Plugin](https://img.shields.io/badge/Claude_Code-Plugin-blue.svg)](https://claude.com/claude-code)

[繁體中文](README.zh-TW.md)

An autonomous AI agent system for [Claude Code](https://claude.ai/code) that iteratively implements features from a PRD. Inspired by [Geoffrey Huntley's Ralph pattern](https://ghuntley.com/ralph/).

Packaged as a **Claude Code plugin** with three namespaced skills: `ralph:prd`, `ralph:convert`, `ralph:run`.

## 📰 Recent Updates

**v0.4.0** — Post-wave code review system (Sonnet wave-reviewer + Opus wave-coordinator for escalation); switched from Task tool's `isolation: "worktree"` to dispatcher-managed worktrees — the platform's worktree isolation creates from stale refs, so Wave N+1 workers couldn't see Wave N's merged changes, causing them to redundantly re-implement previous work and then hit merge conflicts on the duplicated code; removed experimental conflict-resolver agent (Tier 3) in favor of the wave-reviewer/coordinator pipeline; orphan worktree cleanup at startup.

**v0.3.7** — Next-step prompts in `ralph:prd` and `ralph:convert` skills guide users through the workflow.

**v0.3.6** — PRD output centralized to `.ralph-in-claude/tasks/`; `ralph:convert` auto-detects PRD files from that directory.

**v0.3.5** — Tightened prd.json schema validation.

**v0.3.4** — Default max parallel agents increased from 3 to 5.

**v0.3.2 ~ v0.3.3** — Switched ralph-worker model from Opus to Sonnet for better cost/speed balance.

**v0.3.0 ~ v0.3.1** — Worktree isolation for parallel workers. Added `sharedFiles` / `conflictStrategy` fields to prd.json, append-only conflict auto-resolve.

## 💡 Motivation

The original [Ralph](https://github.com/snarktank/ralph) was built for Amp — an autonomous loop that picks up stories from a PRD and implements them one by one, each in a fresh context to avoid exhaustion. This project started as a Claude Code adaptation of that pattern (a simple bash loop), and has since evolved to leverage Claude Code's native agentic primitives (Task system, Skills, Hooks, plugin marketplace) for **dependency-aware parallel execution** and **schema-validated data integrity**.

It works today, but there are still rough edges around hook scoping, subagent coordination, and error recovery. Work in progress.

## 🏛️ Architecture

### Current: Native Plugin (`/ralph:run`)

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
│  ┌─ 2. Wave Execution ────────────────────────────────────────────────┐  │
│  │                                                                     │  │
│  │   Single-story wave → Direct mode (commit on feature branch)        │  │
│  │   Multi-story wave  → Worktree mode (dispatcher-managed worktrees)  │  │
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
│  │   ┌─ 3. Merge Pipeline (worktree mode) ───────────────────────┐    │  │
│  │   │  Tier 1: git merge --no-ff (clean merge)                   │    │  │
│  │   │  Tier 2: append-only auto-resolve                          │    │  │
│  │   │  Tier 3: defer to wave review                               │    │  │
│  │   └────────────────────────────────────────────────────────────┘    │  │
│  │                                 │                                   │  │
│  │                                 ▼                                   │  │
│  │   4. Typecheck ──→ Update prd.json ──→ Append progress.txt          │  │
│  │                                 │                                   │  │
│  │                                 ▼                                   │  │
│  │   5. Wave Review (Phase A: resolve deferred conflicts,              │  │
│  │                   Phase B: consistency check)                       │  │
│  └─────────────────────────────────────────────────────────────────────┘  │
│                                    │                                      │
│                                    ▼                                      │
│   Repeat waves until: all passes=true  or  max waves exhausted            │
└───────────────────────────────────────────────────────────────────────────┘
```

See [docs/plan.md](docs/plan.md) for the full design document.

### Original: Bash Loop (`ralph.sh`)

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

The original approach: each iteration is a fresh Claude instance with no shared memory. State persists via `prd.json`, `progress.txt`, and git history. Still available as a fallback for CI/headless environments.

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

Answer the clarifying questions. Output saves to `.ralph-in-claude/tasks/prd-[feature-name].md`.

**2. Convert to Ralph format**

```
/ralph:convert .ralph-in-claude/tasks/prd-[feature-name].md
```

This creates `.ralph-in-claude/prd.json` with user stories structured for autonomous execution.

**3. Run Ralph**

**Native Plugin (recommended) — parallel execution:**

```
/ralph:run                          # uses .ralph-in-claude/prd.json, default 5 agents
/ralph:run path/to/prd.json        # custom prd path
/ralph:run .ralph-in-claude/prd.json 8  # custom prd path + max 8 parallel agents
```

The dispatcher reads `.ralph-in-claude/prd.json`, builds a dependency DAG, and spawns subagent workers in parallel waves (default 5 per wave, configurable via the second argument). Two execution modes are used:

- **Direct mode** (single-story wave): the worker commits directly on the feature branch — no worktree or merge needed.
- **Worktree mode** (multi-story wave): the dispatcher creates git worktrees from the feature branch HEAD, ensuring each wave sees all previous waves' merged changes. Workers commit in their worktrees, then the dispatcher merges via `git merge --no-ff`.

The dispatcher verifies results, updates prd.json, and spawns the next wave.

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
│   ├── wave-reviewer.md                # Sonnet agent — post-wave consistency review
│   └── wave-coordinator.md             # Opus agent — escalated wave issue resolution
├── hooks/
│   └── hooks.json                      # Plugin-level PreToolUse hooks (prd.json validation)
├── scripts/
│   ├── ensure-ralph-dir.sh             # Hook: auto-creates .ralph-in-claude/ dir
│   └── validate-prd-write.sh           # Hook: validates prd.json schema (9 checks)
├── skills/
│   ├── prd/
│   │   └── SKILL.md                    # ralph:prd — PRD generator
│   ├── convert/
│   │   └── SKILL.md                    # ralph:convert — PRD-to-JSON converter
│   └── run/
│       ├── SKILL.md                    # ralph:run — parallel dispatcher
│       └── references/
│           ├── subagent-prompt-template.md  # Worker prompt (dynamic context only)
│           ├── wave-review-prompt-template.md       # Wave reviewer prompt
│           └── wave-coordinator-prompt-template.md  # Wave coordinator prompt
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

### Shared Files & Conflict Resolution

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
  3. **Tier 3:** Defer to wave review — the story's merge is aborted and deferred to Phase A of the wave review, where the Sonnet wave-reviewer (with full wave context) attempts resolution. If the reviewer can't resolve, the Opus coordinator tries. If neither succeeds, a remediation story is created.

### Quality Gates

- **Dispatcher:** typecheck after each wave, `git merge --no-ff` per worker branch, retries failed stories up to 3 times
- **Wave review:** after each multi-story wave, a two-phase review runs: **Phase A** resolves any deferred merge conflicts (Tier 3) with full wave context — the Sonnet reviewer attempts resolution first, escalating to the Opus coordinator if needed; **Phase B** checks the combined diff for cross-cutting consistency issues (naming, imports, style), with major issues escalated to the coordinator.
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
