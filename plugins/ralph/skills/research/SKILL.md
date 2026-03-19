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
4. **Checkpoint 1:** Present angles to user for confirmation
5. Spawn parallel research agents (default 3, up to 8 for complex topics)
6. Collect and synthesize findings
7. **Checkpoint 2:** Present findings, allow deep-dive requests
8. **Checkpoint 3:** Confirm handoff to `/ralph:prd`
9. Save research report

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

## 3. Checkpoint 1 — Angle Selection

Use `AskUserQuestion` to present the planned research angles and let the user adjust. Format:

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

### 4.3 Dispatch

Spawn all agents in a **single message** with parallel `Agent` calls:

```
For each angle:
  Agent(
    subagent_type: "ralph:research-worker" or "ralph:research-architect",
    description: "Research: <angle-name>",
    prompt: <generated prompt>,
    run_in_background: true,
    name: "research-<angle-slug>"
  )
```

Do NOT set the `model` parameter — let each agent's definition control its own model.

While agents are running, inform the user that research is in progress and how many agents were dispatched.

---

## 5. Collect and Synthesize

After all agents return:

1. **Read each agent's output** — extract key findings, recommendations, risks, and references
2. **Follow the synthesis guidelines** in `references/synthesis-guidelines.md` to combine findings
3. **Identify cross-cutting insights** — patterns, contradictions, or connections across angles
4. **Flag open questions** — items that need user input before PRD generation

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

After saving, tell the user:

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
