#!/usr/bin/env bash
#
# discuss-and-implement.sh
#   The conversational front door to the plan-and-implement pipeline.
#
#   1) Opens an INTERACTIVE Copilot discussion (the `feature-discovery` skill) so you
#      can talk a feature through: explore, ask, decide. Press Ctrl-D when you've
#      reached a decision to end the discussion.
#   2) Resumes that same session headlessly and uses the `feature-definer` skill to
#      write the full feature definition to docs/features/<slug>.md and capture the
#      handoff prompt for the pipeline.
#   3) Feeds that handoff prompt into plan-and-implement.sh, which plans + implements
#      the feature on a new branch and opens a pull request.
#
# Must be run in a real terminal — the discussion is interactive.
#
# Usage:
#   ./discuss-and-implement.sh "Add CSV export to the reports page"
#   ./discuss-and-implement.sh            # prompts you for the feature to discuss
#
# Optional env vars:
#   REPO_DIR=/path/to/repo                  # repo to work in (default: current dir)
#   DISCUSS_MODEL=claude-opus-4.8           # model for the interactive discussion
#   DISCUSS_EFFORT=                         # reasoning effort for discussion (optional)
#   DEFINE_MODEL=claude-opus-4.8            # model for writing the definition
#   PLAN_IMPL_SCRIPT=plan-and-implement.sh  # path to the pipeline script (auto-located)
#   NO_LAUNCH=1                             # stop after writing the definition
#   AUTO_LAUNCH=1                           # skip the confirm prompt and launch immediately
#
set -euo pipefail

usage() { echo "Usage: $0 \"<feature to discuss>\"   (or run with no args to be prompted)" >&2; exit 1; }

command -v copilot >/dev/null 2>&1 || { echo "ERROR: copilot CLI not found in PATH" >&2; exit 1; }
command -v uuidgen >/dev/null 2>&1 || { echo "ERROR: uuidgen not found in PATH" >&2; exit 1; }

REPO_DIR="${REPO_DIR:-$PWD}"
DISCUSS_MODEL="${DISCUSS_MODEL:-claude-opus-4.8}"
DEFINE_MODEL="${DEFINE_MODEL:-claude-opus-4.8}"

# ---- locate the pipeline script: explicit override > PATH > alongside this script
PLAN_IMPL_SCRIPT="${PLAN_IMPL_SCRIPT:-}"
if [[ -z "$PLAN_IMPL_SCRIPT" ]]; then
  if command -v plan-and-implement.sh >/dev/null 2>&1; then
    PLAN_IMPL_SCRIPT="$(command -v plan-and-implement.sh)"
  else
    PLAN_IMPL_SCRIPT="$(cd "$(dirname "$0")" && pwd)/plan-and-implement.sh"
  fi
fi

# ---- input: feature prompt from $1, else ask --------------------------------
PROMPT="${1:-}"
if [[ ! -t 0 ]]; then
  echo "ERROR: discuss-and-implement.sh needs an interactive terminal for the discussion." >&2
  echo "       Run it in a terminal and pass the feature as an argument, e.g.:" >&2
  echo "       $0 \"Add CSV export to the reports page\"" >&2
  exit 1
fi
if [[ -z "$PROMPT" ]]; then
  printf '\033[1;36mWhat feature do you want to discuss and implement?\033[0m\n> '
  IFS= read -r PROMPT || true
fi
[[ -n "${PROMPT//[[:space:]]/}" ]] || { echo "ERROR: no feature provided." >&2; usage; }

# ---- session + handoff plumbing ---------------------------------------------
SID="$(uuidgen)"
WORK_DIR="$(mktemp -d)"
HANDOFF_FILE="$WORK_DIR/handoff-prompt.txt"
trap 'rm -rf "$WORK_DIR"' EXIT

# ---- 1) bold, colorful announcement -----------------------------------------
BOLD=$'\033[1m'; RESET=$'\033[0m'
PINK=$'\033[1;38;5;205m'; CYAN=$'\033[1;38;5;51m'; YEL=$'\033[1;38;5;226m'; GRN=$'\033[1;38;5;46m'
RULE='════════════════════════════════════════════════════════════════'
printf '\n%s%s%s\n' "$PINK" "$RULE" "$RESET"
printf '%s  🎙  FEATURE DISCUSSION SESSION%s\n' "$CYAN" "$RESET"
printf '%s%s%s\n\n' "$PINK" "$RULE" "$RESET"
printf "  %sLet's flesh this out together:%s\n" "$BOLD" "$RESET"
printf "  %s%s%s\n\n" "$YEL" "$PROMPT" "$RESET"
printf "  Discuss freely — Copilot will ask questions and explore the repo.\n"
printf "  %sWhen you've reached a decision, press Ctrl-D%s to lock it in.\n" "$GRN" "$RESET"
printf "  The feature definition is then written and planning + implementation start automatically.\n"
printf '%s%s%s\n\n' "$PINK" "$RULE" "$RESET"
read -r -p "  Press Enter to start the discussion… " _ || true

