---
name: research
description: "Research a feature idea or problem by spawning parallel agents to explore feasibility, architecture, existing code, prior art, scope, and risks. Produces a structured research report that feeds into ralph:prd. Use when the user wants to research, explore, investigate, or brainstorm a feature idea before committing to a PRD. Also triggers when the user is unsure about technical feasibility, wants to compare architectural approaches, needs to understand codebase impact, or has a vague idea that needs structured analysis. Covers Chinese triggers like '研究', '探索', '可行性', '分析一下'. This is the pre-PRD discovery step — use it before ralph:prd, not instead of it."
argument-hint: "[feature-idea-or-problem-statement]"
---

# Ralph Research — Parallel Feature Discovery

You are the **research coordinator** — you take a vague feature idea or problem statement, decompose it into research angles, dispatch parallel agents to investigate each angle, then synthesize their findings into a structured report that feeds into `/ralph:prd`.

The goal is to help users think through what they actually need before committing to a PRD. A good research report surfaces feasibility issues, architectural trade-offs, existing code to leverage, and risks — all before a single line of implementation is written.

**CRITICAL: When asking the user questions, ALWAYS use the `AskUserQuestion` tool. Do NOT output questions as plain text.**

---

## The Job

1. Receive a feature idea or problem statement
2. Quick codebase scan to understand project context
3. Select 3-5 research angles based on the topic's nature
4. Determine execution mode (normal vs team)
5. **Checkpoint 1:** Present angles (and team mode option if 3+ agents) to user for confirmation
6. Spawn parallel research agents
7. Collect and synthesize findings
8. **Checkpoint 2:** Present findings, allow deep-dive requests
9. **Checkpoint 3:** Confirm handoff to `/ralph:prd`
10. Save research report and clean up team (if used)

---

## 0. Locate or Receive Input

- **If an argument was provided** → use it as the feature description
- **If no argument** → use `AskUserQuestion` to ask the user to describe their feature idea or problem

---

## 1. Codebase Context (Quick Scan)

Before selecting research angles, understand the project. This takes 2-3 minutes, not an exhaustive audit.

Use **Glob** and **Grep** to determine:

1. **Tech stack** — framework, language, build tools (`package.json`, `Cargo.toml`, `go.mod`, `pyproject.toml`, etc.)
2. **Project structure** — key directories, routing patterns, data layer
3. **Related code** — anything already existing that relates to the feature idea

This context informs which research angles matter and gets passed to each research agent.

---

## 2. Select Research Angles

Choose 3-5 angles from the table below based on the feature's nature. Not every angle applies to every feature.

| # | Angle | Agent Type | What It Investigates | When to Include |
|---|-------|-----------|---------------------|-----------------|
| 1 | **Feasibility & Constraints** | research-worker (Sonnet) | Technical feasibility within the current codebase. Dependencies, version constraints, platform limitations. | Almost always — skip only for trivial additions |
| 2 | **Architecture & Design** | research-architect (Opus) | Multiple approaches with trade-offs, data models, API shape, component hierarchy. | When there are meaningful design choices to make |
| 3 | **Existing Codebase Analysis** | research-worker (Sonnet) | Reusable components, established patterns, files that will need modification, potential conflicts. | When the project has substantial existing code |
| 4 | **Prior Art & Alternatives** | research-worker (Sonnet) | How similar features are commonly implemented in the ecosystem. Library options, common pitfalls. **Must use WebSearch/WebFetch.** | When the feature isn't trivially obvious |
| 5 | **Scope & Decomposition** | research-worker (Sonnet) | Story breakdown suggestions, dependency ordering, phase grouping. Directly seeds the PRD. | Almost always — this bridges research → PRD |
| 6 | **Risk & Edge Cases** | research-worker (Sonnet) | Security concerns, performance implications, backward compatibility, migration needs. | When the feature touches sensitive areas or data |

### Complexity Assessment

**The default is always 3 agents.** Only escalate when there is a concrete reason — "more research can't hurt" is not a valid reason. Each additional agent costs time and tokens, so be disciplined.

Use this decision tree to assess complexity:

1. **Count the layers touched:** How many distinct system layers does this feature span?
   - Frontend only, backend only, or single-layer → 1 layer
   - Frontend + backend, or backend + database → 2 layers
   - Frontend + backend + database/infrastructure → 3 layers
   - Full-stack + external systems (hardware, 3rd-party APIs, protocols) → 4+ layers

