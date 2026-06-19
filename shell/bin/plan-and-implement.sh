#!/usr/bin/env bash
#
# plan-and-implement.sh
#   1) Runs Copilot with the `implementation-planner` skill on your prompt and
#      captures the handoff prompt it produces.
#   2) Runs a second Copilot session with the `plan-implementer` skill, fed that
#      handoff prompt, to build the plan.
#
# Both sessions run unattended (--autopilot --yolo --no-ask-user). The whole run
# is wrapped in macOS `caffeinate` so the machine stays awake until it finishes.
#
# Usage:
#   ./plan-and-implement.sh "Add CSV export to the reports page"
#   echo "Add CSV export..." | ./plan-and-implement.sh
#
# Optional env vars:
#   REPO_DIR=/path/to/repo            # repo to work in (default: current dir)
#   PLAN_FILE=IMPLEMENTATION_PLAN.md  # where the plan is saved (default shown)
#   PLAN_MODEL=claude-opus-4.8        # model for the PLANNING session
#   PLAN_EFFORT=max                   # planning reasoning effort (none|low|medium|high|xhigh|max)
#   PLAN_CONTEXT=long_context         # planning context tier (default | long_context = 1M)
#   IMPL_MODEL=gpt-5.5                # model for the IMPLEMENTATION session
#   IMPL_EFFORT=xhigh                 # implement reasoning effort (none|low|medium|high|xhigh|max)
#   IMPL_CONTEXT=long_context         # implement context tier (default | long_context = 1M)
#   IMPL_MAX_CONTINUES=30             # raise autopilot continuations for the long
#                                     # implement run (default: CLI default of 5)
#   MANUAL_ACTIONS_FILE=MANUAL_ACTIONS.md  # ledger of human-only steps (surfaced at end)
#   NO_CAFFEINATE=1                   # skip the caffeinate wrapper
#
set -euo pipefail

# ---- keep the machine awake for the whole run (macOS) -----------------------
# Re-exec the script under `caffeinate` once; -i = no idle sleep, -s = no system
# sleep. caffeinate holds the wake lock until this script exits.
if [[ -z "${NO_CAFFEINATE:-}" && -z "${_CAFFEINATED:-}" ]] && command -v caffeinate >/dev/null 2>&1; then
  export _CAFFEINATED=1
  exec caffeinate -i -s "$0" "$@"
fi

usage() { echo "Usage: $0 \"<request prompt>\"   (or pipe the prompt via stdin)" >&2; exit 1; }

# ---- input: prompt from $1 or stdin -----------------------------------------
PROMPT="${1:-}"
if [[ -z "$PROMPT" && ! -t 0 ]]; then PROMPT="$(cat)"; fi
[[ -n "$PROMPT" ]] || usage

command -v copilot >/dev/null 2>&1 || { echo "ERROR: copilot CLI not found in PATH" >&2; exit 1; }

REPO_DIR="${REPO_DIR:-$PWD}"
PLAN_FILE="${PLAN_FILE:-IMPLEMENTATION_PLAN.md}"
MANUAL_ACTIONS_FILE="${MANUAL_ACTIONS_FILE:-MANUAL_ACTIONS.md}"
PLAN_MODEL="${PLAN_MODEL:-claude-opus-4.8}"
PLAN_EFFORT="${PLAN_EFFORT:-max}"
PLAN_CONTEXT="${PLAN_CONTEXT:-long_context}"
IMPL_MODEL="${IMPL_MODEL:-gpt-5.5}"
IMPL_EFFORT="${IMPL_EFFORT:-xhigh}"
IMPL_CONTEXT="${IMPL_CONTEXT:-long_context}"
IMPL_EXTRA="${IMPL_MAX_CONTINUES:+--max-autopilot-continues $IMPL_MAX_CONTINUES}"

WORK_DIR="$(mktemp -d)"
HANDOFF_FILE="$WORK_DIR/handoff-prompt.txt"
trap 'rm -rf "$WORK_DIR"' EXIT