# ---- 2) interactive discussion (feature-discovery skill) --------------------
SEED="Use the feature-discovery skill to run an interactive feature-discovery discussion with me — you are the conversational front end of the discuss-and-implement pipeline.

Feature to explore: ${PROMPT}

Investigate this repository as needed to ground the conversation, ask me focused questions, surface the key decisions, tradeoffs, and edge cases, and converge on a clear, complete shared understanding. Do NOT write or edit any files and do NOT invoke other skills or start implementing — the discussion itself is the deliverable. When you believe we have reached a clear decision, give me a concise recap of everything we have agreed and remind me that pressing Ctrl-D will lock it in: that ends this session, after which the feature definition will be written from our conversation and planning + implementation will start automatically."

echo ">>> [1/3] Discussion — talk it through, then press Ctrl-D when you've decided." >&2

DISCUSS_FLAGS=(--allow-all-tools -C "$REPO_DIR" --session-id "$SID")
[[ -n "$DISCUSS_MODEL" ]] && DISCUSS_FLAGS+=(--model "$DISCUSS_MODEL")
[[ -n "${DISCUSS_EFFORT:-}" ]] && DISCUSS_FLAGS+=(--effort "$DISCUSS_EFFORT")

set +e
copilot -i "$SEED" "${DISCUSS_FLAGS[@]}"
set -e

# ---- 3) write the definition (headless, resuming the SAME session) ----------
echo ">>> [2/3] Writing the feature definition from our discussion ..." >&2
DEF_PROMPT="Use the feature-definer skill to capture the feature we just discussed in this very session.
Write the full, agreed feature definition to a NEW Markdown file under docs/features/ in this repo (choose a descriptive kebab-case filename), reflecting every decision from our conversation; create the docs/features directory if it does not exist.
Then write ONLY the exact handoff prompt for the plan-and-implement pipeline (the copy-paste text that points at that definition file as the source of truth) to this absolute path, with NO surrounding code fence: ${HANDOFF_FILE}
Do not modify any other code and do not create branches; only create the definition file and write the handoff file, then stop."

DEFINE_FLAGS=(-s --no-color --allow-all-tools --no-ask-user -C "$REPO_DIR" --session-id "$SID")
[[ -n "$DEFINE_MODEL" ]] && DEFINE_FLAGS+=(--model "$DEFINE_MODEL")

copilot -p "$DEF_PROMPT" "${DEFINE_FLAGS[@]}" | tee "$WORK_DIR/definer.out"

# ---- capture the handoff prompt (file first, stdout fallback) ---------------
if [[ ! -s "$HANDOFF_FILE" ]]; then
  echo ">>> Handoff file empty; extracting the last fenced block from the definer output ..." >&2
  awk '
    /^```/ { if (inblk) { inblk=0; last=buf; buf="" } else { inblk=1; buf="" }; next }
    inblk { buf = buf $0 "\n" }
    END   { printf "%s", last }
  ' "$WORK_DIR/definer.out" > "$HANDOFF_FILE"
fi
if [[ ! -s "$HANDOFF_FILE" ]]; then
  echo "ERROR: no feature definition / handoff was produced. Did the discussion end before reaching a decision?" >&2
  exit 2
fi

echo "" >&2
echo ">>> Feature definition written. Handoff prompt for plan-and-implement:" >&2
sed 's/^/    /' "$HANDOFF_FILE" >&2
echo "" >&2

# ---- 4) launch plan-and-implement.sh with the handoff -----------------------
if [[ -n "${NO_LAUNCH:-}" ]]; then
  echo ">>> NO_LAUNCH set — stopping after the definition. The definition file is saved in the repo;" >&2
  echo "    pass the handoff prompt above to plan-and-implement.sh when you're ready." >&2
  exit 0
fi

if [[ -z "${AUTO_LAUNCH:-}" ]]; then
  read -r -p ">>> Launch plan-and-implement now? [Y/n] " ans || true
  if [[ "${ans:-}" =~ ^[Nn] ]]; then
    echo ">>> Stopped before implementation. The definition is saved in the repo; re-run" >&2
    echo "    plan-and-implement.sh with the handoff prompt above when ready." >&2
    exit 0
  fi
fi

echo ">>> [3/3] Handing off to plan-and-implement.sh ..." >&2
HANDOFF="$(cat "$HANDOFF_FILE")"
if [[ -x "$PLAN_IMPL_SCRIPT" ]]; then
  REPO_DIR="$REPO_DIR" "$PLAN_IMPL_SCRIPT" "$HANDOFF"
elif [[ -f "$PLAN_IMPL_SCRIPT" ]]; then
  REPO_DIR="$REPO_DIR" bash "$PLAN_IMPL_SCRIPT" "$HANDOFF"
else
  echo "ERROR: plan-and-implement script not found at: $PLAN_IMPL_SCRIPT" >&2
  echo "       Set PLAN_IMPL_SCRIPT=/path/to/plan-and-implement.sh and retry." >&2
  exit 1
fi
