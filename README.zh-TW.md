# 🤖 Ralph for Claude Code

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Claude Code Plugin](https://img.shields.io/badge/Claude_Code-Plugin-blue.svg)](https://claude.com/claude-code)

[English](README.md)

自主 AI 代理系統，從 PRD 迭代實作功能。靈感來自 [Geoffrey Huntley 的 Ralph 模式](https://ghuntley.com/ralph/)。

以 **Claude Code 外掛** 形式封裝，提供三個命名空間技能：`ralph:prd`、`ralph:convert`、`ralph:run`。

## 💡 緣起

最初是看到 [原版 Ralph（for Amp）](https://github.com/snarktank/ralph)，覺得這個概念很有意思——一個自主迴圈，從 PRD 撈出 story 逐一實作，每次都用全新的 context 來避免上下文耗盡。於是想試試看能不能搬到 Claude Code 上，做了一個最簡單的 bash 迴圈版本（v0.0.1）。

後來 Claude Code 陸續推出了一波新的 agentic 工具：**Task/子代理系統**、**Skills**、**Hooks**、**外掛市集**、**Agent 定義** 等等。這讓我好奇——Ralph 的工作流程和理念，能不能跟這些現代化的工具結合，做到平行執行、schema 驗證、更精細的調度？

目前這個專案就是在探索這個方向。能用，但說實話體驗還不夠順暢——hook 作用域、子代理協作、錯誤恢復等方面都還有粗糙的地方。持續迭代加強中。

## 🔍 背景

原版 [Ralph](https://github.com/snarktank/ralph) 是為 Amp 打造的。這個專案最初是該模式的 Claude Code 移植版——一個簡單的 bash 迴圈（`ralph.sh`），依序啟動全新的 Claude 實例。

現在正在演進成更進階的東西：利用 Claude Code 的原生能力（Task 系統、Skills、Hooks）打造更聰明的調度層，實現**依賴感知的平行執行**和**schema 驗證的資料完整性**。

## 🏛️ 架構

### v1：循序 Bash 迴圈（備用方案）

```
ralph.sh
  └─ for 迴圈 (最多 N 次迭代)
       └─ claude -p prompt.md
            └─ 讀取 prd.json → 選擇最高優先級的 story
            └─ 實作 → 型別檢查 → 提交 → 設定 passes: true
            └─ 寫入 progress.txt
       └─ 檢查 <promise>COMPLETE</promise> → 結束或繼續
```

每次迭代都是全新的 Claude 實例，沒有共享記憶。狀態透過 `prd.json`、`progress.txt` 和 git 歷史持久化。

### v2：原生 Claude Code 整合（`/ralph:run`）

```
使用者呼叫 /ralph:run
  └─ 主 Claude 工作階段（調度器）
       ├─ 讀取 .ralph-in-claude/prd.json，建立依賴 DAG
       ├─ 第 1 波：啟動最多 N 個 ralph-worker 子代理（平行，預設 3 個）
       │    ├─ US-001（schema）
       │    ├─ US-002（設定）
       │    └─ US-005（獨立）
       ├─ 驗證：檢查檔案、執行型別檢查、調度器逐一提交每個 story
       ├─ 更新 prd.json passes，追加 progress.txt
       ├─ 第 2 波：啟動新解除封鎖的 story
       │    ├─ US-003（依賴 US-001）
       │    └─ US-004（依賴 US-002）
       ├─ 驗證、更新、重複
       └─ 所有 story 完成 → 回報結果
```

與 v1 的主要改進：

| | v1（ralph.sh） | v2（原生） |
|---|---|---|
| 調度方式 | 外部 bash 迴圈 | 主 Claude 工作階段 |
| 執行方式 | 嚴格循序 | 透過依賴 DAG 平行執行 |
| 品質檢查 | 軟性（提示指令） | 外掛 hook 驗證 prd.json 寫入 |
| 依賴管理 | 線性優先數字 | `dependsOn` DAG 搭配拓撲排序 |
| 錯誤恢復 | 下次迭代盲目重試 | 調度器可介入並重新分派 |

詳見 [plan.md](plan.md) 完整的 v2 設計文件。

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

回答釐清問題。輸出儲存至 `tasks/prd-[feature-name].md`。

**2. 轉換為 Ralph 格式**

```
/ralph:convert tasks/prd-[feature-name].md
```

建立 `.ralph-in-claude/prd.json`，包含結構化的 user story 供自主執行。

**3. 執行 Ralph**

**v2（推薦）— 平行執行：**

```
/ralph:run                                  # 使用 .ralph-in-claude/prd.json，預設 3 個代理
/ralph:run path/to/prd.json                # 自訂 prd 路徑
/ralph:run .ralph-in-claude/prd.json 5     # 自訂路徑 + 最多 5 個平行代理
```

調度器讀取 `.ralph-in-claude/prd.json`，建立依賴 DAG，以波次方式平行啟動子代理 worker（預設每波 3 個，可透過第二個參數設定）。如果最大代理數超過 3，調度器會提示確認檔案競爭風險。Worker 平行實作 story 並回報結果。調度器驗證結果、逐一提交每個 story 的檔案、更新 prd.json，然後啟動下一波。

**v1（備用）— 循序執行：**

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
- **`.ralph-in-claude/progress.txt`**（v2）/ **`progress.txt`**（v1）— 僅追加的學習紀錄和程式碼庫模式
- **`CLAUDE.md`** — Claude Code 自動讀取的可重用模式
- **Git 歷史** — 先前迭代提交的程式碼

### 品質把關

v2 在兩個層級強制品質：

**調度器層級**（每波結束後）：
- 驗證回報的檔案存在、執行專案型別檢查
- 調度器逐一暫存並提交每個 story 的檔案（worker 不碰 git）
- 對失敗的 story 最多重試 3 次，附帶失敗上下文

**Hook 層級**（每次 prd.json 寫入時）：
- **prd.json 驗證 hook** — 阻擋無效 JSON 或缺少欄位的寫入
- **`dependsOn` 完整性檢查** — 確保所有引用的 story ID 存在
- **`ensure-ralph-dir` hook** — 寫入前自動建立 `.ralph-in-claude/` 目錄

## 🏗️ 外掛結構

```
ralph-in-claude/
├── .claude-plugin/
│   └── plugin.json                     # 外掛清單
├── agents/
│   └── ralph-worker.md                 # Worker 代理定義（隨外掛發佈）
├── hooks/
│   └── hooks.json                      # 外掛層級 PreToolUse hooks（prd.json 驗證）
├── scripts/
│   ├── ensure-ralph-dir.sh             # Hook：自動建立 .ralph-in-claude/ 目錄
│   └── validate-prd-write.sh           # Hook：驗證 prd.json schema（6 項檢查）
├── skills/
│   ├── prd/
│   │   └── SKILL.md                    # ralph:prd — PRD 產生器
│   ├── convert/
│   │   └── SKILL.md                    # ralph:convert — PRD 轉 JSON 轉換器
│   └── run/
│       ├── SKILL.md                    # ralph:run — 平行調度器
│       └── references/
│           └── subagent-prompt-template.md  # Worker 提示（動態上下文）
├── CLAUDE.md                           # 專案指令（Claude Code 自動讀取）
├── ralph.sh                            # v1 備用迴圈
├── prompt.md                           # v1 worker 提示
└── plan.md                             # v2 設計文件
```

> **關於 hooks 的說明：** SKILL.md frontmatter 中的 hooks 對於市集安裝的外掛不會觸發
> （[#17688](https://github.com/anthropics/claude-code/issues/17688)）。目前使用外掛層級
> 的 `hooks/hooks.json` 作為替代方案。當此 bug 修復後，hooks 可移回 SKILL.md 以實現
> 技能範圍的執行。

## 🐛 除錯

```bash
# 查看 story 狀態（v2 路徑；v1 使用 prd.json）
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
