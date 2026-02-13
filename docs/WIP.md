# Ralph WIP — Open Issues & Backlog

> 源自 2026-02-12 六方審查（3 Claude Opus + 3 Codex GPT-5.3）彙整。
> 已完成項目已移除，僅保留未解決的待辦事項。

---

## High

- [ ] **驗證機制不夠完整** — 三重驗證中 subagent self-report 是最弱環節（考生自己批改考卷）。Dispatcher 不驗證 acceptance criteria 是否真的被滿足。缺少：lint 強制、test 執行、dispatcher 級 diff review、AC 逐項交叉驗證。

## Medium

- [ ] **validate-prd-write.sh 不檢查 dependency cycle** — hook 只驗證欄位完整性和 `dependsOn` 參照存在，不做 DAG cycle detection。Cycle 只在 `/ralph:run` 執行時才被偵測。建議把 cycle check 前移到 hook 中，在寫入時就阻擋。
- [ ] **SKILL.md 對 Tasks 的描述不完全正確** — SKILL.md 聲稱 Tasks 是 ephemeral，但實際上可持久化（存於 `~/.claude/tasks/<ID>/`）。prd.json 作為 source of truth 的決策仍然正確，但文件敘述應修正。
- [ ] **Retry 缺少前次 attempt 的具體上下文** — 目前只附上 subagent 的 failure report（可能模糊）。應加入：前次 `git diff`（如有 commit）、typecheck/lint 的具體錯誤訊息（前 50 行），讓重試 subagent 不用從零開始。

## Low / Enhancement

- [ ] **Story sizing 缺乏自動偵測** — 目前靠「2-3 句話」的主觀標準。可在 convert skill 中加入複雜度估算（AC 數量、涉及技術棧），超閾值時建議拆分。
- [ ] **progress.txt 會持續膨脹** — 20+ stories 後可能累積數千 tokens。建議設 token 上限 + 每 wave 後 dispatcher 做摘要壓縮。
- [ ] **Dispatcher 自身 context 耗盡風險** — 大 PRD（15+ stories、5+ waves）可能接近 context 上限。可能需要 dispatcher checkpoint/restart 機制。
- [ ] **缺少 crash-recovery reconcile** — Session 中斷時 prd.json 可能未更新。Recovery：啟動時掃描 `git log` 中的 `feat: <STORY_ID>` commit + typecheck，自動回填 `passes: true`。
- [ ] **動態 subagent type 選擇** — 目前固定用 `ralph-worker`。可根據 story 類型動態選擇（UI → `frontend-design`，infra → `senior-engineer`）。
- [ ] **`ralph:pipeline` 一鍵串接** — 加一個 pipeline skill 做可選的 `prd → convert → run` 一鍵流程。
- [ ] **Retry 回溯依賴 story** — 當 story 連續 3 次失敗且原因涉及上游 story 時，應建議 mark 依賴 story as failed 並從那裡重試。
- [ ] **同 wave 內知識斷層** — 並行 workers 無法互相學習。可加 `{{WAVE_CONTEXT}}` placeholder 傳遞同 wave stories 的 brief summary。
