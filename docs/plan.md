# Ralph Native Plugin: Design Document

> Native Plugin 設計文件。Phase 1-4 已完成。Phase 5a（Worktree Isolation）和 Phase 5b（Streaming Execution）為下一階段計畫。

---

## 1. Background

### 1.1 Bash Loop Architecture (ralph.sh)

Ralph 的 Bash Loop 模式是一個 **bash-driven sequential agent loop**：

```
ralph.sh (orchestrator)
  └─ for loop (max N iterations)
       └─ claude -p prompt.md
            └─ 讀 prd.json → 找最高 priority 且 passes: false 的 story
            └─ 實作 → typecheck → commit → 設 passes: true
            └─ 寫 progress.txt
       └─ 檢查 <promise>COMPLETE</promise> → 結束或繼續
```

本質是 **ticket-based handoff** 模式：每個 iteration spawn 全新 Claude instance，透過 prd.json + progress.txt + git commits 傳遞狀態。

### 1.2 Limitations

1. **嚴格串行** — 獨立 stories 也無法平行
2. **外部 orchestrator** — 無法利用 Claude Code 內建的 agent 協調能力
3. **無硬性驗證** — quality checks 靠 prompt 指示，agent 可忽略
4. **依賴管理粗糙** — 只有 priority 線性排序，沒有 DAG
5. **重複開銷** — 每次 fresh instance 要重新讀 codebase

---

## 2. Native Plugin Architecture (Phase 1-4, Completed)

### 2.1 核心想法

將 bash loop 替換為 Claude Code 內建的 **Task system** + **Hooks**：

- **Task system** → orchestration + 平行執行
- **Hooks** → 硬性驗證（取代 prompt 中的軟指示）
- **prd.json** → 保留為 ticket source，新增 `dependsOn` 支援 DAG

### 2.2 Architecture Overview (Current)

```
User 啟動 /ralph:run
  └─ 主 Claude session（dispatcher）
       ├─ 讀 .ralph-in-claude/prd.json，建構依賴 DAG
       ├─ Wave 1：平行 spawn 無依賴的 stories（最多 3 個 subagent）
       ├─ 驗證：檢查檔案、typecheck、dispatcher 逐一 commit
       ├─ 更新 prd.json passes，追加 progress.txt
       ├─ Wave 2：spawn 新解除封鎖的 stories
       └─ 重複直到全部完成
```

### 2.3 Bash Loop vs Native Plugin

| 維度 | Bash Loop (ralph.sh) | Native Plugin (/ralph:run) |
|------|---------------|-----------------|
| Orchestrator | Bash loop（外部） | 主 Claude session（內部） |
| 執行模式 | 嚴格串行 | 依賴圖平行 |
| Agent 隔離 | 每次 fresh instance | 每個 Task 是獨立 subagent |
| 依賴管理 | priority 線性排序 | `dependsOn` DAG + 拓撲排序 |
| 驗證機制 | Prompt 文字指示 | Plugin hooks 驗證 prd.json |
| 狀態追蹤 | prd.json `passes` | prd.json + state.json 生命週期 |
| 知識傳遞 | progress.txt | progress.txt + 主 session context |
| 錯誤恢復 | 下次 iteration 盲目重試 | 即時介入、重新分配 |

### 2.4 Current Limitations (Phase 1-4)

1. **Shared working tree** — 平行 subagent 共用同一個工作目錄，file race condition 風險高
2. **Max 3 agents 硬限制** — 因為 race condition，超過 3 個需要使用者確認
3. **File overlap check 脆弱** — 靠 story notes 裡的檔案路徑做 overlap 判斷，不可靠
4. **Dispatcher 集中 commit** — worker 不能自己 commit，dispatcher 逐一 stage/commit 是瓶頸
5. **失敗回滾複雜** — 用 `git checkout --` 和 `rm` 手動清理，worker 沒報告檔案清單時更危險
6. **Wave 等待浪費** — 一波中有 agent 先完成，被解鎖的 story 仍需等整波結束才能開始

---

## 3. Key Design Decisions (Phase 1-4)

1. **Branch 策略：** 所有 subagent 在同一個 branch 上工作，不使用 sub-branch。Dispatcher 確保平行 stories 不修改重疊檔案。
2. **最大平行度：** 預設 3 個 subagent，可透過參數調整。
3. **失敗重試：** 每個 story 最多 3 次重試，失敗 context 傳遞給下次嘗試。3 次仍失敗則標記失敗，交回 dispatcher 處理。
4. **Git 責任歸屬：** Subagent 不碰 git，由 dispatcher 在 wave 結束後逐一驗證並 commit。
5. **ralph.sh 保留：** 作為 fallback，適合 CI/headless 場景。

