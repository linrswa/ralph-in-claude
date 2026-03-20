# 🤖 Ralph for Claude Code

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Claude Code Plugin](https://img.shields.io/badge/Claude_Code-Plugin-blue.svg)](https://claude.com/claude-code)

[繁體中文](README.zh-TW.md)

An autonomous AI agent system for [Claude Code](https://claude.ai/code) that iteratively implements features from a PRD. Inspired by [Geoffrey Huntley's Ralph pattern](https://ghuntley.com/ralph/).

Packaged as a **Claude Code plugin** with four namespaced skills: `ralph:research`, `ralph:prd`, `ralph:convert`, `ralph:run`.

## 📰 Recent Updates

**v0.6.0** — **[Experimental] Team mode for `ralph:research`**. When 4+ research agents are spawned, agents can optionally join a shared team and exchange intermediate findings in real-time via `SendMessage`. Requires enabling `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` in settings (see [Team Mode](#-team-mode-experimental) below).

**v0.5.0** — Added `ralph:research` skill for pre-PRD feature discovery. Spawns parallel research agents to explore feasibility, architecture, existing code, prior art, scope, and risks. Produces a structured research report that feeds into `ralph:prd`.

**v0.4.8** — Improved all three core skills based on quality review; added codebase exploration to `ralph:prd` and `ralph:convert`; optimized `ralph:run` structure; added plugin update instructions.

See [CHANGELOG.md](CHANGELOG.md) for full version history.

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
│  ┌─ 2. Wave Execution ─────────────────────────────────────────────────┐  │
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
│  │   ┌─ 3. Merge Pipeline (worktree mode) ────────────────────────┐    │  │
│  │   │  Tier 1: git merge --no-ff (clean merge)                   │    │  │
│  │   │  Tier 2: append-only auto-resolve                          │    │  │
│  │   │  Tier 3: defer to wave review                              │    │  │
│  │   └────────────────────────────────────────────────────────────┘    │  │
│  │                                 │                                   │  │
│  │                                 ▼                                   │  │
│  │   4. Typecheck ──→ Update prd.json ──→ Append progress.txt          │  │
│  │                                 │                                   │  │
│  │                                 ▼                                   │  │
│  │   5. Wave Review (Phase A: resolve deferred conflicts,              │  │
│  │                   Phase B: consistency check,                       │  │
│  │                   Phase C: bridge work for next wave)               │  │
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

### Install from Marketplace

```bash
# Add the marketplace
claude plugin marketplace add linrswa/ralph-in-claude

# Install the plugin
claude plugin install ralph@ralph-in-claude
```

This enables `/ralph:prd`, `/ralph:convert`, and `/ralph:run` commands in any project.

### Update

```bash
# Update the marketplace to fetch latest versions
claude plugin marketplace update ralph-in-claude

# Update the plugin
claude plugin update ralph@ralph-in-claude
```

> **Note:** You must update the marketplace first — it refreshes the plugin catalog from the repo. Then `plugin update` pulls in the new version. After updating, run `/reload-plugins` to pick up any hook or command changes.

## 🚀 Workflow

**0. Research (optional)**

```
/ralph:research [feature idea or problem statement]
```

Spawns parallel research agents to explore feasibility, architecture, existing code, prior art, and risks. Produces a structured report saved to `.ralph-in-claude/tasks/`. Use this before writing a PRD to surface unknowns and trade-offs. Supports optional [team mode](#-team-mode-experimental) for complex research (4+ agents).

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
│   └── marketplace.json                # Marketplace definition (source: ./plugins/ralph)
├── plugins/
│   └── ralph/                          # Plugin root (installed by marketplace)
│       ├── .claude-plugin/
│       │   └── plugin.json             # Plugin manifest
│       ├── .claude/
│       │   └── settings.json           # Plugin permissions
│       ├── agents/
│       │   ├── ralph-worker.md         # Worker agent definition
│       │   ├── research-worker.md      # Sonnet agent — research angle investigator
│       │   ├── research-architect.md   # Opus agent — architecture & design research
│       │   ├── wave-reviewer.md        # Sonnet agent — post-wave consistency review
│       │   └── wave-coordinator.md     # Opus agent — escalated wave issue resolution
│       ├── hooks/
│       │   └── hooks.json              # Plugin-level PreToolUse hooks (prd.json validation)
│       ├── scripts/
│       │   ├── ensure-ralph-dir.sh     # Hook: auto-creates .ralph-in-claude/ dir
│       │   └── validate-prd-write.sh   # Hook: validates prd.json schema (9 checks)
│       ├── skills/
│       │   ├── research/
│       │   │   ├── SKILL.md            # ralph:research — parallel feature research
│       │   │   └── references/
│       │   │       ├── architect-prompt-template.md
│       │   │       ├── researcher-prompt-template.md
│       │   │       └── synthesis-guidelines.md
│       │   ├── prd/
│       │   │   └── SKILL.md            # ralph:prd — PRD generator
│       │   ├── convert/
│       │   │   └── SKILL.md            # ralph:convert — PRD-to-JSON converter
│       │   └── run/
│       │       ├── SKILL.md            # ralph:run — parallel dispatcher
│       │       └── references/
│       │           ├── subagent-prompt-template.md
│       │           ├── wave-review-prompt-template.md
│       │           └── wave-coordinator-prompt-template.md
│       └── CLAUDE.md                   # Plugin instructions (auto-read by Claude Code)
├── docs/                               # Dev-only documentation
├── CHANGELOG.md
├── LICENSE
├── README.md
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
- **Wave review:** after each multi-story wave, a three-phase review runs: **Phase A** resolves any deferred merge conflicts (Tier 3) with full wave context — the Sonnet reviewer attempts resolution first, escalating to the Opus coordinator if needed; **Phase B** checks the combined diff for cross-cutting consistency issues (naming, imports, style), with major issues escalated to the coordinator; **Phase C** performs bridge work for the next wave (e.g., inserting append-only marker comments in shared files to enable safe parallel modification).
- **Hooks:** validates prd.json schema on every Write/Edit (JSON integrity, required fields, `dependsOn` referential check)

## 🧪 Team Mode (Experimental)

The `ralph:research` skill supports an optional **team mode** for complex research (4+ agents). In team mode, research agents join a shared team and can share intermediate discoveries via `SendMessage` — for example, the Codebase Analysis agent discovering a critical pattern can immediately inform the Architecture agent, rather than waiting for the coordinator to synthesize after all agents finish.

### How it works

- **3 agents or fewer**: Normal parallel mode (no team). Agents work in isolation.
- **4+ agents**: Team mode is offered as an option at Checkpoint 1. If the user's prompt contains team intent keywords (e.g., "team", "swarm", "組隊", "協作"), team mode auto-enables.
- Agents check peer discoveries at **two checkpoints** (mid-exploration and pre-report) to avoid duplicated work and redirect research based on early findings.

### Enabling team mode

Team mode requires the Claude Code experimental agent teams feature. Add this to your settings (`~/.claude/settings.json`):

```json
{
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
  }
}
```

If the feature is not enabled, the skill will inform you how to enable it and fall back to normal parallel mode.

### When to use team mode

Team mode is most valuable when:
- Research angles have **strong cross-cutting dependencies** (e.g., a feasibility constraint that changes architectural design)
- Multiple agents are likely to **discover the same core issue independently** (team mode lets the first discoverer broadcast, saving others from duplicating)
- The topic is **ambiguous** with many unknowns (more benefit from early findings sharing)

For well-defined topics with clear codebase evidence, normal parallel mode produces comparable results at lower token cost.

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
