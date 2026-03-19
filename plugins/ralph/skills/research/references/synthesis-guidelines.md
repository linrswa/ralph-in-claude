# Synthesis Guidelines

Instructions for the research coordinator when combining findings from parallel research agents into a unified report.

## Synthesis Process

### 1. Extract and Categorize

For each agent's output, extract:
- **Facts** — concrete findings backed by evidence (file paths, search results, benchmarks)
- **Opinions** — recommendations, preferences, judgments
- **Risks** — issues flagged with severity
- **Gaps** — things the agent couldn't find or determine

### 2. Cross-Reference

Look for patterns across agents:
- **Agreement** — multiple agents independently reaching the same conclusion strengthens confidence
- **Contradiction** — different agents disagreeing signals a genuine trade-off or ambiguity worth highlighting
- **Complementary findings** — one agent's finding providing context for another's

### 3. Resolve Conflicts

When agents disagree:
- Present both perspectives in the report
- Note the evidence each side has
- If one side has stronger evidence, say so — but don't hide the disagreement

### 4. Build the Narrative

The research report should tell a story:
1. **Executive Summary** — the headline answer: is this feasible? what's the recommended path?
2. **Supporting evidence** — organized by section (feasibility, architecture, codebase impact, etc.)
3. **Story decomposition** — concrete suggestions that bridge into PRD generation
4. **Risks and open questions** — honest about what's still unknown

### 5. Quality Checks

Before finalizing:
- Every claim in the Executive Summary is supported by findings in the body
- File paths and code references have been mentioned by at least one agent (don't invent references)
- The Suggested Story Decomposition is concrete enough to seed a PRD (not just "build the backend")
- Open Questions are genuinely unresolved (not things you could answer from the findings)
- Risks have both severity AND mitigation suggestions

## Tone

- **Decisive but honest** — make clear recommendations while acknowledging uncertainty
- **Concrete** — prefer specifics ("use the existing `AuthMiddleware` in `src/middleware/auth.ts`") over generalities ("leverage existing auth infrastructure")
- **Actionable** — every section should help the user make a decision or take a next step
