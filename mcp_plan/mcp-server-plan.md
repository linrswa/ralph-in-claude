# MCP Server Plan for Ralph State Management

## 1. Problem Analysis

The current Ralph dispatcher manages two stateful files — `prd.json` and `state.json` — using Claude Code's general-purpose `Read`, `Edit`, and `Write` tools. Every mutation follows this expensive pattern:

1. **Read** the entire file (tokens proportional to file size)
2. **Edit** by constructing exact old-string/new-string pairs (error-prone, token-heavy)
3. **Hook validation** via `validate-prd-write.sh` intercepts the `Edit`/`Write`, simulates the edit in bash/python/jq, then validates the result (fragile, slow)

An MCP server can expose purpose-built tools that perform atomic, validated reads and writes internally, returning only the data the dispatcher needs.

---

## 2. Architecture Overview

```
┌──────────────────────┐       stdio        ┌──────────────────────────┐
│  Claude Code         │◄──────────────────►│  ralph-state MCP server  │
│  (dispatcher agent)  │   JSON-RPC 2.0     │                          │
│                      │                     │  - File-based state      │
│  Calls MCP tools:    │                     │  - Built-in validation   │
│  ralph_get_prd       │                     │  - Atomic file writes    │
│  ralph_mark_passed   │                     │  - File locking          │
│  ...                 │                     │  Single process, no deps │
└──────────────────────┘                     └──────────────────────────┘
```

**Key decisions:**

- **Single process, stdio transport.** Claude Code spawns the server as a child process.
- **File-based state.** The server reads/writes `prd.json` and `state.json` directly on disk. It is the sole writer.
- **Built-in validation.** All validation logic from `validate-prd-write.sh` moves into TypeScript/Zod.
- **File locking.** Write operations use `mkdir`-based locking (atomic on all filesystems).
- **Single bundled JS file.** TypeScript compiled via `esbuild` into `dist/ralph-state-server.js`. No `npm install` needed by users.

---

## 3. Tool Inventory (15 tools)

### 3.1 PRD Read Tools

#### `ralph_get_prd`

Returns the full prd.json content. Used at initialization and at the start of each wave.

| Field | Value |
|-------|-------|
| **Parameters** | `prdPath` (string, optional, default `.ralph-in-claude/prd.json`) |
| **Returns** | Full parsed prd.json object |
| **Errors** | File not found; invalid JSON; schema validation failure |

#### `ralph_get_ready_stories`

Returns only stories eligible for the next wave, with retry counts pre-computed. **Most token-saving tool** — replaces reading full file + parsing notes + filtering dependencies.

| Field | Value |
|-------|-------|
| **Parameters** | `prdPath` (string, optional), `maxRetries` (number, optional, default 3) |
| **Returns** | `{ conflictStrategy: string, stories: ReadyStory[] }` |
| **Errors** | File not found; invalid JSON |

**Server-side logic:**
1. Parse prd.json
2. For each story with `passes: false`, count `"Attempt N failed:"` entries in `notes`
3. Ready if: all `dependsOn` stories have `passes: true` AND retryCount < maxRetries
4. Sort by priority ascending

Note: The dispatcher still does conflict-aware wave selection (sharedFiles overlap checking) because that's a stateful, iterative algorithm.

#### `ralph_get_project_info`

Returns project-level metadata only (no stories array). For template substitution.

| Field | Value |
|-------|-------|
| **Parameters** | `prdPath` (string, optional) |
| **Returns** | `{ project, branchName, baseBranch, sourcePrd, description, conflictStrategy }` |

---

### 3.2 PRD Write Tools

#### `ralph_mark_story_passed`

Marks a story's `passes` field to `true`. The single most common prd.json mutation.

| Field | Value |
|-------|-------|
| **Parameters** | `prdPath` (string, optional), `storyId` (string, required) |
| **Returns** | `{ success: true, story: { id, title, passes: true } }` |
| **Errors** | Story not found; write failure |

#### `ralph_append_story_failure`

Appends a failure note: `"Attempt N failed: <reason>"`. Server computes N automatically.

| Field | Value |
|-------|-------|
| **Parameters** | `prdPath` (string, optional), `storyId` (string, required), `reason` (string, required) |
| **Returns** | `{ success: true, storyId, attemptNumber, retryCount, maxRetriesReached }` |

#### `ralph_add_remediation_story`

Creates a new remediation story in prd.json (Tier 4 of merge pipeline).

