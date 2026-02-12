# Ralph v2: From Sequential Loop to Parallel Task System

## 1. Background

### 1.1 Current Architecture (ralph.sh)

Ralph 目前是一個 **bash-driven sequential agent loop**：

```
ralph.sh (orchestrator)
  └─ for loop (max N iterations)
       └─ claude --dangerously-skip-permissions -p prompt.md
            └─ 讀 prd.json → 找最高 priority 且 passes: false 的 story
            └─ 實作 → typecheck → commit → 設 passes: true
            └─ 寫 progress.txt
       └─ 檢查 <promise>COMPLETE</promise> → 結束或繼續
```

**核心檔案：**

| 檔案 | 角色 |
|------|------|
| `ralph.sh` | Bash orchestrator，spawn Claude instances |
| `prompt.md` | 每個 iteration 的指令 |
| `prd.json` | Ticket queue + 狀態追蹤 |
| `progress.txt` | Agent 間的知識傳遞 |

### 1.2 這是 Ticket-Based Handoff

Ralph 的本質是一種 **ticket-based handoff** 模式：

- **Ticket** = prd.json 裡的 user story
- **Handoff** = 每次 iteration spawn 全新 Claude instance（無 shared memory）
- **Shared state** = prd.json（狀態）+ progress.txt（知識）+ git commits（成果）
- **Queue ordering** = priority 欄位（嚴格線性）

這個設計解決了 **context exhaustion** 問題——每個 agent 只處理一個 story，不會爆 context window。

### 1.3 Current Limitations

1. **嚴格串行**：所有 stories 按 priority 順序一個一個執行，即使 US-002 和 US-003 完全獨立也不能平行
2. **外部 orchestrator**：依賴 bash loop，無法利用 Claude Code 內建的 agent 協調能力
3. **無硬性驗證**：quality checks 靠 prompt 裡的文字指示（"please run typecheck"），agent 可以忽略
4. **依賴管理粗糙**：只有 priority 數字排序，沒有明確的依賴圖（DAG）
5. **每次 fresh instance 的開銷**：每個 iteration 都要重新讀 codebase、理解 context，重複工作量大

---

## 2. Proposal: Ralph v2

### 2.1 核心想法

將 ralph.sh 的外部 bash loop 替換為 Claude Code 內建的 **Task system** + **Hooks**：

- **Task system** 取代 bash loop 做 orchestration，支援平行執行
- **Hooks** 取代 prompt 裡的軟性指示，做硬性驗證
- **prd.json** 保留為 ticket source，但新增 `dependsOn` 欄位支援 DAG

### 2.2 Architecture Overview

```
User 啟動 Ralph skill
  └─ 主 Claude session（orchestrator）
       ├─ 讀 prd.json
       ├─ 解析依賴圖（dependsOn）
       ├─ 對每個 story → TaskCreate（設定 blockedBy 關係）
       ├─ 平行 spawn 無依賴的 stories（Task tool with subagents）
       │    ├─ Task A: US-001 (schema)        ← 立即執行
       │    └─ Task B: US-005 (config)        ← 立即執行（與 A 獨立）
       ├─ Hook: PreToolUse[Write] → prd.json 寫入驗證
       ├─ Task A 完成 → TaskUpdate → 解鎖 US-002, US-003
       ├─ 平行 spawn US-002 和 US-003
       │    ├─ Task C: US-002 (backend API)   ← 平行
       │    └─ Task D: US-003 (backend logic) ← 平行
       ├─ 兩者完成 → 解鎖 US-004 (UI)
       └─ Task E: US-004 (UI) → 全部完成
```

### 2.3 vs Current Architecture

| 維度 | ralph.sh (v1) | Task system (v2) |
|------|---------------|------------------|
| Orchestrator | Bash loop（外部） | 主 Claude session（內部） |
| 執行模式 | 嚴格串行 | 依賴圖允許平行 |
| Agent 隔離 | 每次 fresh Claude instance | 每個 Task 是獨立 subagent |
| 依賴管理 | priority 線性排序 | `dependsOn` + `blockedBy` DAG |
| 驗證機制 | Prompt 裡的文字指示 | **Skill Hooks 驗證 prd.json 寫入** |
| 狀態追蹤 | prd.json `passes` 欄位 | TaskList + prd.json 雙軌 |
| 知識傳遞 | progress.txt | progress.txt + CLAUDE.md（主 session 累積 context） |
| 錯誤恢復 | 下一個 iteration 重試 | 主 session 可以即時介入、重新分配 |

