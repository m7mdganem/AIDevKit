---
name: implementation-planner
description: Produces a highly descriptive, spec-grade implementation plan to hand off to a separate AI coding agent. The plan captures all requirements like a spec, organizes work into dependency-ordered waves, and explicitly marks which tasks can run in parallel so the implementing agent can spawn subagents to speed up delivery. It finishes by printing the exact, copy-paste-ready prompt the user will give to the implementing agent. Use this whenever the user asks you to plan, spec out, design, scope, or break down a feature, refactor, bug fix, or migration that another AI agent will implement.
license: MIT
---

# Implementation Planner

Your job with this skill is **not to implement** the work. Your job is to produce
a self-contained, spec-grade **plan** that another AI agent can execute with
minimal additional context, and to hand the user the **exact prompt** they will
paste into that implementing agent.

Optimize the plan for two things:

1. **Completeness** — it reads like a specification. The implementing agent
   should rarely need to ask follow-up questions.
2. **Parallelism** — clearly identify which tasks are independent and can be
   worked on simultaneously by subagents, and which must be sequential because
   of dependencies. This lets the implementing agent fan out work and finish
   faster.

Follow the process below in order.

## Step 1 — Understand the request and gather context

1. Restate the goal in one or two sentences to confirm your understanding.
2. Investigate before planning. Use your available tools (read files, search the
   codebase, inspect configs, read docs/ADRs, check existing conventions) so the
   plan reflects how *this* project actually works — naming, layering, test/build
   commands, directory structure, and existing patterns. Cite concrete files and
   symbols in the plan.
3. Identify and resolve ambiguity. If a decision materially changes the design
   (scope, data model, API shape, UX behavior, edge-case handling), **ask the
   user a focused question** before writing the plan rather than guessing. Record
   the resolved answers in the plan's Assumptions section.

## Step 2 — Map dependencies and parallelism

Before writing tasks, build a quick dependency model in your head (or as a short
list):

