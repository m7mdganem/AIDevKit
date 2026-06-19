---
name: feature-definer
description: Captures an already-discussed feature into a spec-grade feature-definition Markdown file in the repo, then prints the exact, copy-paste-ready prompt to feed to the user's plan-and-implement.sh pipeline (which auto-plans and implements the feature). Use this right after you and the user finish discussing or defining a feature, when they want to hand it off for automated planning and implementation. It writes the full agreed feature definition to a .md file and outputs a short handoff prompt that points the pipeline at that file. It does NOT itself break the work into tasks/waves or write the implementation — that is delegated to the pipeline's implementation-planner and plan-implementer skills.
license: MIT
---

# Feature Definer

Use this skill **after** you and the user have finished discussing a feature. Your
job is to do exactly two things, in order:

1. Write the **full, agreed feature definition** to a Markdown file in the repo — a
   spec-grade source of truth that captures everything the discussion settled.
2. Print the **exact prompt** the user will hand to their `plan-and-implement.sh`
   pipeline. That prompt points the pipeline at the definition file and asks it to
   plan and implement the whole feature.

You are **not** planning tasks/waves and **not** writing code here. The pipeline's
`implementation-planner` skill turns your definition into a wave-by-wave plan, and
its `plan-implementer` skill builds it on a branch and opens a PR. Optimize your
definition to be a complete, unambiguous source of truth so those downstream skills
rarely need to guess or ask follow-ups.

> How the pipeline consumes your output: `plan-and-implement.sh` takes a single
> prompt (CLI arg or stdin) and feeds it to the `implementation-planner` skill as
> the feature **request**. The planner reads the repo (including the file you point
> it at), saves an `IMPLEMENTATION_PLAN.md`, and emits a handoff that the script
> then runs through `plan-implementer`. So your printed prompt only needs to point
> at the definition file and say "do it" — the script already handles planning,
> branching, verification, the PR, and the `MANUAL_ACTIONS.md` ledger.

## Step 1 — Consolidate the discussion and close gaps

1. Restate the feature in one or two sentences to confirm understanding.
2. Gather **every decision** reached during the discussion — scope, behavior, data
   model, API/UX choices, naming, edge-case handling. These agreed decisions are
   the heart of the definition; capture them faithfully, do not silently change
   them.
3. Investigate the repo so the definition reflects how *this* project actually
   works: read `AGENTS.md`/`CLAUDE.md`/`.github/copilot-instructions.md`/custom
   instructions, `CONTRIBUTING.md`, ADRs, and the relevant code, and
   note real file paths, layering, naming conventions, and the project's
   build/lint/test commands. Cite concrete files and symbols.
4. If a **material** decision is still genuinely unresolved (one that changes scope
   or design), ask the user one focused question before writing. Don't re-litigate
   what the discussion already settled.

## Step 2 — Choose the definition file path

- Honor the repo's existing convention for specs/design docs if one exists (e.g. a
  `docs/` tree). Otherwise default to `docs/features/<kebab-slug>.md`, or a path the
  user specifies.
- Derive a descriptive kebab-case slug from the feature title. Confirm the path if
  it's ambiguous, and create parent directories as needed.

## Step 3 — Write the feature definition file (the source of truth)

Write the full definition to that file in Markdown. Keep it a **specification /
definition**, not a task plan: capture the **what** and **why**, and the agreed
**how** at a *design* level, then let the planner derive the tasks and waves. Be
concrete — real file paths, signatures, schema columns, routes, copy, and
acceptance criteria. Use this structure (adapt as the feature needs):