| Field | Value |
|-------|-------|
| **Parameters** | `prdPath` (string, optional), `originalStoryId` (string), `mergedStoryId` (string), `conflictedFiles` (string[]), `priority` (number) |
| **Returns** | `{ success: true, remediationStory: { id, title, ... } }` |
| **Errors** | Story not found; remediationDepth > 2; validation failure |

#### `ralph_update_story_notes`

General-purpose notes update.

| Field | Value |
|-------|-------|
| **Parameters** | `prdPath` (string, optional), `storyId` (string), `notes` (string), `mode` (enum: `"replace"` or `"append"`, default `"append"`) |
| **Returns** | `{ success: true, storyId, notes }` |

---

### 3.3 State Management Tools

#### `ralph_init_state`

Creates the initial `state.json`. Called once during initialization.

| Field | Value |
|-------|-------|
| **Parameters** | `statePath` (string, optional), `conflictStrategy` (enum: `"conservative"` or `"optimistic"`) |
| **Returns** | `{ success: true, state: { status, conflictStrategy, currentWave, workers, failedStories, lastUpdated } }` |

#### `ralph_start_wave`

Updates state.json for a new wave. Replaces `workers` array, increments `currentWave`.

| Field | Value |
|-------|-------|
| **Parameters** | `statePath` (string, optional), `workers` (array of `{ storyId, storyTitle, retryCount }`) |
| **Returns** | `{ success: true, currentWave, workerCount, lastUpdated }` |

#### `ralph_complete_worker`

Marks a single worker as completed or failed in state.json.

| Field | Value |
|-------|-------|
| **Parameters** | `statePath` (string, optional), `storyId` (string), `status` (enum: `"completed"` or `"failed"`), `reason` (string, optional) |
| **Returns** | `{ success: true, storyId, status, lastUpdated }` |

#### `ralph_complete_run`

Marks the entire run as completed.

| Field | Value |
|-------|-------|
| **Parameters** | `statePath` (string, optional) |
| **Returns** | `{ success: true, state: <full state object> }` |

#### `ralph_get_state`

Reads current state.json.

| Field | Value |
|-------|-------|
| **Parameters** | `statePath` (string, optional) |
| **Returns** | Full state.json object |

---

### 3.4 Progress Log Tools

#### `ralph_append_progress`

Appends a completed-story entry to `progress.txt`.

| Field | Value |
|-------|-------|
| **Parameters** | `progressPath` (string, optional), `storyId` (string), `storyTitle` (string), `summary` (string), `filesChanged` (string[]), `learnings` (string) |
| **Returns** | `{ success: true, storyId }` |

#### `ralph_get_codebase_patterns`

Extracts `## Codebase Patterns` section from progress.txt.

| Field | Value |
|-------|-------|
| **Parameters** | `progressPath` (string, optional) |
| **Returns** | `{ patterns: string }` (or `"None yet"`) |

---

### 3.5 Validation Tool

#### `ralph_validate_prd`

Validates a prd.json file against the full schema. Read-only.

| Field | Value |
|-------|-------|
| **Parameters** | `prdPath` (string, optional) |
| **Returns** | `{ valid: true }` or `{ valid: false, errors: string[] }` |

---

## 4. Tool Summary Table

| Tool | Reads | Writes | Replaces |
|------|-------|--------|----------|
| `ralph_get_prd` | prd.json | — | `Read` of prd.json |
| `ralph_get_ready_stories` | prd.json | — | `Read` + retry-count parsing + dependency filtering |
| `ralph_get_project_info` | prd.json | — | `Read` (partial) |
| `ralph_mark_story_passed` | prd.json | prd.json | `Edit` passes + hook validation |
| `ralph_append_story_failure` | prd.json | prd.json | `Edit` notes + hook validation |
| `ralph_add_remediation_story` | prd.json | prd.json | `Edit` add story + hook validation |
| `ralph_update_story_notes` | prd.json | prd.json | `Edit` notes + hook validation |
| `ralph_init_state` | — | state.json | `Write` initial state |
| `ralph_start_wave` | state.json | state.json | `Write`/`Edit` wave workers |
| `ralph_complete_worker` | state.json | state.json | `Edit` worker status |
| `ralph_complete_run` | state.json | state.json | `Write` final state |
| `ralph_get_state` | state.json | — | `Read` of state.json |
| `ralph_append_progress` | — | progress.txt | `Write`/`Edit` append |
| `ralph_get_codebase_patterns` | progress.txt | — | `Read` + section extraction |
| `ralph_validate_prd` | prd.json | — | `validate-prd-write.sh` hook |

