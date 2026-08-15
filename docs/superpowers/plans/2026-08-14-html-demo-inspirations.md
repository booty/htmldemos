# HTML Demo Inspirations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create a durable `INSPIRATIONS.md` field guide that turns research from browser-demoscene archives into original, actionable ideas for future self-contained HTML demos.

**Architecture:** One root Markdown document organized as a creative field guide, not an exhaustive catalog. It will move from scene context and observed patterns to implementation recipes, original demo seeds, and a source shelf for further browsing.

**Tech Stack:** Markdown, curated external links, no runtime dependencies.

## Global Constraints

- Keep the document useful to future agents: emphasize transferable techniques, visual premises, interaction patterns, and concrete prompts.
- Preserve the repository's offline-first browser contract: no demo idea should assume a CDN, remote asset, server-only API, or project-wide dependency.
- Draw inspiration from references without proposing direct copies of proprietary art, music, logos, code, or named productions.
- Keep sources linked and clearly separate observed reference patterns from original suggestions.
- Add only the requested inspiration document and this plan artifact; do not alter demo implementation files.

---

### Task 1: Write and verify the inspiration field guide

**Files:**
- Create: `INSPIRATIONS.md`

**Interfaces:**
- Consumes: Research notes from Pouët, Demozoo, Shadertoy, JS1k, DemoJS, and js13kGames.
- Produces: A root-level Markdown reference document with sections for scene map, patterns, constraints, prompts, and sources.

- [ ] **Step 1: Draft the scene map and reading strategy**

Explain the difference between browser demos, shader experiments, sizecoding, browser games, and traditional demoscene releases. Link the supplied archives and recommend a practical browsing order.

- [ ] **Step 2: Synthesize transferable patterns**

Document recurring patterns such as one striking visual premise, procedural geometry, raymarching, fractals/L-systems, tunnels, particles/fluids, palette discipline, faux hardware effects, tiny game loops, audio reactivity, and interaction as a performance.

- [ ] **Step 3: Add browser-specific design and constraint recipes**

Translate those patterns into offline-safe HTML guidance: Canvas 2D/WebGL choices, progressive enhancement, local assets, DPR/performance caps, user-gesture audio, direct-file testing, and optional size limits.

- [ ] **Step 4: Add original demo seeds**

Provide enough concrete prompts for a future agent to start a new demo folder immediately. Each seed should combine a visual premise, a technique, an interaction, and a palette or presentation constraint.

- [ ] **Step 5: Add a curated source shelf and verification**

Link every major research community used, include representative deep links where useful, run Markdown/link/whitespace checks, and inspect the final diff for accidental claims of copying or runtime dependencies.

- [ ] **Step 6: Commit the documentation change**

```bash
git add INSPIRATIONS.md docs/superpowers/plans/2026-08-14-html-demo-inspirations.md
git commit -m "docs: add HTML demo inspiration guide"
```