```markdown
# Feature definition: <concise title>

- Status: Proposed (defined, pre-implementation)
- Owner: <user>
- Type: <feature | refactor | bugfix | migration>

## 1. Motivation / problem
<Who needs this and why; the user-facing outcome.>

## 2. Current behavior (baseline)
<How it works today, with cited files/symbols — i.e. what we're changing from.>

## 3. Goals / non-goals
**Goals** — <bulleted, testable outcomes.>
**Non-goals** — <explicitly out of scope, to prevent creep.>

## 4. Agreed decisions
<Every decision settled in the discussion: scope, data model, API shape, UX
behavior, edge cases, naming. This section is the heart of the definition.>

## 5. Proposed design
<The agreed approach at a design level: data model / schema changes, types,
validation, data-access, hooks, UI/UX, and how they fit the project's layering.
Cite concrete files to create/change; include algorithms/pseudocode where it
removes ambiguity. Do NOT pre-break this into implementation waves/tasks.>

## 6. Affected areas
<Files / dirs / modules to create or change, one line each.>

## 7. UX / behavior details
<States, copy, messages, accessibility — anything the implementer must get right.>

## 8. Edge cases & interactions
<Boundary conditions, interactions with existing features, backward compatibility.>

## 9. Data / schema & migration notes
<Columns/tables/enums; expand-then-contract notes; how to generate the migration.>

## 10. Testing & acceptance
<What "done" means; tests to add; the project's real verify commands
(lint / build / test / type-check).>

## 11. Risks, open questions, future work
<Known risks, anything intentionally deferred, possible follow-ups. Note if an ADR
is warranted per the repo's conventions.>
```

Rules for a good definition:

- **Source of truth** — the downstream planner/implementer should rarely need to ask
  follow-ups. Inline the important details.
- **Capture the agreed decisions verbatim** in section 4 — never quietly revise what
  the user already decided.
- **Conventions-aware** — mirror the project's layering, naming, and commands you
  observed (`AGENTS.md`/`CLAUDE.md`/`.github/copilot-instructions.md`, ADRs,
  existing patterns).
- **Concrete over abstract** — real paths, real signatures, real commands.
- **Backward compatibility** — for schema/API/data-model changes, prefer
  expand-then-contract and say so explicitly.
- **Stay a definition** — do not enumerate waves/tasks; that is the planner's job.

After writing, tell the user the exact path you saved the file to.

## Step 4 — Print the handoff prompt for the pipeline (required, always last)

End your response with a single fenced code block containing the **exact prompt the
user will pass to `plan-and-implement.sh`**. The pipeline feeds this prompt to the
`implementation-planner` skill as the feature request, so write it as a request that
points at the definition file as the source of truth. Keep it short — the detail
lives in the file — and don't restate planning/branching/PR/verification mechanics,
which the script already supplies.

Use this template (fill in the real repo-relative path to the file you wrote):

```text
Plan and implement the feature defined in `<path/to/definition>.md`.

That document is the complete, agreed feature definition — read it first and treat
it as the source of truth for scope, decisions, design, and acceptance. Implement
the entire feature end to end, following this repository's conventions (AGENTS.md /
CLAUDE.md / .github/copilot-instructions.md / custom instructions, CONTRIBUTING, ADRs,
and the existing layering and patterns), including every
schema/migration, validation, type, data-access, hook, UI, and test change it
specifies. Run the project's verification commands (lint, build, tests, type-check)
and make them pass. Proceed autonomously; only stop for a genuine blocker or an
unresolved ambiguity.
```

Then add a short usage note showing how to run it. Because the prompt is multi-line,
recommend piping it via stdin:

```bash
plan-and-implement.sh <<'EOF'
<paste the prompt here>
EOF
```

(For a one-line prompt, `plan-and-implement.sh "<prompt>"` also works. Optional env
knobs the script supports include `REPO_DIR`, `PLAN_MODEL`, `IMPL_MODEL`, and
`IMPL_MAX_CONTINUES`.) Remind the user that the pipeline will (1) run
`implementation-planner` to save `IMPLEMENTATION_PLAN.md`, then (2) run
`plan-implementer` to build it on a new branch and open a PR — so pointing it at the
definition file is all the prompt has to do.

## Operating rules

- **Two deliverables, in order:** the **definition file**, then the **handoff
  prompt** (printed last, always).
- **You define; you don't plan waves or implement.** Leave task/wave breakdown to
  the planner and the code to the implementer.
- **Honor the user's decisions.** Capture what was agreed; ask only if something
  material is genuinely unresolved.
- **Make the definition self-contained and conventions-aware** so the downstream
  pipeline runs without follow-up questions.
- **Keep the handoff prompt short and pointed at the file** — let the file carry the
  detail.