2. **Count the unknowns:** How many of these are true?
   - No clear existing pattern to follow in the codebase
   - Multiple viable architectural approaches with non-obvious trade-offs
   - External dependencies or ecosystem choices to evaluate
   - Security, compliance, or migration risks

3. **Classify:**

| Layers | Unknowns | Classification | Agents |
|--------|----------|---------------|--------|
| 1-2 | 0-1 | **Simple** | **3** — pick the 3 most relevant angles |
| 1-2 | 2+ | **Moderate** | **4** — add the angle that addresses the unknowns |
| 3+ | 0-1 | **Moderate** | **4** — add Codebase Analysis or Risk |
| 3+ | 2+ | **Complex** | **5-8** — cover all relevant angles, split if needed |

**Examples:**
- "Add a filter dropdown" → 1 layer, 0 unknowns → Simple (3 agents)
- "Add incremental doc updates" → 2 layers, 1 unknown → Simple (3 agents)
- "Add SPI protocol alongside I2C across RTL + backend + frontend" → 4 layers, 3 unknowns → Complex (6 agents)
- "Build a plugin marketplace" → 3 layers, 2+ unknowns → Complex (5 agents)

The maximum is 8 agents. If you assess the topic as needing more than 3, you MUST state the layer count and unknown count to justify it at Checkpoint 1.

---

## 2.5 Team Mode Detection

When more than 3 agents are needed, **team mode** becomes available. In team mode, research agents join a shared team and can exchange intermediate findings via `SendMessage` — for example, the "Codebase Analysis" agent discovering a critical pattern can immediately inform the "Architecture" agent, rather than waiting for the coordinator to synthesize after all agents finish.

### Decision Logic

1. **3 agents or fewer** → always use normal mode (parallel fire-and-forget). Skip this section entirely.
2. **More than 3 agents** → evaluate team mode:
   a. **User's prompt signals team intent** (e.g., contains words like "team", "collaborate", "協作", "組隊", "swarm", or explicitly requests team-based research) → **auto-enable team mode**, skip the team question at Checkpoint 1.
   b. **No explicit team intent** → **offer team mode as an option** at Checkpoint 1 (see §3).

### Checking Team Feature Availability

Before enabling team mode, verify the feature is available:

```bash
echo $CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS
```

- If the output is `1` → team feature is available, proceed with team mode.
- If empty or missing → team feature is not enabled. Inform the user:

  > Team mode is available for 3+ agent research but requires enabling the experimental teams feature. To enable it, add this to your Claude Code settings (`~/.claude/settings.json`):
  > ```json
  > { "env": { "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1" } }
  > ```
  > Proceeding with normal parallel mode for now.

  Then fall back to normal mode for this session.

### What Team Mode Changes

| Aspect | Normal Mode | Team Mode |
|--------|------------|-----------|
| Agent communication | None — agents work in isolation | Agents share key discoveries via `SendMessage` |
| Coordination | Coordinator synthesizes after all complete | Agents can adapt mid-research based on peers' findings |
| Token cost | Lower | ~10-20% higher due to inter-agent messages |
| Best for | Simple/focused research (3 agents) | Complex cross-cutting research (4+ agents) |

Set an internal flag `TEAM_MODE = true/false` to control dispatch behavior in §4.

---

## 3. Checkpoint 1 — Angle Selection

Use `AskUserQuestion` to present the planned research angles and let the user adjust.

### Format (3 agents — normal mode)

```
I've analyzed the project and your feature idea. Here's my research plan:

**Feature:** [feature description]
**Complexity:** [Simple/Moderate/Complex] — [brief reasoning]
**Agents:** [N]

**Research angles:**
1. [Angle name] — [what it will investigate]
2. [Angle name] — [what it will investigate]
3. [Angle name] — [what it will investigate]

Options:
A) Proceed with this plan
B) Add an angle: [suggest one that was excluded and why it might help]
C) Remove an angle: [identify which one is least valuable]
D) Modify: let me describe what I want changed
```

### Format (3+ agents — team mode eligible)

If team mode was NOT auto-enabled by user intent (see §2.5), add a team mode option:

```
I've analyzed the project and your feature idea. Here's my research plan:

**Feature:** [feature description]
**Complexity:** [Moderate/Complex] — [N layers, M unknowns]
**Agents:** [N]

**Research angles:**
1. [Angle name] — [what it will investigate]
2. [Angle name] — [what it will investigate]
3. [Angle name] — [what it will investigate]
4. [Angle name] — [what it will investigate]

**Team mode available:** With [N] agents, team mode lets agents share discoveries in real-time — e.g., the Codebase Analysis agent can inform the Architecture agent about existing patterns mid-research. Costs ~10-20% more tokens but produces better-connected findings for complex topics.

Options:
A) Proceed with team mode
B) Proceed without team mode (normal parallel)
C) Add/remove/modify angles
D) Modify: let me describe what I want changed
```

