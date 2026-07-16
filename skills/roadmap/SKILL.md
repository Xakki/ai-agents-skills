---
name: roadmap
description: >-
  Plan and autonomously build an entire application phase by phase. Generates a
  phased roadmap blueprint, then executes it phase by phase — commits at
  milestones, deploys via make, tests, and keeps going until it hits a blocker
  or finishes. Modes: plan (generate the roadmap), start (begin execution),
  resume (continue from where it stopped), status (show progress). Триггеры RU:
  «roadmap», «составь дорожную карту», «построй всё приложение», «начни
  строить», «продолжай сборку», «исполни roadmap», «на какой мы фазе». EN:
  «roadmap», «start building», «resume the build», «keep going», «build the
  whole thing», «execute the roadmap», «what phase are we on».
allowed-tools:
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - Bash
  - Agent
  - Skill
---

# Roadmap — phased app build

Generate an exhaustive technical roadmap for building a whole application, then execute it autonomously. Detailed enough that an agent can pick up any phase and work it for hours without further clarification.

This is **not** a high-level strategy doc. It is a **delivery blueprint**: every phase has concrete tasks, every task is actionable, and the whole order is arranged to build from phase 1 to launch with no backtracking.

## When to use

- Kicking off a large new product (after deep-research or from a product brief)
- Turning a fuzzy idea into an executable plan
- Planning a multi-week build spread across many sessions
- Before you say "build it" — the roadmap is what gets executed

## Inputs

You need one of:

| Input | Where to get it |
|-------|-----------------|
| Deep-research brief | MemPalace (`mempalace_search`, scoped to the project wing) |
| Product brief | User describes what they want |
| Partially built app | Read `CLAUDE.md` + `IDEA.md`/`ROADMAP.md` + the codebase |
| Competitor to clone/improve | URL or name — analyze it |

If all you're told is "plan a notes app" — that's enough; ask clarifying questions as you go.

## Modes

| Mode | Triggers | What it does |
|------|----------|--------------|
| `plan` | "draft a roadmap", "plan it" | Generates/updates `ROADMAP.md` (see Generation workflow) |
| `start` | "start building", "execute the roadmap" | Executes from phase 1, phase by phase, no stops |
| `resume` | "keep going", "what phase are we on" | Finds the first open phase/task and continues |
| `status` | "roadmap status", "what's done" | Progress summary by phase |

---

## Generation workflow (`plan` mode)

### 1. Pin the vision

Before any technical planning, nail down:
- **One sentence**: what is it? ("Cloud markdown knowledge workspace for teams and AI agents")
- **Who**: primary/secondary users, agents?
- **Why**: what can't existing tools do, what's the gap?
- **Constraints**: stack, budget, timeline, must-haves?
- **What we're NOT building**: what's explicitly out of scope?

### 2. Decide the stack

```markdown
| Layer | Choice | Why |
|-------|--------|-----|
| Frontend | … | … |
| Backend | … | … |
| DB | … | … |
| Auth | … | … |
| Storage | … | … |
| Search | … | … |
| Hosting | … | … |
```

If there's a deep-research brief, take its recommendations. Otherwise make a deliberate choice based on the project's existing stack (read `CLAUDE.md`/`IDEA.md`).

### 3. Design the data model

Sketch **all** tables/collections the final product needs — not just phase 1. This prevents mid-build schema rework. Mark which tables belong to which phase.

```markdown
## Data model
### <entity>
  id, <type>
  <field>, <type>, <constraints>
  created_at, updated_at
### Relations
- <entity> has many <entity> via <field>
```

### 4. Plan the phases

The core of the roadmap. Every phase must:
- **Have a clear goal** — one sentence on what changes when the phase is done
- **Be independently deployable** — the app works (with reduced features) after each phase
- **Build on the previous one** — no phase requires throwing away prior work
- **Fit in 1–3 sessions** — if a phase takes more than a day, split it

#### Phase template

