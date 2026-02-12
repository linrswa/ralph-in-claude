# Ralph WIP — Architecture Review Findings

> 2026-02-12 六方審查（3 Claude Opus + 3 Codex GPT-5.3）彙整

---

## Critical

- [x] **`exit 1` → `exit 2`** — ~~`validate-prd-write.sh` 驗證失敗時用 `exit 1`，但 Claude Code hooks 只有 `exit 2` 才能阻擋操作。~~ 已修正：`scripts/validate-prd-write.sh` 所有驗證失敗改為 `exit 2`。（v0.1.1）
- [x] **`storyIdToTaskId` mapping compaction 遺失** — ~~dispatcher 的 `storyIdToTaskId` 和 `retries` 只存在於 context memory 中。~~ 已修正：每波開始前從 TaskList 重建 `storyIdToTaskId`（解析 subject `US-001: Title` 格式）；retries 改為計算 prd.json notes 中的 `"Attempt N failed:"` 條目數。不需額外檔案或 hook。（v0.1.2）

## High

- [ ] **Plugin skill hooks 可能不觸發** — GitHub Issue [#17688](https://github.com/anthropics/claude-code/issues/17688) 確認：透過 marketplace 安裝的 plugin 中，SKILL.md frontmatter 定義的 hooks 不會觸發（project skills 正常）。需測試確認當前版本是否已修復。備選方案：移到 plugin-level `hooks/hooks.json`。
- [x] **同 branch 並行 git race condition** — ~~多個 subagent 共享同一 git 工作樹，file overlap check 只依賴 story `notes` 中手動提及的檔案路徑。~~ 已修正：subagent 不再執行 `git add`/`git commit`，改由 dispatcher 在 wave 結束後逐一驗證並 commit（§3.5），消除 git staging area race condition。搭配既有的 file overlap check（§3.2）防止同檔案並行修改。
- [ ] **驗證機制不夠完整** — 三重驗證中 subagent self-report 是最弱環節（考生自己批改考卷）。Dispatcher 不驗證 acceptance criteria 是否真的被滿足。缺少：lint 強制、test 執行、dispatcher 級 diff review、AC 逐項交叉驗證。

## Medium

- [ ] **Hook command 路徑解析風險** — `command: "scripts/..."` 是相對路徑，hook 在 CWD 執行時可能找不到腳本。應改用 `${CLAUDE_PLUGIN_ROOT}/skills/<skill>/scripts/...` 或確認 `CLAUDE_SKILL_DIR` 環境變數可用。
- [x] **Write matcher 範圍不足** — ~~目前只攔截 `Write` tool，但 `Edit` tool 也能修改 prd.json。~~ 已修正：兩個 SKILL.md 新增 `matcher: "Edit"`，validate 腳本用 Python 模擬 edit 結果後驗證。（v0.1.1）
- [ ] **validate-prd-write.sh hook 不檢查 dependency cycle** — hook 只驗證欄位完整性和 dependsOn 參照存在，不做 DAG cycle detection。Cycle 只在 `ralph:run` 執行時才被偵測。建議把 cycle check 前移到 hook 中，在寫入時就阻擋。
- [x] **Hook 腳本重複** — ~~`convert/scripts/` 和 `run/scripts/` 中的腳本完全相同。~~ 已修正：整合至 plugin root `scripts/`，SKILL.md 以 `../../scripts/` 引用。（v0.1.1）
- [ ] **`senior-engineer` subagent type 可移植性** — 非 Claude Code 內建類型，需在 `~/.claude/agents/senior-engineer.md` 定義。作為可分發 plugin，使用者可能沒有此定義，Claude 會 fallback 到 `general-purpose`。建議：(a) 在 plugin 中附帶 agent 定義，或 (b) 改用內建類型並在 prompt 中補充角色指令。
- [ ] **SKILL.md 聲稱 Tasks 是 ephemeral 不完全正確** — Tasks 實際上可持久化（存於 `~/.claude/tasks/<ID>/`），跨 session 可用。prd.json 作為 source of truth 的決策仍然正確，但文件敘述應修正以避免誤導。
- [ ] **Retry 缺少前次 attempt 的具體上下文** — 目前只附上 subagent 的 failure report（可能模糊）。應加入：前次 `git diff`（如有 commit）、typecheck/lint 的具體錯誤訊息（前 50 行），讓重試 subagent 不用從零開始。

## Low / Enhancement

- [ ] **Story sizing 缺乏自動偵測** — 目前靠「2-3 句話」的主觀標準，沒有自動化機制檢測 story 是否超出 context window。可在 convert skill 中加入複雜度估算（AC 數量、涉及技術棧、notes 檔案數），超閾值時建議拆分。
- [ ] **progress.txt 會持續膨脹** — Codebase Patterns 區段沒有 token 上限，20+ stories 後可能累積數千 tokens，擠壓 subagent context。建議設 token 上限 + 每 wave 後 dispatcher 做摘要壓縮。
- [ ] **Dispatcher 自身 context 耗盡風險** — Dispatcher 是長 session，大 PRD（15+ stories、5+ waves）可能接近 context 上限。與 v1（每 iteration 全新 instance）的設計哲學矛盾。可能需要 dispatcher 自身的 checkpoint/restart 機制。
- [ ] **缺少 crash-recovery reconcile** — Session 中斷時，subagent commits 可能已發生但 prd.json 尚未更新。Recovery 方案：啟動時掃描 `git log` 中的 `feat: <STORY_ID>` commit + typecheck，自動回填 `passes: true`。
- [ ] **動態 subagent type 選擇** — 目前固定用 `senior-engineer`。可根據 story 類型動態選擇（UI story → `frontend-design`，infra → `senior-engineer`），提高品質。
- [ ] **考慮 `ralph:pipeline` 一鍵串接** — 保留三段式作為安全預設，加一個 pipeline skill 做可選的一鍵 `prd → convert → run`。
- [ ] **Retry 第四選項：回溯修改依賴 story** — 當同一 story 連續 3 次失敗且原因涉及上游 story 產出物時，應建議「mark US-XXX as failed and retry from there」而非只有拆分/加 notes/跳過。
- [ ] **同 wave 內知識斷層** — 並行 workers 無法互相學習（Wave 1 的 A 發現 codebase 慣例，B 不知道）。可加 `{{WAVE_CONTEXT}}` placeholder 傳遞同 wave stories 的 brief summary。