---

## 3. Detailed Design

### 3.1 prd.json Schema Evolution

新增 `dependsOn` 欄位，從線性 priority 升級為 DAG：

```json
{
  "project": "MyApp",
  "branchName": "ralph/feature-name",
  "baseBranch": "main",
  "sourcePrd": "docs/prd/feature.md",
  "description": "Feature description",
  "userStories": [
    {
      "id": "US-001",
      "title": "Add schema",
      "description": "...",
      "acceptanceCriteria": ["...", "Typecheck passes"],
      "dependsOn": [],
      "priority": 1,
      "passes": false,
      "notes": ""
    },
    {
      "id": "US-002",
      "title": "Backend API",
      "description": "...",
      "acceptanceCriteria": ["...", "Typecheck passes"],
      "dependsOn": ["US-001"],
      "priority": 2,
      "passes": false,
      "notes": ""
    },
    {
      "id": "US-003",
      "title": "Backend logic",
      "description": "...",
      "acceptanceCriteria": ["...", "Typecheck passes"],
      "dependsOn": ["US-001"],
      "priority": 3,
      "passes": false,
      "notes": ""
    },
    {
      "id": "US-004",
      "title": "UI component",
      "description": "...",
      "acceptanceCriteria": ["...", "Typecheck passes", "Verify in browser"],
      "dependsOn": ["US-002", "US-003"],
      "priority": 4,
      "passes": false,
      "notes": ""
    }
  ]
}
```

**規則：**
- `dependsOn: []` = 無依賴，可立即執行
- `dependsOn: ["US-001"]` = US-001 passes: true 後才能開始
- `priority` 保留用於同層級排序（多個無依賴 story 的執行順序）
- 向下相容：`dependsOn` 不存在時，fallback 到 priority 線性排序（v1 行為）

### 3.2 Dispatcher: prd.json → TaskCreate

主 Claude session 作為 dispatcher，讀取 prd.json 並建立 Task：

```
For each story in prd.json where passes == false:
  1. TaskCreate({
       subject: "[US-001] Add schema",
       description: story.description + story.acceptanceCriteria + story.notes,
       activeForm: "Implementing US-001"
     })
  2. 根據 dependsOn 設定 TaskUpdate({ addBlockedBy: [...] })
```

**映射關係：**

| prd.json | Task system |
|----------|-------------|
| `id` | Task subject prefix |
| `description` + `acceptanceCriteria` + `notes` | Task description |
| `dependsOn` | `blockedBy` |
| `passes: false` | status: pending |
| `passes: true` | status: completed |

### 3.3 Parallel Execution

主 Claude session 識別可平行的 stories 並同時 spawn：

```
Phase 1: 找出所有 dependsOn == [] 的 stories
         → 同時用 Task tool spawn 多個 subagents

Phase 2: Phase 1 完成後，找出所有 dependsOn 已滿足的 stories
         → 同時 spawn

Phase N: 重複直到全部完成
```

每個 subagent 收到的 prompt 包含：
- 該 story 的完整資訊（從 prd.json）
- 原始 PRD（sourcePrd）
- progress.txt 的 Codebase Patterns section
- 專案的 CLAUDE.md

### 3.4 Hooks Design

#### 3.4.1 prd.json Write Validation（PreToolUse on Write）— 已實作

攔截對 prd.json 的修改，驗證：

```bash
#!/bin/bash
# .claude/hooks/validate-prd-write.sh
INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name')
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path')

# 只攔截 prd.json 的寫入
if echo "$FILE_PATH" | grep -q 'prd.json$'; then
  # 對 Write tool：驗證新內容是合法 JSON
  if [ "$TOOL" = "Write" ]; then
    NEW_CONTENT=$(echo "$INPUT" | jq -r '.tool_input.content')
    if ! echo "$NEW_CONTENT" | jq . > /dev/null 2>&1; then
      echo "BLOCKED: Invalid JSON in prd.json" >&2
      exit 2
    fi
    # 驗證必要欄位存在
    if ! echo "$NEW_CONTENT" | jq -e '.userStories | length > 0' > /dev/null 2>&1; then
      echo "BLOCKED: prd.json must have at least one userStory" >&2
      exit 2
    fi
  fi
fi
exit 0
```

#### 3.4.2 Story Completion Verification（PostToolUse）

Story 完成時自動驗證，只有全部 acceptance criteria 通過才允許設 `passes: true`：