---

## 4. Hooks Design

### prd.json Write Validation（PreToolUse）

攔截 `Write` 和 `Edit` 對 prd.json 的修改，驗證：
- 合法 JSON
- 必要欄位存在（project, userStories, id, dependsOn 等）
- `dependsOn` 參照完整性（引用的 story ID 必須存在）

> 實作：`hooks/hooks.json` + `scripts/validate-prd-write.sh`

### ensure-ralph-dir（PreToolUse）

寫入 `.ralph-in-claude/` 路徑前自動建立目錄。

> 實作：`hooks/hooks.json` + `scripts/ensure-ralph-dir.sh`

---

## 5. Phase 5a: Worktree Isolation（保留 Wave 模式）

### 5a.1 動機

Phase 1-4 的 shared working tree 是最大的技術負債：平行 worker 共用工作目錄，file race condition 風險高，限制了平行度和可靠性。Worktree isolation 是低風險、高價值的改進，可以獨立於 streaming execution 實作。

### 5a.2 Architecture Overview

```
User 啟動 /ralph:run
  └─ Dispatcher（主 session）
       ├─ 讀 prd.json，建構依賴 DAG
       ├─ Wave 1：spawn ready stories（各自在獨立 worktree，foreground）
       │    ├─ Worker 在 worktree 裡實作 + commit
       │    └─ 全部完成後，dispatcher 逐一 merge --no-ff 到 feature branch
       ├─ 更新 prd.json passes，追加 progress.txt
       ├─ Wave 2：spawn 新解除封鎖的 stories
       └─ 重複直到全部完成
```

與 Phase 1-4 的差異：worker 從 shared working tree 改為獨立 worktree，但仍用 **wave 模式**（foreground Task，等全部完成再處理）。

### 5a.3 Worktree Isolation

每個 subagent 使用 Task tool 的 `isolation: "worktree"` 參數，獲得獨立的 git worktree：

```
feature-branch (HEAD = commit X)
  ├─ worktree/US-001 (branch: ralph-worker-US-001, forked from X)
  ├─ worktree/US-003 (branch: ralph-worker-US-003, forked from X)
  └─ worktree/US-004 (branch: ralph-worker-US-004, forked from X)
```

**改變點：**

| | Phase 1-4 (Shared) | Phase 5a (Worktree) |
|---|---|---|
| Worker 工作目錄 | 共用主 working tree | 各自獨立 worktree |
| File race condition | 有風險，靠 overlap check 緩解 | 不存在 |
| Worker commit | 禁止，dispatcher 集中做 | Worker 在自己 worktree commit |
| 失敗回滾 | `git checkout --` + `rm` | 丟棄 worktree（自動清理） |
| 最大平行度 | 預設 3（race condition 風險） | 可安全提高（仍建議確認） |

### 5a.4 Merge 策略：`merge --no-ff`

使用 `git merge --no-ff` 取代 cherry-pick，作為 worktree 合併到 feature branch 的機制。

**為什麼 `merge --no-ff` 優於 cherry-pick：**

1. **3-way merge 語義** — merge 使用共同祖先做 3-way diff，衝突解決比 cherry-pick 的 patch apply 更準確
2. **多 commit worker 友好** — worker 如果做了多個 commits，merge 一次處理整個 branch；cherry-pick 需要逐一或用 range 語法
3. **History 更清楚** — merge commit 明確標記每個 story 的整合點，`--no-ff` 保留 branch 結構
4. **無 duplicate commit 問題** — cherry-pick 產生新 hash，如果 branch 沒被刪除會造成重複；merge 不會

**Worker branch 是 ephemeral：** 合併後即刪除，不會殘留。

**合併衝突處理（Append-Only Auto-Resolve）：**
1. `git -c merge.conflictStyle=diff3 merge --no-ff <worker-branch>` 失敗
2. 檢查所有衝突 hunk 是否為 append-only（diff3 base section 為空）
3. 如果全部為 append-only：移除衝突標記、`git add` + `git commit --no-edit`，視為成功
4. 如果有任何 hunk 的 base 非空（真正的修改衝突）：`git merge --abort` 還原，標記 story 為 failed
5. 下次重試時 worker 從新的 HEAD fork（包含已合併的 stories），衝突自然解決

