# AIDevKit

My personal toolkit for AI-assisted software development with the
[GitHub Copilot CLI](https://github.com/github/copilot-cli) — a set of **skills**
and **shell scripts** that turn a rough feature idea into a planned, implemented,
and PR-ready change.

Together they form a four-stage pipeline:

```
  ┌───────────┐     ┌──────────┐     ┌──────────┐     ┌─────────────┐
  │  DISCUSS  │ ──▶ │  DEFINE  │ ──▶ │   PLAN   │ ──▶ │  IMPLEMENT  │
  └───────────┘     └──────────┘     └──────────┘     └─────────────┘
 feature-discovery  feature-definer  implementation-   plan-implementer
   (interactive)    (writes spec)      planner          (branch + PR)
        └──────── discuss-and-implement.sh ────────┘
                          └──────── plan-and-implement.sh ────────┘
```

- **Discuss** an idea interactively until it's a clear, shared understanding.
- **Define** that understanding as a spec-grade Markdown feature definition.
- **Plan** the work into dependency-ordered, parallelizable waves.
- **Implement** the plan wave by wave on a branch, verifying and committing, then
  open a pull request.

## What's inside

### Skills (`skills/`)

Copilot CLI skills (each a `SKILL.md`). Once installed they live in
`~/.copilot/skills/` and Copilot loads them on demand.

| Skill | Stage | What it does |
|-------|-------|--------------|
| [`feature-discovery`](skills/feature-discovery/SKILL.md) | Discuss | Runs an interactive, Socratic discussion to turn a rough idea into a complete shared understanding of one feature. Read-only — writes nothing. |
| [`feature-definer`](skills/feature-definer/SKILL.md) | Define | Captures the discussed feature into a spec-grade `docs/features/<slug>.md` and prints the handoff prompt for the pipeline. |
| [`implementation-planner`](skills/implementation-planner/SKILL.md) | Plan | Produces a spec-grade implementation plan organized into dependency-ordered **waves**, marking which tasks can run in parallel, then prints the exact handoff prompt. |
| [`plan-implementer`](skills/plan-implementer/SKILL.md) | Implement | Executes a plan to completion on a dedicated branch — parallel subagents per wave, verify + commit each wave, push every 3 commits, and open a PR. |

### Scripts (`bin/`)

Bash wrappers that drive the Copilot CLI through the stages end to end.

| Script | What it does |
|--------|--------------|
| [`discuss-and-implement.sh`](bin/discuss-and-implement.sh) | The full front door: opens an **interactive** discussion (Ctrl-D to finish), writes the feature definition from that session, then hands off to `plan-and-implement.sh`. |
| [`plan-and-implement.sh`](bin/plan-and-implement.sh) | Unattended plan → implement: runs `implementation-planner`, captures its handoff, then runs `plan-implementer`. Wrapped in `caffeinate` so the machine stays awake. |

## Requirements

- [GitHub Copilot CLI](https://github.com/github/copilot-cli) (`copilot` on your `PATH`)
- `bash`, `git`, and `uuidgen`
- macOS for the `caffeinate` keep-awake wrapper in `plan-and-implement.sh`
  (set `NO_CAFFEINATE=1` to skip it on other platforms)
- `gh` (GitHub CLI) recommended so `plan-implementer` can open pull requests

## Installation

Clone the repo and run the installer. It **symlinks** each skill into
`~/.copilot/skills/` and each script into `~/bin/`, so edits here take effect
immediately:

```bash
git clone https://github.com/m7mdganem/AIDevKit.git
cd AIDevKit
./install.sh
```

Make sure `~/bin` is on your `PATH` (the installer warns you if it isn't):

```bash
export PATH="$HOME/bin:$PATH"   # add to ~/.zshrc or ~/.bashrc
```

To remove the symlinks again (backups named `*.bak` are left untouched):

```bash
./install.sh --uninstall
```

Prefer not to symlink? Copy `skills/*` into `~/.copilot/skills/` and `bin/*.sh`
into any directory on your `PATH` instead.

## Usage

### Full pipeline — discuss, then build

Run from inside the target repository (or set `REPO_DIR`). Discuss the feature,
press **Ctrl-D** when you've decided, and the kit defines, plans, implements, and
opens a PR:

```bash
cd ~/path/to/your/repo
discuss-and-implement.sh "Add CSV export to the reports page"
```

### Plan and implement a known request

Skip the discussion and hand a request straight to the plan → implement pipeline:

```bash
plan-and-implement.sh "Add CSV export to the reports page"

# multi-line prompts via stdin
plan-and-implement.sh <<'EOF'
Plan and implement the feature defined in `docs/features/csv-export.md`.
Treat that document as the source of truth.
EOF
```

### Use a skill directly

You don't need the scripts — invoke any skill from a normal Copilot session:

```bash
copilot -i "Use the implementation-planner skill to plan adding CSV export to the reports page."
```

### Useful environment variables

`plan-and-implement.sh` (and, where relevant, `discuss-and-implement.sh`) accept
overrides, for example:

| Variable | Default | Purpose |
|----------|---------|---------|
| `REPO_DIR` | current dir | Repository to work in |
| `PLAN_MODEL` | `claude-opus-4.8` | Model for the planning session |
| `IMPL_MODEL` | `gpt-5.5` | Model for the implementation session |
| `IMPL_MAX_CONTINUES` | CLI default | Autopilot continuations for long implement runs |
| `NO_CAFFEINATE` | _(unset)_ | Skip the macOS keep-awake wrapper |

See the header comment of each script for the complete list.

## Repository layout

```
AIDevKit/
├── bin/                         # pipeline scripts (-> ~/bin)
│   ├── discuss-and-implement.sh
│   └── plan-and-implement.sh
├── skills/                      # Copilot CLI skills (-> ~/.copilot/skills)
│   ├── feature-discovery/SKILL.md
│   ├── feature-definer/SKILL.md
│   ├── implementation-planner/SKILL.md
│   └── plan-implementer/SKILL.md
├── install.sh                   # symlink installer (./install.sh [--uninstall])
├── LICENSE
└── README.md
```

## License

[MIT](LICENSE) © Mohammad Ghanem