```bash
#!/bin/bash
# .claude/hooks/verify-story-completion.sh
# PostToolUse hook - 在 prd.json 被修改後觸發
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

if echo "$FILE_PATH" | grep -q 'prd.json$'; then
  # 檢查是否有 story 從 false 變成 true
  # 如果有，跑該 story 的 acceptance criteria 驗證
  # 透過 stderr 回報結果給 Claude
  echo "prd.json updated - verify acceptance criteria manually" >&2
fi
exit 0
```

#### 3.4.3 TaskCompleted Hook

利用 Claude Code 的 `TaskCompleted` event，在 subagent 完成 story 後同步狀態：

```json
{
  "hooks": {
    "TaskCompleted": [
      {
        "hooks": [
          {
            "type": "command",
            "command": ".claude/hooks/on-task-completed.sh"
          }
        ]
      }
    ]
  }
}
```

這個 hook 可以：
- 驗證 git commit 存在且 typecheck 通過
- 提醒主 Claude 更新 prd.json 的 `passes` 狀態
- 觸發下游 blocked tasks 的檢查

### 3.5 Concurrency Safety

**問題：** 多個平行 subagent 可能同時修改同一個檔案。

**解決方案（分層）：**

1. **prd.json 寫入集中化**
   - Subagent 不直接修改 prd.json
   - Subagent 完成後回報結果給主 Claude
   - 主 Claude 統一更新 prd.json（serialized writes）

2. **Git 衝突預防**
   - 在 prd.json 的 story notes 裡標註每個 story 會修改的檔案範圍
   - Dispatcher 在排程時檢查：平行的 stories 不能有重疊的檔案修改範圍
   - 如果有衝突風險，降級為串行執行

3. **Branch 策略**
   - 每個 subagent 在同一個 ralph branch 上工作
   - 平行 stories 必須修改不同檔案（由 dispatcher 在排程時驗證）
   - 或者：每個 subagent 在 sub-branch 上工作，完成後由主 Claude merge

### 3.6 Knowledge Transfer

現有 progress.txt 機制保留，但因為主 Claude session 是持久的，知識傳遞更自然：

| 機制 | v1 | v2 |
|------|----|----|
| progress.txt | 唯一的跨 iteration 知識通道 | 保留，但重要性降低 |
| CLAUDE.md | 由 agent 自行更新 | 同上 |
| 主 Claude context | 不存在（每次 fresh） | **新增**：主 session 累積所有 subagent 回報 |
| Subagent 回報 | 不存在 | **新增**：每個 Task 完成後的 summary |

---

## 4. Implementation Requirements

### 4.1 prd.json Schema Changes

- [x] 新增 `dependsOn` 欄位（string array of story IDs）
- [x] `dependsOn` 為 required（`[]` 表示無依賴），validation hook 強制驗證
- [x] 更新 prd.json.example
- [x] 更新 ralph SKILL.md 的 converter 邏輯（PRD → prd.json 時分析依賴產生 dependsOn）

### 4.2 Dispatcher Skill

建立新的 skill 或更新現有 ralph skill，實作 dispatcher 邏輯：

- [x] 讀取 prd.json 並建構依賴圖
- [x] 偵測循環依賴並報錯（Kahn's algorithm in SKILL.md §2）
- [x] 計算可平行的 story groups（拓撲排序）
- [x] 為每個 story 建立 TaskCreate（wave-based, not TaskCreate — uses Task tool directly）
- [x] 設定正確的 blockedBy 關係（via dependsOn DAG in dispatcher logic）
- [x] 產生每個 subagent 的 prompt（subagent-prompt-template.md with placeholders）
- [x] 用 Task tool 平行 spawn 無依賴的 stories
- [x] 監聽 Task 完成，更新 prd.json，解鎖下游 tasks
- [x] 處理失敗情況（3 retries per story, failure context appended to retry prompt）

### 4.3 Hooks

- [x] `.claude/hooks/validate-prd-write.sh` — prd.json 寫入時驗證 JSON schema（skill-level hook，已實作）
- [x] `.claude/hooks/ensure-ralph-dir.sh` — 確保 ralph/ 目錄存在（skill-level hook，已實作）
- ~~`.claude/hooks/on-task-completed.sh`~~ — 不需要，dispatcher 在 wave 完成後直接驗證

### 4.4 Prompt Updates