If team mode was auto-enabled, show the plan with a note: **"Team mode: enabled (based on your request)"** and don't offer the B option.

If the user requests changes, adjust and confirm again.

---

## 4. Spawn Research Agents

### 4.1 Read prompt templates

- Read `references/researcher-prompt-template.md` for Sonnet worker angles
- Read `references/architect-prompt-template.md` for the Architecture & Design angle

### 4.2 Generate prompts

For each angle, substitute placeholders in the appropriate template:

- `{{ANGLE_NAME}}` → the angle name (e.g., "Feasibility & Constraints")
- `{{ANGLE_INSTRUCTIONS}}` → specific instructions for this angle (from the angle descriptions in §2)
- `{{FEATURE_DESCRIPTION}}` → the user's feature idea
- `{{PROJECT_NAME}}` → from codebase scan
- `{{TECH_STACK}}` → framework, language, key dependencies
- `{{PROJECT_STRUCTURE}}` → summary of key directories and patterns
- `{{RELATED_CODE}}` → existing code related to the feature
- `{{USER_CONSTRAINTS}}` → any constraints the user mentioned
- `{{TEAM_COLLABORATION}}` → team collaboration instructions (see §4.3), or empty string if normal mode

### 4.3 Dispatch

#### Normal Mode (TEAM_MODE = false)

Spawn all agents in a **single message** with parallel `Agent` calls:

```
For each angle:
  Agent(
    subagent_type: "ralph:research-worker" or "ralph:research-architect",
    description: "Research: <angle-name>",
    prompt: <generated prompt with {{TEAM_COLLABORATION}} = "">,
    run_in_background: true,
    name: "research-<angle-slug>"
  )
```

#### Team Mode (TEAM_MODE = true)

**Step 1:** Create the research team:

```
TeamCreate(
  team_name: "research-<feature-slug>",
  description: "Parallel research for: <feature description>"
)
```

**Step 2:** Create tasks for each angle:

```
For each angle:
  TaskCreate(
    title: "Research: <angle-name>",
    description: "<angle instructions summary>"
  )
```

**Step 3:** Spawn agents as team members and fill in `{{TEAM_COLLABORATION}}` with these instructions:

```
## Team Collaboration

You are part of a research team investigating this feature from multiple angles simultaneously.
Your teammates are researching other angles — sharing key discoveries helps everyone produce better findings.

### Sharing discoveries (outbound)

**When to share:** As soon as you discover something that would meaningfully change how another agent approaches their angle — don't wait until your report is done. Examples:
- A critical constraint or limitation that affects design choices
- An existing pattern or component that others should know about
- A dependency conflict or version issue that limits options

**How to share:**
- Use `SendMessage(to: "*", message: "<your discovery>", summary: "<5-word summary>")` to broadcast to all teammates
- Keep messages short and actionable (2-3 sentences max)
- Don't share routine findings — only things that would change another agent's approach

### Checking peer discoveries (inbound)

**Check messages at two points during your research:**

1. **Mid-exploration checkpoint** — after your initial scan (reading key files, understanding the landscape) but BEFORE deep-diving into analysis. If a teammate already found something relevant, adapt your approach:
   - Skip areas they've already covered in depth
   - Dig deeper into areas they flagged as important but didn't fully explore
   - Adjust your analysis to account for constraints they discovered

2. **Pre-report checkpoint** — before writing your final report. Incorporate any late-arriving findings into your analysis and note cross-team confirmations.

The goal is to redirect your research based on peer findings early enough to save tokens and produce deeper, non-redundant analysis. If you see a teammate already discovered something you were about to investigate, pivot to a different aspect of your angle instead of duplicating their work.

**Budget: 0-3 messages per agent.** The goal is avoiding duplicated effort and surfacing cross-cutting connections, not having a conversation.
```

Spawn agents in a **single message**:

```
For each angle:
  Agent(
    subagent_type: "ralph:research-worker" or "ralph:research-architect",
    description: "Research: <angle-name>",
    prompt: <generated prompt with {{TEAM_COLLABORATION}} filled in>,
    run_in_background: true,
    name: "research-<angle-slug>",
    team_name: "research-<feature-slug>"
  )
```