**同一波的 merge 順序不影響衝突機率：** 同波的 workers 都從相同 commit X fork，無論合併順序如何，衝突的 story 組合不變。

### 5a.5 Worker Prompt 改變

Worker prompt template 需要調整以反映新的 git 責任：

**明確的 Git 指示（加入 worker prompt）：**
```
## Git Instructions
1. All your work is in an isolated worktree. You are free to use git.
2. When done, stage ALL changed files: git add -A
3. Make exactly ONE commit: git commit -m "feat: {{STORY_ID}} - {{STORY_TITLE}}"
4. Report the full commit hash in your result.
5. Do NOT create branches, merge, rebase, or push.
```

**Worker 回報格式：**
```
## Result
- **Status:** PASS | FAIL
- **Commit:** <full commit hash>
- **Files Changed:** <list>
- **Summary:** <what was done>
- **Learnings:** <patterns discovered>
```

### 5a.6 File Overlap：從 block 降級為 soft warning

Worktree 消除了 runtime file corruption，但 **merge 衝突仍然會發生**（兩個 worker 改了同一個檔案的同一行）。因此 file overlap check 不應完全移除，而是降級為 soft warning：

- 排程時仍掃描 story notes 中的檔案路徑
- 發現重疊時 **記錄警告**（不阻止排程）：`"Warning: US-001 and US-003 may conflict at merge time (both touch src/foo.ts). Worktree isolation prevents corruption but merge conflicts are possible."`
- 這提供有用的除錯資訊，不影響執行效率

### 5a.7 實作步驟

#### Step 1: Worker Prompt Template 更新
- 修改 `skills/run/references/subagent-prompt-template.md`
- 加入 §5a.5 的 Git Instructions 和新回報格式
- 移除「不要碰 git」的舊指示

#### Step 2: SKILL.md Dispatcher 邏輯修改
- 修改 `skills/run/SKILL.md`
- §3.4 Task spawn 加入 `isolation: "worktree"`（保留 foreground）
- §3.5 驗證改為 merge --no-ff（取代 dispatcher 手動 stage/commit）
- §3.2 file overlap check 改為 soft warning
- §0 移除 `max-agents > 3` 的 race condition 確認（改為一般性確認）
- §1, §4, §7 中引用 `currentWave` 和 `workers` 的部分保持不變（wave 模式不變）

#### Step 3: Concurrency Rules 更新
- 新增 git merge 相關規則
- file overlap check 降級為 soft warning
- 保留 prd.json / progress.txt / state.json 寫入集中化

#### Step 4: 文件更新
- 更新 `README.md` 和 `README.zh-TW.md` 中相關的 concurrency 描述
- 更新 `CLAUDE.md` 中的 Concurrency Rules 段落

### 5a.8 前置驗證（PoC）

在實作前，執行最小化概念驗證：

1. **Worktree isolation test** — 建立一個 Task with `isolation: "worktree"`，確認 worker 能在 worktree 中 commit
2. **Merge test** — 從 worktree branch `merge --no-ff` 回 feature branch，確認行為正確
3. **Worktree metadata test** — 確認 Task 完成後能取得 branch name 和 worktree path
4. **Cleanup test** — 確認 worktree 在完成/失敗後的清理行為

---

## 6. Phase 5b: Streaming Execution（取代 Wave 模式）

