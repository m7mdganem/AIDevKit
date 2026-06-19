---
name: plan-implementer
description: Executes a spec-grade implementation plan to completion — the counterpart to the implementation-planner skill. Use this whenever the user hands you an implementation plan (a saved plan file such as IMPLEMENTATION_PLAN.md, the handoff prompt printed by the implementation-planner skill, or an inlined plan) and asks you to implement, execute, build, carry out, or "do" the plan. It works through the plan wave by wave on a dedicated new branch, spawning parallel subagents for the independent tasks within each wave, upholding core software-engineering principles (SOLID, DRY, KISS, YAGNI, separation of concerns/layering, clean code), and after every wave it verifies (lint, build, tests, and any other project commands) and commits — pushing the branch after every 3 commits, and finally opening a pull request with an appropriate title and description.
license: MIT
---

# Plan Implementer

Your job with this skill is to **execute** an existing implementation plan to
completion — you are the implementing agent the `implementation-planner` skill
writes its handoff prompt for. You are not re-planning the work; you are building
it, cleanly, safely, and fast.

Optimize for four things, in priority order:

1. **Correctness** — every task's acceptance criteria are met and the project's
   verification commands (lint, build, tests, type-check) pass after every wave.
2. **Engineering quality** — the code honors SOLID, DRY, KISS, YAGNI, separation
   of concerns/layering, and clean-code practices, and respects the project's
   existing architecture and conventions.
3. **Speed through parallelism** — independent tasks within a wave are dispatched
   to parallel subagents, never serialized unnecessarily.
4. **A clean, reviewable history** — all work on a dedicated branch, one commit
   per verified wave, pushed regularly, and opened as a pull request for review.

## The execution loop (quick reference)

```
load plan ─▶ create new branch ─▶ baseline check
   └▶ for each wave (in order):
         dispatch independent tasks to parallel subagents (honor shared-file cautions)
         integrate results
         verify: lint + build + tests + plan's commands  ── fix until green ──┐
         commit the wave (only if there are changes) ◀───────────────────────┘
         commits_since_push += 1
         if (total_commits % 3 == 0) push
   └▶ final push of any unpushed commits ─▶ open the pull request ─▶ final report
```

Track this state as you go (a todo list or short scratchpad is fine):
**branch name · current wave · total commits made · commits since last push.**

## Core engineering standards (uphold these throughout)

These apply to **every** task and subagent. Put them in each subagent's prompt.

- **SOLID** — Single Responsibility (each module/function/class does one thing),
  Open/Closed, Liskov substitution, Interface Segregation, Dependency Inversion
  (depend on abstractions, inject dependencies rather than hard-wiring them).
- **DRY / KISS / YAGNI** — remove duplication by extracting shared logic; prefer
  the simplest design that satisfies the spec; do **not** build abstraction,
  config, or features the plan does not call for. Honor the plan's "Out of Scope".
- **Separation of concerns & layering** — keep presentation, domain/business
  logic, and data-access concerns in their proper layers. Match the layering the
  project already uses; if the plan introduces new layers, keep boundaries clean
  and dependencies pointing inward. Don't leak data-access or framework details
  into UI/business code, or vice versa.
- **Clean code** — intention-revealing names, small focused functions, no dead or
  commented-out code, consistent formatting, and comments only where the code
  genuinely needs clarification. Leave each file at least as clean as you found it.
- **Respect the project** — follow `AGENTS.md`/custom instructions, ADRs, the
  linter config, and the naming/structure patterns already in the codebase. Do
  **not** introduce a new dependency, framework, formatter, or pattern unless the
  plan explicitly requires it; prefer the ecosystem tools the project already uses.
- **Security & correctness** — validate inputs, enforce authorization/ownership
  server-side where applicable, handle errors and edge cases the plan lists, and
  never commit secrets or credentials.
- **Tests** — meet the testing requirements in each task's acceptance criteria and
  follow the project's existing test conventions; run the suite as part of
  verification. Add tests the plan asks for — don't gold-plate beyond it.

Balance is the job: be principled and thorough, but resist over-engineering.

## Manual / human actions (out-of-band — never block on these)

Some steps can only be performed by a human in an environment you cannot reach:
setting secrets/env vars in a prod or staging dashboard (e.g. Vercel), DNS or
third-party console changes, rotating credentials, or one-off production
migrations/backfills. The run is unattended, so you must **never stop and wait**
for these. Instead:

- **Record every such action** in a single root `MANUAL_ACTIONS.md` ledger (create
  it if missing; the plan may have seeded it). Append one structured entry per
  action: a timing tag — `[BEFORE DEPLOY]` (blocking) or `[AFTER DEPLOY]`
  (follow-up) — plus **What** (exact step), **Where** (environment/console),
  **Why** (the code that needs it), **Verify** (how to confirm), and the wave that
  surfaced it.