- [x] ~~更新 prompt.md 適配 subagent 模式~~ — prompt.md 保留給 v1；v2 使用 `subagent-prompt-template.md`
- [x] Subagent 不需要自己讀 prd.json、判斷做哪個 story——由 dispatcher 指定（template 直接注入 story）
- [x] Subagent 不需要自己更新 prd.json——由主 session 統一更新（template 明確禁止）
- [x] 保留 quality check 和 commit 邏輯（template 包含 quality check + commit 指令）

### 4.5 Backward Compatibility

- [x] `dependsOn` 不存在時，行為等同 v1（按 priority 串行）— Phase 1 已處理
- [x] ralph.sh 保留作為 fallback（適合 CI/headless 場景）— 未修改
- [x] 現有 prd.json 不需修改即可在 v2 下運行 — `dependsOn` 是 required 但 `[]` 即可

---

## 5. Risks & Mitigations

### 5.1 Context Window Exhaustion（主 Session）

**風險：** 主 Claude session 作為 orchestrator，隨著協調工作和 subagent 回報，context 會逐漸累積。

**緩解：**
- Claude Code 有自動 context compaction
- 主 session 只做協調，不做實作——context 使用量遠低於實作 agent
- 極端情況可 fallback 到 ralph.sh

### 5.2 Parallel Git Conflicts

**風險：** 多個 subagent 同時修改重疊的檔案。

**緩解：**
- Dispatcher 排程時檢查檔案範圍是否重疊
- 有衝突風險的 stories 自動降級為串行
- Story notes 裡標註預期修改的檔案

### 5.3 Subagent Failure

**風險：** 一個 subagent 失敗，阻塞下游的所有 stories。

**緩解：**
- 主 session 可以即時介入，分析失敗原因
- 可以重新 spawn subagent 重試
- 可以修改策略（拆分 story、調整依賴）
- 比 ralph.sh 更靈活——v1 只能盲目重試下一個 iteration

### 5.4 Hook Compatibility

**風險：** 不同專案的 quality check 命令不同（npm vs cargo vs cmake）。

**緩解：**
- Hook scripts 讀取專案配置（package.json、Cargo.toml 等）自動偵測
- 或在 prd.json 新增 `qualityChecks` 欄位指定命令
- Fallback：hook 找不到已知的 check 命令時 pass through（不阻擋）

---

## 6. Migration Path

### Phase 1: Schema ✓
1. ~~prd.json 加 `dependsOn` 欄位~~ ✓（required，`[]` for root stories）
2. ~~更新 SKILL.md converter~~ ✓（conversion rules、checklist 皆涵蓋）
3. ~~ralph.sh 忽略 `dependsOn`~~ ✓（向下相容，未修改 ralph.sh）

### Phase 2: Hooks ✓
1. ~~實作 prd.json write validation hook~~ ✓（skill-level hook）
2. ~~實作 ensure-ralph-dir hook~~ ✓（skill-level hook）
3. ~~在現有 ralph.sh 流程中測試 hooks~~ ✓

### Phase 3: Dispatcher ✓
1. ~~建立 dispatcher skill~~ ✓（`.claude/skills/ralph-run/SKILL.md`）
2. ~~實作 prd.json → TaskCreate 映射~~ ✓（wave-based dispatch in SKILL.md）
3. ~~實作平行 spawn 邏輯~~ ✓（Task tool parallel calls, max 3 per wave）
4. ~~測試 end-to-end~~ ✓（手動驗證通過）

### Phase 4: Polish ✓
1. ~~錯誤恢復和重試邏輯~~ ✓（SKILL.md §5 — 3 retries/story, failure context propagation）
2. ~~Progress reporting 整合~~ ✓（SKILL.md §3.5 — wave 完成後更新 progress.txt + 報告用戶）
3. ~~文件更新~~ ✓（README.md + CLAUDE.md 已更新）

---

## 7. Design Decisions（已決定）

1. **Subagent branch 策略：** 所有 subagent 在**同一個 branch** 上 commit。不使用 sub-branch。Dispatcher 排程時須確保平行 stories 不修改重疊檔案。
2. **最大平行度：** 預設 **3 個** subagent 同時執行，可透過設定調整。
3. **失敗重試策略：** 單一 subagent session 內最多重試 **3 次**。3 次仍失敗則該 story 標記為失敗，交回主 session 重新 dispatch（可能拆分 story、調整策略後重試）。
4. **是否保留 ralph.sh：** 保留作為參考，v2 開發期間不刪除。