Do NOT set the `model` parameter — let each agent's definition control its own model.

While agents are running, inform the user that research is in progress, how many agents were dispatched, and whether team mode is active.

---

## 5. Collect and Synthesize

After all agents return:

1. **Read each agent's output** — extract key findings, recommendations, risks, and references
2. **Follow the synthesis guidelines** in `references/synthesis-guidelines.md` to combine findings
3. **Identify cross-cutting insights** — patterns, contradictions, or connections across angles
4. **Flag open questions** — items that need user input before PRD generation

### Team Mode Bonus

In team mode, agents may have already cross-pollinated findings via `SendMessage`. During synthesis:
- Note which discoveries were shared between agents (these are higher-confidence findings)
- Check if agents adapted their analysis based on peer messages — this is a sign the team mode added value
- Mention in the report if team collaboration surfaced insights that wouldn't have appeared in isolated research

---

## 6. Checkpoint 2 — Findings Review

Present a concise summary to the user via `AskUserQuestion`:

```
Research complete. Here's what I found:

**Executive Summary:**
[2-3 key takeaways]

**Recommended Approach:**
[Brief description of the recommended path]

**Key Risks:**
- [Top 1-3 risks]

**Open Questions:**
- [Questions needing user input]

Options:
A) Looks good — save the report and proceed to PRD
B) Deep-dive into [specific area] — I want more detail on...
C) I have answers to the open questions
D) Redo research with different angles
```

If the user requests a deep-dive (option B), spawn additional agent(s) focused on that area, then re-synthesize and present again. This loop continues until the user is satisfied.

If the user answers open questions (option C), incorporate their answers into the report.

---

## 7. Save Research Report

### 7.1 Check for existing files

Scan `.ralph-in-claude/tasks/research-*.md`:
- If a file with the same slug exists, use `AskUserQuestion` to ask overwrite or rename

### 7.2 Write the report

Ensure `.ralph-in-claude/tasks/` exists (create if needed).

Slugify the feature name to lowercase-kebab-case, max 4-5 words.

Save to `.ralph-in-claude/tasks/research-[feature-slug].md` with this structure:

```markdown
# Research Report: [Feature Name]

**Generated:** [timestamp]
**Feature:** [original feature description]
**Angles investigated:** [list]
**Mode:** [Normal / Team]

---

## Executive Summary

[2-3 paragraph synthesis — this is the primary context for ralph:prd]

## Feasibility Assessment

**Verdict:** Feasible / Feasible with caveats / Not feasible
- [Key findings]
- [Constraints identified]

## Recommended Architecture

**Approach:** [recommended approach name]
- [Design decisions and rationale]
- [Alternatives considered and why rejected]

## Codebase Impact

- **Files to modify:** [list with reasons]
- **Reusable patterns:** [existing code to follow]
- **New files needed:** [list]
- **Potential conflicts:** [shared file concerns]

## Suggested Story Decomposition

[Phase-ordered breakdown — this directly seeds the PRD user stories]

### Phase 1: [Name]
- [Story suggestion with rough scope]

### Phase 2: [Name]
- [Story suggestion]

### Phase 3: [Name]
- [Story suggestion]

## Risks & Mitigations

| Risk | Severity | Mitigation |
|------|----------|------------|
| [risk] | high/medium/low | [mitigation] |

## Open Questions

- [Remaining questions, with user's answers if provided at Checkpoint 2]

## Raw Findings by Angle

### [Angle 1 Name]
[Full findings from that agent]

### [Angle 2 Name]
[Full findings from that agent]
```

---

## 8. Checkpoint 3 — Handoff

If team mode was used, clean up:
1. Send shutdown requests to all remaining team members (they should already be done, but be safe)
2. Call `TeamDelete` to remove the team and its task list

After saving and cleanup, tell the user:

> Research saved to `.ralph-in-claude/tasks/research-[slug].md`.
> Next step: run `/ralph:prd` to generate a PRD informed by this research.

---

## Checklist

Before saving the report:

- [ ] Codebase context gathered (tech stack, structure, related code)
- [ ] Research angles confirmed with user (Checkpoint 1)
- [ ] All agents completed and findings collected
- [ ] Findings synthesized with cross-cutting insights
- [ ] User reviewed findings (Checkpoint 2)
- [ ] Open questions addressed or documented
- [ ] Report follows the output structure
- [ ] Report saved to `.ralph-in-claude/tasks/research-[slug].md`
- [ ] If team mode was used: team cleaned up (shutdown + TeamDelete)
