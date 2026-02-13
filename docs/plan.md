# Ralph v2: Design Document

> v2 設計文件。所有階段已完成實作（Phase 1-4 ✓）。本文件保留作為架構參考。

---

## 1. Background

### 1.1 v1 Architecture (ralph.sh)

Ralph v1 是一個 **bash-driven sequential agent loop**：

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

## 2. v2 Architecture

### 2.1 核心想法

將 bash loop 替換為 Claude Code 內建的 **Task system** + **Hooks**：

- **Task system** → orchestration + 平行執行
- **Hooks** → 硬性驗證（取代 prompt 中的軟指示）
- **prd.json** → 保留為 ticket source，新增 `dependsOn` 支援 DAG

### 2.2 Architecture Overview

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

### 2.3 v1 vs v2

| 維度 | v1 (ralph.sh) | v2 (/ralph:run) |
|------|---------------|-----------------|
| Orchestrator | Bash loop（外部） | 主 Claude session（內部） |
| 執行模式 | 嚴格串行 | 依賴圖平行 |
| Agent 隔離 | 每次 fresh instance | 每個 Task 是獨立 subagent |
| 依賴管理 | priority 線性排序 | `dependsOn` DAG + 拓撲排序 |
| 驗證機制 | Prompt 文字指示 | Plugin hooks 驗證 prd.json |
| 狀態追蹤 | prd.json `passes` | prd.json + state.json 生命週期 |
| 知識傳遞 | progress.txt | progress.txt + 主 session context |
| 錯誤恢復 | 下次 iteration 盲目重試 | 即時介入、重新分配 |

---

## 3. Key Design Decisions

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

## 5. Concurrency Safety

1. **prd.json 寫入集中化** — subagent 不直接修改 prd.json，由 dispatcher 統一更新
2. **Git 衝突預防** — dispatcher 排程時檢查平行 stories 的檔案範圍是否重疊，有衝突風險則降級為串行
3. **單一 branch** — 所有 subagent 在同一 branch，dispatcher 負責 commit 序列化