- **Keep the code safe without it.** Follow expand/contract: read new config
  through the project's env helper with a sensible fallback or behind a
  feature-flag so a not-yet-set value never crashes the app. Still ship everything
  that *can* be done in code — `.env.example` entries, config templates, migration
  files.
- **Commit `MANUAL_ACTIONS.md`** as part of the wave that introduced the need.
- **Summarize the outstanding actions** in your final report so the user sees them.

## Step 1 — Locate and load the plan

Find the plan from whatever the user gave you, in this order:

1. **A plan file** — if the prompt references a path (e.g. "follow
   `IMPLEMENTATION_PLAN.md`"), read that file in full. Prefer this as the source
   of truth.
2. **An inlined plan** — if the full plan is pasted into the prompt, use that.
3. **Neither is clear** — search the repo for an obvious plan file
   (`*PLAN*.md`, `docs/**`); if you still can't find one, **ask the user** where
   the plan is. Do not start implementing without a plan.

Then parse out and internalize: the **Objective**, **Requirements**,
**Assumptions/Decisions**, **Out of Scope**, the **Task Breakdown by Wave**
(tasks, their `Depends on`, `Files`, `Details`, `Acceptance`), the
**Parallelization Summary** (including **shared-file cautions** and the critical
path), and the **Verification & Acceptance** commands. These drive everything
below.

## Step 2 — Create the working branch (always, first thing you change)

All work happens on a **new, dedicated branch** — never commit to `main`,
`master`, or the repository's default/protected branch.

1. Run `git status` to confirm the working tree state. If there are unrelated
   uncommitted changes, ask the user how to proceed (stash, include, or abort)
   rather than sweeping them into your commits.
2. Choose a descriptive branch name. Follow the repo's branch-naming convention
   if one exists (check `AGENTS.md`, contributing docs, or existing branch names —
   e.g. a required username or `feature/` prefix); otherwise default to a concise
   kebab-case slug derived from the plan title, e.g. `feature/<plan-slug>`.
3. Create and switch to it: `git checkout -b <branch>` (branch from the current
   up-to-date HEAD unless the plan/user says otherwise). Record the branch name in
   your tracked state.

## Step 3 — Establish a green baseline and confirm the commands

Before changing code, learn the project's **real** commands and starting state so
you never blame a pre-existing failure on your work, and never invent tooling:

- Take the verification commands primarily from the plan's "Verification &
  Acceptance" section. Cross-check against `package.json` scripts, `Makefile`,
  `pyproject.toml`, CI config, and `AGENTS.md`/README.
- Run the lint/build/test commands once now to capture the baseline. If something
  is already failing before you touch anything, note it and proceed — your bar is
  "no **new** failures," and all plan-specified checks must pass for your waves.

## Step 4 — Execute the plan wave by wave

Process waves **strictly in order**. Do not start a wave until the previous wave
is fully implemented, verified, and committed.

For each wave:

1. **Identify the independent tasks** in this wave from the plan and the
   Parallelization Summary. Within a wave the plan guarantees the tasks are
   independent (no shared-file writes, no ordering requirement).
2. **Dispatch one subagent per independent task, in parallel**, when there are two
   or more. For a single-task wave, just do it directly. Give each subagent a
   **complete, self-contained** prompt containing:
   - the exact task (title, `Files`, `Details`, `Acceptance` from the plan),
   - the **Core engineering standards** above,
   - the project conventions/commands it must follow,
   - an explicit boundary: it may edit **only** its assigned files/region and must
     not touch another task's files (honor the plan's shared-file cautions), and
   - a request to report back a concise summary of what it changed.
3. **Never let two parallel tasks edit the same file or region.** If the plan
   reveals an overlap, sequence those tasks (split across waves or run them
   one-after-another) instead of in parallel.
4. **Integrate** the subagents' results, resolving any seams between them
   (imports, shared types, wiring), and confirm each task's acceptance criteria
   are actually satisfied.

If a wave has no parallelism, implement it yourself following the same standards.

## Step 5 — Verify the wave (before any commit)

After integrating a wave, run the full verification set and make it **green**:

- Run the project's lint, build, type-check, and test commands — at minimum the
  ones in the plan's Verification section plus the standard project commands.
- If anything fails, **fix it** (directly, or dispatch a focused fix subagent) and
  re-run until everything passes. **Do not commit broken or unverified code.**
- Confirm each task in the wave meets its acceptance criteria.

If you hit a genuine blocker you cannot resolve (ambiguous spec, environmental
failure, contradictory requirement), stop and ask the user rather than committing
a broken or guessed result.

## Step 6 — Commit the wave

Once the wave is green:

- Review what changed (`git status`, `git diff --stat`) and stage it
  (`git add -A`, or stage precisely). If the wave produced **no** changes, skip the
  commit — never create empty commits.
- Make **exactly one commit for the wave** with a clear, conventional message that
  follows the repo's commit style and summarizes the wave's outcome, e.g.:

  ```text
  feat(<area>): <wave theme> (Wave N)

  - <key change 1>
  - <key change 2>
  Implements Wave N of <plan title>; lint/build/tests pass.
  ```

  Follow the host environment's commit conventions, including any required
  trailers (such as a `Co-authored-by:` line) the environment specifies.
- Increment your **total commits** and **commits-since-last-push** counters.

## Step 7 — Push after every 3 commits

- After every **3rd** commit (commit #3, #6, #9, …), push the branch. On the first
  push set upstream: `git push -u origin <branch>`; afterwards `git push`. Reset
  your commits-since-last-push counter.
- When all waves are complete, do a **final push of any remaining unpushed
  commits**, even if you haven't reached the next multiple of 3, so nothing is left
  only on your machine.
- If a push is rejected (e.g. the remote moved), pull/rebase as appropriate, keep
  the tree green, and re-push.

## Step 8 — Open the pull request

After the final push, **open a pull request** for the branch so the work is ready
for review — don't wait to be asked:

- **Target the right base.** Open the PR against the branch you branched from —
  normally the repository's default/protected branch (`main`/`master`). Never
  target your own working branch.
- **Use the project's tooling.** Prefer the GitHub CLI (`gh pr create`). If the
  remote isn't GitHub or `gh` is unavailable/unauthenticated, fall back to the
  host's PR mechanism (the compare URL printed by `git push`, or the platform's
  API). If you genuinely cannot create it, print the exact `gh pr create` command
  and the compare URL so the user can open it in one step, and say so in the report.
- **Be idempotent.** If a PR for this branch already exists, reuse/update it
  instead of erroring or opening a duplicate.
- **Write an appropriate title** — follow the repo's PR/commit conventions and
  summarize the plan's *objective* concisely (e.g. `feat(<area>): <plan title>`),
  not just one wave's message.
- **Write a useful description** so a reviewer understands the change without
  reading every commit. Include: a one-paragraph **summary** of the objective and
  approach; a **what changed** list (by wave or area); the **verification** status
  (lint ✅ build ✅ tests ✅ + any plan-specific checks); any outstanding **manual
  actions** (point to `MANUAL_ACTIONS.md`); and **notes / follow-ups** (anything
  deferred, out-of-scope, or risky).

A reliable way to create it with a multi-line body via the GitHub CLI:

```bash
gh pr create --base <default-branch> --head <branch> \
  --title "<conventional PR title>" \
  --body "$(cat <<'EOF'
## Summary
<one-paragraph objective + approach>

## What changed
- Wave 1: <theme>
- Wave 2: <theme>

## Verification
lint ✅ · build ✅ · tests ✅ <+ plan-specific checks>

## Manual actions
<none | see MANUAL_ACTIONS.md: N item(s)>

## Notes / follow-ups
<anything deferred, out-of-scope, or risky>
EOF
)"
```

Capture the resulting **PR URL** to include in your final report.

## Step 9 — Final report and handoff

When every wave is done, verified, committed, the branch is fully pushed, and the
pull request is open, give the user a concise summary:

```text
Implemented: <plan title>
Branch: <branch name> (pushed)
Pull request: <PR URL>
Waves completed: N/N
Commits: <count>  ·  Pushes: <count>
Verification: lint ✅  build ✅  tests ✅  (+ any plan-specific checks)
Manual actions: <N item(s) in MANUAL_ACTIONS.md, e.g. "set 2 prod env vars"> | none
Notes / follow-ups: <anything deferred, out-of-scope, or risky>
```

If you could not open the PR automatically, include the ready-to-run
`gh pr create` command (or compare URL) here so the user can open it in one step.

## Operating rules

- **Stay in scope.** Build exactly what the plan specifies — no more (YAGNI), no
  less. If reality contradicts the plan, surface it to the user instead of silently
  diverging.
- **Order is sacred.** Waves run in dependency order; tasks within a wave run in
  parallel only when the plan marks them independent.
- **Green before commit, commit before moving on, push every 3.** Never commit
  unverified code; never leave the final commits unpushed.
- **One dedicated branch**, never the default/protected branch.
- **Finish with a pull request.** After the final push, open a PR with an
  appropriate title and description — don't wait to be asked.
- **Never block on human-only actions.** Record them in `MANUAL_ACTIONS.md`, keep
  the code safe without them, and keep going.
- **Proceed autonomously**; ask the user only at a genuine blocker or an
  unresolvable ambiguity.
