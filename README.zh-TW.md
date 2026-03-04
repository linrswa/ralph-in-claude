# 🤖 Ralph for Claude Code

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Claude Code Plugin](https://img.shields.io/badge/Claude_Code-Plugin-blue.svg)](https://claude.com/claude-code)

[English](README.md)

自主 AI 代理系統，從 PRD 迭代實作功能。靈感來自 [Geoffrey Huntley 的 Ralph 模式](https://ghuntley.com/ralph/)。

以 **Claude Code 外掛** 形式封裝，提供三個命名空間技能：`ralph:prd`、`ralph:convert`、`ralph:run`。

## 📰 近期更新

**v0.4.4** — 新增「禁止覆蓋模型」約束——調度器不得在啟動子代理時設定 `model` 參數，由各 agent 定義檔自行控制模型。釐清 phase/wave 術語：PRD 中 story 的階段分組用「phase」，「wave」保留給 `ralph:run` 的平行執行排程。

**v0.4.1 ~ v0.4.3** — 精簡 skills、agents 與 prompt templates（約 25% 減量）；修復 8 項遺失的規格；新增波次審查 Phase C（bridge work）——為下一波平行 worker 準備程式碼庫；修復調度器在單 story 與 direct mode 波次跳過 Phase C 的問題。

**v0.4.0** — 波次後 code review 系統（Sonnet wave-reviewer + Opus wave-coordinator 升級處理）；從 Task tool 的 `isolation: "worktree"` 改為調度器自行管理 worktree；移除實驗性 conflict-resolver agent（Tier 3），改由 wave-reviewer/coordinator pipeline 處理；啟動時自動清理孤立 worktree。

完整版本歷史請參閱 [CHANGELOG.md](CHANGELOG.md)。

## 💡 緣起

原版 [Ralph](https://github.com/snarktank/ralph) 是為 Amp 打造的 —— 一個自主迴圈，從 PRD 撈出 story 逐一實作，每次都用全新的 context 來避免上下文耗盡。這個專案最初是該模式的 Claude Code 移植版（簡單的 bash 迴圈），現在正利用 Claude Code 的原生 agentic 工具（Task 系統、Skills、Hooks、外掛市集）演進為**依賴感知的平行執行**和**schema 驗證的資料完整性**。

能用，但 hook 作用域、子代理協作、錯誤恢復等方面還有粗糙的地方。持續迭代中。

## 🏛️ 架構

### 現行架構：Native Plugin（`/ralph:run`）

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
│  │   5. Wave Review（Phase A：解析延遲衝突，                           │  │
│  │                   Phase B：一致性檢查，                             │  │
│  │                   Phase C：為下一波準備 bridge work）               │  │
│  └─────────────────────────────────────────────────────────────────────┘  │
│                                    │                                      │
│                                    ▼                                      │
│   Repeat waves until: all passes=true  or  max waves exhausted            │
└───────────────────────────────────────────────────────────────────────────┘
```

詳見 [docs/plan.md](docs/plan.md) 完整的設計文件。

### 原版架構：Bash Loop（`ralph.sh`）

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

原版做法：每次迭代都是全新的 Claude 實例，沒有共享記憶。狀態透過 `prd.json`、`progress.txt` 和 git 歷史持久化。仍可作為 CI/無頭環境的備用方案。

## 📦 安裝

### 前置需求

- [Claude Code CLI](https://claude.ai/code) 已安裝且通過驗證
- 已安裝 `jq`（`brew install jq` / `apt install jq`）
- 一個 git 儲存庫作為你的專案

### 以外掛形式安裝

1. 註冊本地市集（若尚未完成）：

```bash
# 在 Claude Code 中執行：
/plugin marketplace add /path/to/your/marketplace
```

2. 安裝 ralph 外掛：

```bash
/plugin install ralph@local
```

3. 在 `~/.claude/settings.json` 中啟用：

```json
{
  "enabledPlugins": {
    "ralph@local": true
  }
}
```

這會在所有專案中啟用 `/ralph:prd`、`/ralph:convert` 和 `/ralph:run` 指令。

## 🚀 工作流程

**1. 建立 PRD**

```
/ralph:prd [你的功能描述]
```

回答釐清問題。輸出儲存至 `.ralph-in-claude/tasks/prd-[feature-name].md`。

**2. 轉換為 Ralph 格式**

```
/ralph:convert .ralph-in-claude/tasks/prd-[feature-name].md
```

建立 `.ralph-in-claude/prd.json`，包含結構化的 user story 供自主執行。

**3. 執行 Ralph**

**Native Plugin（推薦）— 平行執行：**

```
/ralph:run                                  # 使用 .ralph-in-claude/prd.json，預設 5 個代理
/ralph:run path/to/prd.json                # 自訂 prd 路徑
/ralph:run .ralph-in-claude/prd.json 8     # 自訂路徑 + 最多 8 個平行代理
```

調度器讀取 `.ralph-in-claude/prd.json`，建立依賴 DAG，以波次方式平行啟動子代理 worker（預設每波 5 個，可透過第二個參數設定）。依波次大小使用兩種執行模式：

- **Direct mode**（單 story 波次）：worker 直接在 feature branch 上提交——不需要 worktree 或合併。
- **Worktree mode**（多 story 波次）：調度器從 feature branch HEAD 建立 git worktree，確保每波都能看到前一波已合併的變更。Worker 在各自的 worktree 中提交，調度器再透過 `git merge --no-ff` 合併。

調度器驗證結果、更新 prd.json，然後啟動下一波。

**Bash Loop（備用）— 循序執行：**

```bash
./ralph.sh [max_iterations]  # 預設：10
```

每個 story 啟動一個全新 Claude 實例，循序執行。適用於 CI/無頭環境。

兩者都會持續執行直到：
- 所有 story 的 `passes` 為 `true`，或
- 達到最大迭代/波次上限

## 🧩 核心概念

### Story 大小原則

每個 story 必須在**一次迭代**（一個 context window）內完成。如果 LLM 用光上下文，就會產出壞掉的程式碼。

**大小適當：** 新增一個資料庫欄位、建立一個 UI 元件、更新一個 server action、新增一個篩選下拉選單。

**太大（請拆分）：** 「建構整個儀表板」、「新增身份驗證」、「重構整個 API」。

**經驗法則：** 如果你無法用 2-3 句話描述這個改動，那它就太大了。

### 依賴圖

Story 透過 `dependsOn` 宣告依賴：

```json
{
  "id": "US-003",
  "dependsOn": ["US-001", "US-002"],
  "priority": 3
}
```

- `dependsOn: []` — 無依賴，可立即執行
- Story 在所有依賴的 `passes` 為 `true` 之前不會被選中
- `priority` 在相同依賴層級的 story 間決定順序

### 知識傳遞

迭代之間的知識透過以下方式持久化：
- **`.ralph-in-claude/progress.txt`**（Native Plugin）/ **`progress.txt`**（Bash Loop）— 僅追加的學習紀錄和程式碼庫模式
- **`CLAUDE.md`** — Claude Code 自動讀取的可重用模式
- **Git 歷史** — 先前迭代提交的程式碼

### 共用檔案與衝突解析

Story 可透過 `sharedFiles` 宣告多個 story 可能同時修改的共用檔案：

```json
{
  "id": "US-003",
  "sharedFiles": [
    { "file": "src/index.ts", "conflictType": "append-only", "reason": "import registration" },
    "src/config.ts"
  ]
}
```

專案層級的 `conflictStrategy` 控制調度器如何處理重疊的 story：

- **`"conservative"`**（預設）— 將所有有 `sharedFiles` 重疊的 story 延遲到不同波次
- **`"optimistic"`** — 允許 `append-only` 重疊在同一波次平行執行，搭配分層合併管線：
  1. **Tier 1：** `git merge` — 乾淨合併成功即完成
  2. **Tier 2：** Append-only 自動解析 — 自動解析標記為 `append-only` 的檔案衝突標記
  3. **Tier 3：** 延遲至波次審查 — 中止 story 合併，延遲到波次審查 Phase A 處理，由 Sonnet wave-reviewer（具備完整波次上下文）嘗試解析。若 reviewer 無法解析，升級至 Opus coordinator。若兩者都無法解析，建立補救 story。

### 品質把關

- **調度器：** 每波結束後執行型別檢查、`git merge --no-ff` 逐一合併 worker 分支、失敗 story 最多重試 3 次
- **波次審查：** 每波結束後，執行三階段審查：**Phase A** 以完整波次上下文解析延遲的合併衝突（Tier 3）——Sonnet reviewer 先行嘗試解析，無法解析時升級至 Opus coordinator；**Phase B** 檢查合併後的 diff 是否有跨 story 一致性問題（命名、import、風格），重大問題升級至 coordinator；**Phase C** 為下一波執行 bridge work（如安裝新依賴、建立 barrel file、設定共用 scaffolding），減少平行 worker 的重複工作。
- **Hooks：** 每次 prd.json 寫入時驗證 schema（JSON 完整性、必填欄位、`dependsOn` 參照檢查）

## 🏗️ 外掛結構

```
ralph-in-claude/
├── .claude-plugin/
│   └── plugin.json                     # 外掛清單
├── agents/
│   ├── ralph-worker.md                 # Worker 代理定義（隨外掛發佈）
│   ├── wave-reviewer.md                # Sonnet 代理 — 波次後一致性審查
│   └── wave-coordinator.md             # Opus 代理 — 升級議題處理
├── hooks/
│   └── hooks.json                      # 外掛層級 PreToolUse hooks（prd.json 驗證）
├── scripts/
│   ├── ensure-ralph-dir.sh             # Hook：自動建立 .ralph-in-claude/ 目錄
│   └── validate-prd-write.sh           # Hook：驗證 prd.json schema（9 項檢查）
├── skills/
│   ├── prd/
│   │   └── SKILL.md                    # ralph:prd — PRD 產生器
│   ├── convert/
│   │   └── SKILL.md                    # ralph:convert — PRD 轉 JSON 轉換器
│   └── run/
│       ├── SKILL.md                    # ralph:run — 平行調度器
│       └── references/
│           ├── subagent-prompt-template.md  # Worker 提示（動態上下文）
│           ├── wave-review-prompt-template.md       # 波次審查提示
│           └── wave-coordinator-prompt-template.md  # 波次協調提示
├── docs/
│   ├── plan.md                         # Native Plugin 設計文件
│   └── WIP.md                          # 待解決問題與待辦事項
├── CLAUDE.md                           # 專案指令（Claude Code 自動讀取）
├── ralph.sh                            # Bash Loop 備用迴圈
└── prompt.md                           # Bash Loop worker 提示
```

> **關於 hooks 的說明：** SKILL.md frontmatter 中的 hooks 對於市集安裝的外掛不會觸發
> （[#17688](https://github.com/anthropics/claude-code/issues/17688)）。目前使用外掛層級
> 的 `hooks/hooks.json` 作為替代方案。當此 bug 修復後，hooks 可移回 SKILL.md 以實現
> 技能範圍的執行。

## 🐛 除錯

```bash
# 查看 story 狀態（Native Plugin 路徑；Bash Loop 使用 prd.json）
jq '.userStories[] | {id, title, passes, dependsOn}' .ralph-in-claude/prd.json

# 查看學習紀錄
cat .ralph-in-claude/progress.txt

# 檢查 git 歷史
git log --oneline -10
```

## 🔗 參考資料

- [Geoffrey Huntley 的 Ralph 文章](https://ghuntley.com/ralph/) — 原始概念
- [原版 Amp 的 Ralph](https://github.com/snarktank/ralph) — 本專案靈感來源的 Amp 實作
- [Claude Code 文件](https://docs.anthropic.com/en/docs/claude-code)

## 📜 授權條款

MIT