```markdown
## Phase N — <Name>
*Goal: <one sentence — what the user can do after this phase>*
*Depends on: Phase N-1*
*Estimate: <hours/sessions>*

### What's new
<user-visible features>

### DB changes
<new tables/columns, migrations>

### API routes
<new endpoints>

### Frontend
<new pages/components>

### Infrastructure
<new resources, secrets, config>

### Task checklist
#### Setup
- [ ] …
#### Data Layer
- [ ] …
#### API
- [ ] …
#### Frontend
- [ ] …
#### Tests and polish
- [ ] …

### Definition of Done
<how to verify the phase is done — what to test, what to deploy>
```

### 5. Phase patterns

- **Phase 1 — always the MVP.** A working tool that **one person** actually uses instead of their current solution (even Excel). Test: "Would you use this instead of what you use now?" If no, the MVP is too thin. Typically: auth (single user/invite-only), 2–3 tables, CRUD on the core entity, basic UI (list + detail + create), deploy to prod, minimal styling.
- **Phase 2 — make it real.** UI polish, secondary features (search/filters/sort), validation, empty states and onboarding (skill `frontend-design`), mobile responsiveness, export/import.
- **Phase 3 — the differentiator.** What sets the product apart: AI features, MCP server, semantic search — the reason to pick it over an established player.
- **Phase 4+ — growth.** Multi-user/teams, advanced views (graph, canvas, calendar, kanban), integrations (API, webhooks), admin/settings, perf, public features (sharing, embed).
- **Final phase — platform** (only if going multi-tenant/SaaS): customer workspaces, billing/plans, white-label, API tokens.

### 6. Summary maps

At the end of the roadmap, provide:
- **Build order** — table: phase | goal | new tables | new routes | sessions
- **Schema evolution** — table: table × phase (✓ / +column)
- **API map** — table: route | phase | auth | purpose
- **Deliberately Not Building** — what's out of scope and why (mandatory section, kills scope creep)

---

## Integration with our tooling

Adapt to the user's environment (see `~/CLAUDE.md`, `~/.claude/CLAUDE.md`, project `CLAUDE.md`):