**Total: 15 tools** (8 read-only, 7 write)

---

## 5. Integration with Plugin

### 5.1 MCP Configuration File

File: `.mcp.json` (at plugin root)

```json
{
  "ralph-state": {
    "command": "node",
    "args": ["${CLAUDE_PLUGIN_ROOT}/dist/ralph-state-server.js"],
    "env": {}
  }
}
```

The server resolves file paths relative to the current working directory (the user's project).

### 5.2 Hook Deprecation

- **Phase 1:** Keep hooks active. Dispatcher uses MCP tools, but `ralph:convert` still uses `Write` for initial prd.json creation. Hook validates those writes.
- **Phase 2:** Remove hooks entirely once all writes go through MCP.

---

## 6. Server Internal Architecture

### 6.1 File Layout

```
mcp-server/
├── src/
│   ├── index.ts              # Entry point: create server, register tools, connect transport
│   ├── tools/
│   │   ├── prd-read.ts       # ralph_get_prd, ralph_get_ready_stories, ralph_get_project_info
│   │   ├── prd-write.ts      # ralph_mark_story_passed, ralph_append_story_failure,
│   │   │                     #   ralph_add_remediation_story, ralph_update_story_notes
│   │   ├── state.ts          # ralph_init_state, ralph_start_wave, ralph_complete_worker,
│   │   │                     #   ralph_complete_run, ralph_get_state
│   │   ├── progress.ts       # ralph_append_progress, ralph_get_codebase_patterns
│   │   └── validate.ts       # ralph_validate_prd
│   ├── lib/
│   │   ├── file-lock.ts      # mkdir-based file locking wrapper
│   │   ├── atomic-write.ts   # Write-to-tmp + rename pattern
│   │   ├── prd-schema.ts     # Zod schema for prd.json
│   │   ├── state-schema.ts   # Zod schema for state.json
│   │   └── timestamp.ts      # Local timestamp helper
│   └── types.ts              # Shared TypeScript interfaces
├── tsconfig.json
├── package.json              # Dev dependencies only
└── build.sh                  # esbuild bundle script
```

### 6.2 Key Implementation Patterns

**Validation (Zod schema):**
```typescript
import { z } from "zod";

const SharedFileEntry = z.union([
  z.string(),
  z.object({
    file: z.string(),
    conflictType: z.enum(["append-only", "structural-modify"]),
    reason: z.string(),
  }),
]);

const UserStory = z.object({
  id: z.string(),
  title: z.string(),
  description: z.string(),
  acceptanceCriteria: z.array(z.string()),
  dependsOn: z.array(z.string()),
  sharedFiles: z.array(SharedFileEntry),
  priority: z.number(),
  passes: z.boolean(),
  notes: z.string(),
  isRemediation: z.boolean().optional(),
  remediationDepth: z.number().max(2).optional(),
});

const PrdSchema = z.object({
  project: z.string().min(1),
  branchName: z.string().min(1),
  baseBranch: z.string(),
  sourcePrd: z.string(),
  description: z.string(),
  conflictStrategy: z.enum(["conservative", "optimistic"]).optional(),
  userStories: z.array(UserStory).min(1),
});
```

Plus a refinement for `dependsOn` referential integrity.

**Atomic writes:**
```typescript
async function atomicWriteJson(filePath: string, data: unknown): Promise<void> {
  const tmp = filePath + ".tmp." + process.pid;
  await writeFile(tmp, JSON.stringify(data, null, 2) + "\n", "utf-8");
  await rename(tmp, filePath);
}
```

**Local timestamp:**
```typescript
function localTimestamp(): string {
  const now = new Date();
  const pad = (n: number) => String(n).padStart(2, "0");
  const offset = -now.getTimezoneOffset();
  const sign = offset >= 0 ? "+" : "-";
  const abs = Math.abs(offset);
  return `${now.getFullYear()}-${pad(now.getMonth()+1)}-${pad(now.getDate())}` +
    `T${pad(now.getHours())}:${pad(now.getMinutes())}:${pad(now.getSeconds())}` +
    `${sign}${pad(Math.floor(abs/60))}${pad(abs%60)}`;
}
```

---

## 7. Build/Bundle Strategy

**Goal:** Single `dist/ralph-state-server.js` — runs with `node` (v18+), no runtime dependencies.

```json
{
  "name": "ralph-state-server",
  "version": "0.4.0",
  "private": true,
  "type": "module",
  "scripts": {
    "build": "esbuild src/index.ts --bundle --platform=node --target=node18 --format=esm --outfile=dist/ralph-state-server.js",
    "typecheck": "tsc --noEmit"
  },
  "devDependencies": {
    "@modelcontextprotocol/sdk": "^1.12.0",
    "zod": "^3.24.0",
    "esbuild": "^0.25.0",
    "typescript": "^5.8.0",
    "@types/node": "^22.0.0"
  }
}
```

- `npm install` only during development
- `npm run build` produces the single bundled file
- `dist/ralph-state-server.js` is **committed to the repo** (distributable artifact)
- Users never run `npm install`

---

## 8. Migration Path

### Phase 1: Add MCP Server (Non-Breaking)

1. Create `mcp-server/` with source code
2. Build and commit `dist/ralph-state-server.js`
3. Create `.mcp.json` at plugin root
4. Keep all existing hooks and SKILL.md unchanged
5. Release as v0.4.0

### Phase 2: Update Dispatcher SKILL.md

| SKILL.md Section | Current | New |
|------------------|---------|-----|
| 1.1 Read prd.json | `Read .ralph-in-claude/prd.json` | `ralph_get_prd` |
| 1.2 Read patterns | `Read progress.txt` + parse | `ralph_get_codebase_patterns` |
| 1.7 Init state | `Write state.json` | `ralph_init_state` |
| 3.1 Find ready | `Read prd.json` + parse + filter | `ralph_get_ready_stories` |
| 3.4 Wave start | `Write state.json` | `ralph_start_wave` |
| 3.5 Mark passed | `Edit prd.json` | `ralph_mark_story_passed` |
| 3.5 Append progress | `Edit progress.txt` | `ralph_append_progress` |
| 3.5 Failure note | `Edit prd.json` | `ralph_append_story_failure` |
| 3.5 Worker done | `Edit state.json` | `ralph_complete_worker` |
| 4.1 Complete run | `Write state.json` | `ralph_complete_run` |

### Phase 3: Remove Hooks

Remove `validate-prd-write.sh` hook. Keep hook for `ralph:convert` only (one-time write, overhead acceptable).

---

## 9. Token Savings Estimate (6-story PRD, 2 waves)

| Operation | Current (est.) | With MCP (est.) | Savings |
|-----------|---------------|-----------------|---------|
| Read prd.json (6x) | ~4800 | 0 | 4800 |
| Edit prd.json passes (6x) | ~3600 | ~480 | 3120 |
| Edit prd.json notes (2x) | ~1000 | ~200 | 800 |
| Write state.json (4x) | ~1600 | ~320 | 1280 |
| Edit state.json (6x) | ~2400 | ~480 | 1920 |
| Write/Edit progress.txt (6x) | ~1800 | ~600 | 1200 |
| Hook validation overhead | ~1200 | 0 | 1200 |
| **Total** | **~16,400** | **~2,080** | **~14,320 (87%)** |

---

## 10. Error Handling

Consistent format across all tools:

```typescript
// Success
{ content: [{ type: "text", text: JSON.stringify({ success: true, ...data }) }] }

// Error
{ content: [{ type: "text", text: JSON.stringify({ success: false, error: message }) }], isError: true }
```

Error categories: `FILE_NOT_FOUND`, `INVALID_JSON`, `VALIDATION_ERROR`, `STORY_NOT_FOUND`, `WORKER_NOT_FOUND`, `REMEDIATION_DEPTH_EXCEEDED`, `WRITE_FAILED`

---

## 11. Implementation Sequencing

| Step | Description |
|------|-------------|
| 1 | Scaffold `mcp-server/` directory, `package.json`, `tsconfig.json` |
| 2 | Implement `src/lib/` (prd-schema, state-schema, atomic-write, file-lock, timestamp) |
| 3 | Implement `src/types.ts` (TypeScript interfaces) |
| 4 | Implement `src/tools/validate.ts` — foundation for all write tools |
| 5 | Implement `src/tools/prd-read.ts` (3 read tools) |
| 6 | Implement `src/tools/prd-write.ts` (4 write tools) |
| 7 | Implement `src/tools/state.ts` (5 state tools) |
| 8 | Implement `src/tools/progress.ts` (2 progress tools) |
| 9 | Implement `src/index.ts` (entry point, tool registration) |
| 10 | Build with esbuild, test manually |
| 11 | Create `.mcp.json` at plugin root |
| 12 | Update `skills/run/SKILL.md` to use MCP tools |
| 13 | End-to-end test with a real PRD |