COMMON_FLAGS=(--autopilot --yolo --no-ask-user --no-color -C "$REPO_DIR")
# Extra flags for the PLANNING session only: model / reasoning effort / context tier
PLAN_FLAGS=(--model "$PLAN_MODEL" --effort "$PLAN_EFFORT" --context "$PLAN_CONTEXT")
# Extra flags for the IMPLEMENTATION session only: model / reasoning effort / context tier
IMPL_FLAGS=(--model "$IMPL_MODEL" --effort "$IMPL_EFFORT" --context "$IMPL_CONTEXT")

# ---- 1) planning session ----------------------------------------------------
echo ">>> [1/2] Planning with the implementation-planner skill ..." >&2
PLAN_PROMPT="Use the implementation-planner skill to produce a spec-grade implementation plan for the request below.
Save the plan to ${PLAN_FILE} (relative to the repo root).
Then write ONLY the final handoff prompt (the exact text meant for the implementing agent, with NO surrounding code fence) to this absolute path: ${HANDOFF_FILE}
If the request requires any human-only actions in an environment an agent cannot reach (prod/staging secrets or env vars, dashboards, DNS, third-party consoles, one-off prod migrations/backfills), record them in a root ${MANUAL_ACTIONS_FILE} ledger.
Do NOT write or modify any other code and do NOT create branches; only produce the plan file, the ${MANUAL_ACTIONS_FILE} ledger (only if such actions exist), and the handoff file, then stop.

Request:
${PROMPT}"

copilot "${COMMON_FLAGS[@]}" "${PLAN_FLAGS[@]}" -s -p "$PLAN_PROMPT" | tee "$WORK_DIR/planner.out"

# ---- capture the handoff prompt (file first, stdout fallback) ----------------
if [[ ! -s "$HANDOFF_FILE" ]]; then
  echo ">>> Handoff file empty; extracting last fenced block from planner output ..." >&2
  awk '
    /^```/ { if (inblk) { inblk=0; last=buf; buf="" } else { inblk=1; buf="" }; next }
    inblk { buf = buf $0 "\n" }
    END   { printf "%s", last }
  ' "$WORK_DIR/planner.out" > "$HANDOFF_FILE"
fi

if [[ ! -s "$HANDOFF_FILE" ]]; then
  echo "ERROR: could not obtain a handoff prompt from the planning session." >&2
  exit 2
fi
echo ">>> Handoff prompt captured ($(wc -l < "$HANDOFF_FILE" | tr -d ' ') lines)." >&2

# ---- 2) implement session ---------------------------------------------------
echo ">>> [2/2] Implementing with the plan-implementer skill ..." >&2
HANDOFF="$(cat "$HANDOFF_FILE")"
IMPL_PROMPT="Use the plan-implementer skill to execute the following implementation-plan handoff to completion. Do all work on a new branch, and verify + commit after each wave, pushing after every 3 commits. Record any human-only/out-of-band actions (prod secrets or env vars, dashboards, DNS, one-off prod migrations) in a root ${MANUAL_ACTIONS_FILE} ledger and keep the code safe without them instead of blocking.

${HANDOFF}"

# shellcheck disable=SC2086
copilot "${COMMON_FLAGS[@]}" "${IMPL_FLAGS[@]}" $IMPL_EXTRA -p "$IMPL_PROMPT"

# ---- surface any manual / human actions the agents recorded -----------------
MA_PATH="$REPO_DIR/$MANUAL_ACTIONS_FILE"
if [[ -s "$MA_PATH" ]]; then
  {
    echo
    echo "############################################################"
    echo "##  ACTION REQUIRED — manual/human steps are pending      ##"
    echo "##  see $MANUAL_ACTIONS_FILE (contents below)"
    echo "############################################################"
    cat "$MA_PATH"
    echo "############################################################"
  } >&2
fi

echo ">>> Done. Plan saved at: ${REPO_DIR}/${PLAN_FILE}" >&2