| Action | How we do it (NOT generic) |
|--------|----------------------------|
| Deploy / run | **Only via `make`** (`make up`, `make deploy`, `make app-front@build`, etc.). No matching target — add it to the `Makefile`, don't call the command directly |
| Review between phases | `/code-review` (reviewer's verdict to the main thread) |
| Quality gate | skill `qa-check` (`make lint` + `make test`) before closing a phase |
| Verify "works live" | skill `/verify` or `/run` on the deployed stand |
| UI/onboarding/empty states | skill `frontend-design` |
| Past memory/context | MemPalace MCP (`mempalace_search`, scoped to the project wing) + in-repo memory |
| Notify on long phase/completion | skill `tg-notify` (>10 min wall-clock or on explicit request) |
| Docs at the end | update `CLAUDE.md` / `docs/` |

**Where the roadmap lives:** project root `ROADMAP.md` (or `docs/ROADMAP.md` if a `docs/` dir exists). It's the project's north star — the agent reads it at the start of any session and knows what to build next.

**Kanban integration.** If the project runs a `.claude/kanban/` board, the **cards are the canonical task source** and `ROADMAP.md` gives the phased picture and references the cards (see the rule in `~/.claude/CLAUDE.md`). Then:
- Phase tasks are created as cards (skill `kanban`), ids like `K-NNN`.
- In the phase template, reference cards instead of bare checkboxes: `- [ ] K-042 — …`.
- Phase progress = card stages (todo/progress/test/done), not just checkmarks in `ROADMAP.md`.

**Delegation (teamlead mode).** Per `~/.claude/CLAUDE.md` the main thread is the teamlead: delegate file reading, edits, debugging, and large dumps to subagents via `Agent` (per the routing table in the project `CLAUDE.md`), surfacing only decisions and results to the main thread. Review — via `@reviewer`/`/code-review`. Before each task, decide: fresh agent or compact the current one's context.

**Commits** — in the user's style: `<scope>: <imperative>`, subject ≤72, no trailers/signatures, whole message ≤255. Scopes per project (e.g. `api|goclient|ext|infra|db|docs|task`). The phase-boundary commit is its own message with a clear goal.

---

## Execution (`start` / `resume` modes)

### `start`

1. Read `ROADMAP.md`.
2. Confirm the project is up (repo, deps, infra resources created).
3. Start at Phase 1, task by task (delegating to subagents).
4. After each task — verify it works (build/run/test).
5. After all the phase's tasks — run the Definition of Done + `qa-check`.
6. Commit at the phase boundary (user's style).
7. Deploy via `make` if there's a deploy target.
8. Quick `/code-review` or `/verify` on the deployed build.
9. Mark the phase done in `ROADMAP.md` (and move cards to `done/`).
10. **Move to the next phase. Don't stop. Don't ask.**
11. Repeat until finished or blocked.

### `resume`

1. Read `ROADMAP.md` — find the first open phase.
2. Check `git log` — the last roadmap commit; and the kanban card stages.
3. Reconcile what's in the codebase vs what the phase expects.
4. Continue from the first incomplete task of the current phase. From there — same as `start`.

### `status`

Read `ROADMAP.md` (+ the kanban board) and produce a summary:

```
Phase 1: MVP ✅ (commit abc1234)
Phase 2: Polish + search ✅ (commit def5678)
Phase 3: AI + MCP ← IN PROGRESS (7/15 tasks)
Phase 4: Teams — not started
```

### Execution rules

**Keep going.** Default is: after a phase, straight to the next, no "may I continue" pause. The roadmap IS the permission.
**Commit at phase boundaries.** Each finished phase = its own commit → natural recovery points.
**Deploy after each phase** via `make` if there's a target. A real deploy catches what local can't.
**Quick check between phases** (`/code-review` or `/verify`) — catch broken routes/regressions before the next phase builds on them.
**Thorough check at the end:** full `/code-review`, `frontend-design` for empty states/onboarding, update the docs (`CLAUDE.md`/`docs/`).

**Stop ONLY when:**
- A task fails and the cause is unclear (unfamiliar error) → skill `systematic-debugging`, then if stuck — to the user
- You need access/a key/an account you don't have
- You need a design decision from a human ("modal or page?")
- The build is finished

**Do NOT stop for:** "continue?" (yes), "deploy?" (yes if there's a target), "commit?" (yes, at phase boundaries), or minor things that don't block the next task — file a card/issue and move on.

### Progress tracking

Markers right in `ROADMAP.md`:

```markdown
## Phase 1 — MVP ✅
*Completed: 2026-03-19, commit abc1234*
```
```markdown
### Task checklist
- [x] K-040 — DB schema (notes, folders)
- [x] K-041 — API CRUD notes
- [ ] K-042 — editor  ← CURRENT
```

`ROADMAP.md` (+ the kanban card stages) is the session file: no separate handoff doc needed — the next incomplete task is the instruction.

---

## Quality rules (for `plan`)

1. **Every task actionable** — not "set up auth" but "set up better-auth (email/password), user/session tables, middleware".
2. **Phases are deployable** — after each one the app works. No "infra phases" with no visible result.
3. **Phase 1 ruthlessly small** — longer than 2–3 sessions → cut scope.
4. **Data model complete upfront** — mid-build schema rework is the #1 time sink.
5. **"Deliberately Not Building" is mandatory** — without it every phase sprawls.
6. **Tasks grouped by layer** (data/API/frontend/infra) — build in layers, not features.
7. **Every phase has a Definition of Done** (what to test and verify).
8. **Stack table included** — don't force guessing tech choices at every phase.

## Common mistakes

- Roadmap as strategy, not blueprint → tasks aren't executable. Every task must be ready to execute.
- Phase 1 bloated → no fast working result. Cut it down to "one person, one purpose".
- Deploy/commands run directly, bypassing `make` → convention violation. Always via a `make` target.
- Ignoring kanban on a project with a board → split task source. Cards are canonical, the roadmap references them.