> **前置條件：** Phase 5a 完成 + `TaskOutput` polling 穩定性驗證通過。
>
> **已知風險：** `TaskOutput(block=false)` 有多個 open issues（[#17540](https://github.com/anthropics/claude-code/issues/17540) session freeze、[#20236](https://github.com/anthropics/claude-code/issues/20236) hang after completion）。Phase 5b 的 event loop 完全依賴此 API。如果這些 bug 未修復，需要考慮 file-based signaling 作為 fallback。

### 6.1 動機

Phase 5a 解決了隔離問題，但 wave 模式仍浪費排程效率：

```
範例: US-1  US-2[blocked by US-1]  US-3  US-4

Wave 模式 (Phase 5a):
  t=0   spawn US-1, US-3, US-4
  t=5   US-1 完成 ← US-2 已就緒但必須等
  t=12  US-3 完成
  t=15  US-4 完成 ← 全波完成，merge all
  t=16  spawn US-2
  t=25  US-2 完成
  總時間: ~25

Streaming 模式 (Phase 5b):
  t=0   spawn US-1, US-3, US-4
  t=5   US-1 完成 → merge → 立即 spawn US-2
  t=12  US-3 完成 → merge
  t=15  US-4, US-2 完成 → merge
  總時間: ~15
```

### 6.2 Architecture Overview

```
User 啟動 /ralph:run
  └─ Dispatcher（主 session）
       ├─ 讀 prd.json，建構依賴 DAG
       ├─ Startup reconciliation（清理上次殘留的 orphan worktrees）
       ├─ Spawn 所有 ready stories 為 background tasks（各自在獨立 worktree）
       ├─ Event loop:
       │    ├─ Poll 所有 active workers（TaskOutput block=false）
       │    ├─ Worker 完成 → merge --no-ff 到 feature branch
       │    ├─ 重新計算 ready stories → 立即 spawn 新解鎖的
       │    ├─ 無完成的 worker → sleep + backoff
       │    └─ 繼續直到所有 story 完成或 blocked
       └─ 完成報告
```

### 6.3 Event Loop（詳細設計）

```
activeWorkers = {}  // storyId → { taskId, outputFile, startedAt }
pollInterval = 10   // seconds, initial
MAX_POLL_INTERVAL = 30
MAX_WORKER_RUNTIME = 600  // seconds, per worker timeout

loop:
  1. 重新計算 ready stories（passes=false, 依賴已滿足, retry < 3, 未在 activeWorkers 中）
  2. 對新 ready 的 stories spawn background Task (worktree isolation)
     → 加入 activeWorkers（記錄 startedAt）
  3. Poll 所有 activeWorkers: TaskOutput(task_id, block=false)
     - 處理所有可能的回傳狀態：completed / failed / running / not_found / error
     - not_found 或 error → 視為 worker 失敗
  4. 對每個完成的 worker:
     a. 解析結果（PASS/FAIL + commit info）
     b. PASS → git merge --no-ff <worker-branch>
              → 更新 prd.json passes=true（atomic write: temp + rename）
              → TaskUpdate status=completed
              → 從 activeWorkers 移除
              → 重設 pollInterval = 10
     c. FAIL → 更新 prd.json notes（追加 "Attempt N failed: ..."，原子寫入）
              → TaskUpdate status=pending
              → 從 activeWorkers 移除
              → 對此 story 套用 retry backoff（exponential, 加 jitter）
     d. Merge conflict → 視為 FAIL，reason = "merge conflict with <conflicting-story>"
              → git merge --abort
  5. Watchdog: 檢查所有 activeWorkers 的 startedAt
     - 超過 MAX_WORKER_RUNTIME → 視為 stuck，標記 FAIL，reason = "worker timeout"
  6. Termination check（基於 step 1 重新計算的結果，不用舊值）:
     a. 所有 stories passes=true → 結束（成功）
     b. activeWorkers 非空 或 有 ready stories → 繼續
     c. activeWorkers 為空 且 無 ready stories → 結束（全部 blocked 或 exhausted）
  7. 如果 step 4 無任何完成的 worker:
     → sleep(pollInterval)（via Bash: sleep N）
     → pollInterval = min(pollInterval * 1.5, MAX_POLL_INTERVAL)
  8. 回到 step 1
```

**關鍵改進：**
- **Step 1 每次迭代重新計算 ready**，確保 step 4 的完成結果立即影響排程
- **Step 3 處理所有 poll 狀態**，不只是 completed，防止 worker 卡在 activeWorkers
- **Step 5 watchdog**，防止 stuck worker 導致無限等待
- **Step 7 exponential backoff**，避免無結果時 tight spin 燒 context token
- **Step 6 termination 用 step 1 的新結果**，避免錯誤提前退出

### 6.4 Fallback: File-based Completion Signaling

如果 `TaskOutput` polling 不穩定，使用 file-based signaling 作為替代：

- Worker 完成時寫入 `.ralph-in-claude/signals/<story-id>.done`（包含 status + commit hash）
- Dispatcher 用 `ls .ralph-in-claude/signals/` polling（via Bash）
- 粗糙但可靠，不依賴 TaskOutput API

### 6.5 State 管理更新

**state.json 結構調整：**
```json
{
  "stateSchemaVersion": 2,
  "status": "running",
  "mode": "streaming",
  "activeWorkers": [
    {
      "storyId": "US-001",
      "storyTitle": "...",
      "status": "running",
      "taskId": "bg_xxx",
      "worktreeBranch": "ralph-worker-US-001",
      "worktreePath": ".claude/worktrees/ralph-worker-US-001",
      "startedAt": "...",
      "completedAt": null,
      "retryCount": 0
    }
  ],
  "completedStories": ["US-003", "US-004"],
  "failedStories": {},
  "lastUpdated": "..."
}
```

**與 Phase 5a 的差異：**
- 新增 `stateSchemaVersion` 欄位支援 schema 演進
- `currentWave` → 移除（streaming 沒有固定 wave）
- 新增 `worktreePath` 用於 crash recovery 清理
- `mode` 欄位區分 `"wave"` (5a) vs `"streaming"` (5b)

### 6.6 Crash Recovery

Dispatcher 啟動時執行 reconciliation：

1. **掃描 orphan worktrees** — `git worktree list`，比對 state.json
   - state.json 有記錄但 worktree 不存在 → 重設 story 為 pending
   - worktree 存在但 state.json 無記錄 → `git worktree remove`
2. **檢查 merge 殘留** — 如果 `MERGE_HEAD` 存在 → `git merge --abort`
3. **重設 zombie stories** — state.json 中 `status: "running"` 的 worker → 重設為 pending

### 6.7 實作步驟

#### Step 1: 驗證 TaskOutput 穩定性
- 建立 PoC：spawn 3 個 background worktree tasks，用 `TaskOutput(block=false)` polling
- 如果不穩定 → 實作 file-based signaling fallback (§6.4)
- **此步驟為 Phase 5b 的 gate，不通過則暫停 5b**

#### Step 2: SKILL.md Event Loop 重寫
- 替換 §3 Execution Loop：wave loop → event loop (§6.3)
- 加入 polling backoff、watchdog、crash recovery
- §0 的 `max-agents` 參數改為 max concurrent active workers

#### Step 3: State Schema 升級
- state.json 加入 `stateSchemaVersion`, `worktreePath`, `mode`
- 加入 startup reconciliation 邏輯 (§6.6)

#### Step 4: 文件更新
- 更新 `README.md` 和 `README.zh-TW.md`
- 更新 `CLAUDE.md`
- 如果有 WebGUI Kanban → 更新 state.json 消費端相容

---

## 7. Concurrency Safety

### Phase 1-4 Rules（保留）

1. **prd.json 寫入集中化** — subagent 不直接修改 prd.json，由 dispatcher 統一更新
2. **progress.txt 寫入集中化** — 只有 dispatcher 追加
3. **state.json 寫入集中化** — 只有 dispatcher 寫入
4. **Task 狀態管理集中化** — subagent 不呼叫 TaskCreate/TaskUpdate/TaskList

### Phase 5a Rules（Worktree Isolation）

5. **Git commit 分離** — worker 在自己的 worktree commit；dispatcher 用 `merge --no-ff` 合併到 feature branch
6. **Merge 序列化** — dispatcher 逐一 merge，不平行合併
7. **Conflict auto-resolve** — merge 衝突時先檢查是否全部為 append-only（diff3 base section 為空）。如果是，自動移除衝突標記並完成 merge。如果有非空 base（真正修改衝突），`git merge --abort` 還原，重試時 worker 從新 HEAD fork，自然解決衝突
8. **Worktree 生命週期** — 成功的 worktree 在 merge 後清理；失敗的 worktree 保留一段時間供 debug（不立刻丟棄）
9. **sharedFiles-aware scheduling** — 排程時根據 story 的 `sharedFiles` 欄位偵測重疊，共用檔案的 stories 不在同一 wave 排程。搭配 append-only auto-resolve，即使遺漏也能自動處理
10. **Worker 單一 commit** — worker prompt 明確要求 exactly one commit，簡化 merge 處理
11. **prd.json 原子寫入** — dispatcher 寫入 prd.json 時使用 temp file + rename，避免 worker 讀到 partial JSON

### Phase 5b Rules（Streaming Execution，在 5a 基礎上新增）

12. **Single dispatcher lock** — 同一 feature branch 同時只能有一個 dispatcher 在跑，防止雙重排程
13. **Polling backoff** — 無完成 worker 時 exponential backoff（10s → 30s），避免 tight spin 燒 context
14. **Worker timeout watchdog** — 每個 worker 有 max runtime（預設 600s），超時視為 stuck 並標記 FAIL
15. **Crash recovery reconciliation** — dispatcher 啟動時掃描 orphan worktrees + merge 殘留 + zombie stories，清理並重設
16. **Max worktree cap** — 同時存在的 worktrees 不超過 max-agents 數量，防止磁碟空間耗盡
17. **Retry backoff** — story 失敗後不立刻重試，套用 exponential backoff + jitter，防止 fail-respawn 循環