- For each unit of work, note what it **depends on** (files, types, schema,
  another task's output) and what **depends on it**.
- Group tasks into **waves** (a.k.a. phases). A wave is a set of tasks that can
  all start at the same time because their dependencies are already satisfied by
  earlier waves.
- Within a wave, every task must be **independent** of the others in that same
  wave (no shared-file write conflicts, no ordering requirement). These are the
  tasks the implementing agent can dispatch to **parallel subagents**.
- Tasks that touch the same file/region, or that consume another task's output,
  belong in **later waves** or must be marked sequential.
- Prefer maximizing the number of independent tasks per wave, but never create
  false parallelism that would cause merge conflicts or rework.

## Step 3 — Write the plan (spec-grade)

Produce the plan in Markdown using the structure below. Be specific and
prescriptive: name files to create/edit, function/type signatures, routes,
schema columns, and acceptance criteria. Avoid vague verbs like "handle" or
"update" without saying exactly what changes.

```markdown
# Implementation Plan: <concise title>

## 1. Objective
<1–3 sentences: what we're building and why.>

## 2. Background & Context
<Relevant existing architecture, conventions, and constraints. Cite concrete
files, e.g. `lib/db/neon/folders.ts`, and project commands (build/lint/test).>

## 3. Requirements (Specification)
### Functional
- <Numbered, testable requirements.>
### Non-functional
- <Performance, security, accessibility, auth/ownership, backward compatibility,
  observability, etc., as applicable.>

## 4. Assumptions & Decisions
- <Resolved ambiguities and the choices made, including anything confirmed with
  the user.>

## 5. Out of Scope
- <Explicitly list what this plan does NOT cover, to prevent scope creep.>

## 6. Affected Areas
- <Files/directories/modules that will be created or changed, with a one-line
  note on each.>

## 7. Task Breakdown by Wave
> Tasks within the same wave are independent and SHOULD be run in parallel by
> separate subagents. Each new wave starts only after the previous wave is
> complete, because it depends on the previous wave's output.

### Wave 1 — <theme> (parallelizable)
- [ ] **T1.1 — <task title>**
  - Depends on: none
  - Files: <exact paths>
  - Details: <exact changes, signatures, behavior, edge cases>
  - Acceptance: <how to verify this task is done correctly>
- [ ] **T1.2 — <task title>**  *(independent of T1.1 — safe to run in parallel)*
  - Depends on: none
  - Files: <exact paths — must NOT overlap with T1.1>
  - Details: ...
  - Acceptance: ...

### Wave 2 — <theme> (depends on Wave 1)
- [ ] **T2.1 — <task title>**
  - Depends on: T1.1, T1.2
  - Files: ...
  - Details: ...
  - Acceptance: ...

<Add waves as needed. Within each wave, explicitly note independence so the
implementing agent knows what is safe to parallelize.>

## 8. Parallelization Summary
- Wave 1: T1.1, T1.2 — run concurrently (N subagents).
- Wave 2: T2.1 — sequential after Wave 1.
- Critical path: <the longest dependency chain that bounds total time>.
- Shared-file cautions: <list any files multiple tasks touch and how they're
  sequenced to avoid conflicts>.

## 9. Verification & Acceptance
- Commands to run (use the project's real commands, e.g. `npm run lint`,
  `npm run build`, tests if they exist).
- Definition of done for the whole effort.
- Manual/QA checks if relevant.

## 10. Risks & Rollback
- <Key risks, migration/expand-contract concerns, and how to back out.>

## 11. Manual / Human Actions Required (out-of-band)
> Anything a human must do in an environment the implementing agent cannot reach
> — prod/staging dashboards, secret/env stores (e.g. Vercel), DNS, third-party
> consoles, or one-off prod migrations/backfills. The agent CANNOT perform these,
> so they must be recorded explicitly, never silently assumed.
- [ ] **[BEFORE DEPLOY] <action>** — Where: <environment/console> · What: <exact
  step> · Why: <code that depends on it> · Verify: <how to confirm>
- [ ] **[AFTER DEPLOY] <action>** — Where/What/Why/Verify as above.
```

Rules for a good plan:

- **Self-contained:** the implementing agent should be able to execute it without
  re-deriving project conventions. Inline the important details.
- **Concrete over abstract:** real paths, real signatures, real commands.
- **Respect project conventions:** mirror the layering, naming, and workflow you
  observed in Step 1 (including any `AGENTS.md`/custom instructions and ADRs).
- **Backward compatibility:** for schema/API/data-model changes, prefer
  expand-then-contract and call it out explicitly.
- **Every task has acceptance criteria.** No task is "done" without a check.
- **Surface human-only actions.** Capture anything a human must do out-of-band
  (prod secrets/env vars, dashboards, DNS, one-off prod migrations) in section 11,
  and also seed a root `MANUAL_ACTIONS.md` ledger with those entries so the
  implementing agent and the user share one live checklist.

## Step 4 — Optionally save the plan as an artifact

Offer to save the plan to a Markdown file so it can be version-controlled or
handed off as a file (for example `IMPLEMENTATION_PLAN.md` at the repo root, or a
path the user specifies). If the user agrees, write it there. Otherwise keep it
in the conversation. Either way, you must still complete Step 5.

## Step 5 — Print the exact handoff prompt (required, always last)

End your response by printing a single fenced code block containing the **exact
prompt the user will paste into the implementing AI agent**. This is the most
important deliverable — make it copy-paste ready and self-contained.

The handoff prompt MUST:

- Tell the agent its mission and point it at the plan. If you saved the plan to a
  file, reference that path (e.g., "Read and follow `IMPLEMENTATION_PLAN.md`").
  If you did **not** save it to a file, **inline the entire plan** inside the
  prompt so it stands alone.
- Explicitly instruct the agent to **execute the waves in order**, and to **spawn
  parallel subagents for the independent tasks within each wave** to speed up
  delivery, then wait for a wave to finish before starting the next.
- Restate the **verification/acceptance** commands and the definition of done.
- Tell the agent to ask clarifying questions only if it hits a genuine blocker;
  otherwise proceed autonomously.

Use this template for the handoff prompt (fill in the brackets; inline the plan
if it wasn't saved to a file):

```text
You are an implementing AI coding agent. Your task is to execute the
implementation plan described below to completion.

PLAN SOURCE:
<Either: "Read and follow the plan in `IMPLEMENTATION_PLAN.md`."
 Or: paste the full plan here so this prompt is self-contained.>

EXECUTION INSTRUCTIONS:
1. Execute the plan wave by wave, in order. Do not start a wave until the
   previous wave is fully complete and verified.
2. Within each wave, the tasks are independent. Dispatch them to PARALLEL
   subagents (one per task) to finish faster, then collect their results before
   moving to the next wave.
3. Honor the dependency notes and shared-file cautions in the plan exactly; never
   let two parallel tasks edit the same file region.
4. Follow this project's conventions (see AGENTS.md / custom instructions and the
   patterns cited in the plan).
5. After each wave and at the end, run the verification commands:
   <e.g., `npm run lint` and `npm run build`> and ensure they pass.
6. The work is done when every task's acceptance criteria are met and the overall
   Definition of Done in the plan is satisfied.
7. Record any action a human must take in an environment you cannot reach (prod
   secrets/env vars, dashboards, DNS, one-off prod migrations) in a root
   `MANUAL_ACTIONS.md` ledger and make the code degrade gracefully without it;
   never block waiting on it.

Begin with Wave 1 now. Ask a clarifying question only if you hit a genuine
blocker; otherwise proceed autonomously.
```

After printing the handoff prompt, give the user a one-line note telling them they
can paste it into a fresh agent session (and that parallel subagent execution may
require enabling fleet/subagent mode in their agent of choice).
