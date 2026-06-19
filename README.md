# AIDevKit

My personal toolkit for AI-assisted software development with the
[GitHub Copilot CLI](https://github.com/github/copilot-cli) — a set of **skills**
and Bash + PowerShell 7 scripts that turn a rough feature idea into a planned,
implemented, and PR-ready change.

Together they form a four-stage pipeline:

```
  ┌───────────┐     ┌──────────┐     ┌──────────┐     ┌─────────────┐
  │  DISCUSS  │ ──▶ │  DEFINE  │ ──▶ │   PLAN   │ ──▶ │  IMPLEMENT  │
  └───────────┘     └──────────┘     └──────────┘     └─────────────┘
 feature-discovery  feature-definer  implementation-   plan-implementer
   (interactive)    (writes spec)      planner          (branch + PR)
        └──── discuss-and-implement.{sh,ps1} ─────┘
                          └──── plan-and-implement.{sh,ps1} ─────┘
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

### Scripts (`shell/bin/*.sh`, `powershell/bin/*.ps1`)

Bash and PowerShell 7 wrappers that drive the Copilot CLI through the stages end
to end. The PowerShell scripts are behavior-identical twins of the Bash scripts.

| Bash | PowerShell 7 | What it does |
|------|--------------|--------------|
| [`discuss-and-implement.sh`](shell/bin/) | [`discuss-and-implement.ps1`](powershell/bin/) | The full front door: opens an **interactive** discussion (Ctrl-D to finish), writes the feature definition from that session, then hands off to `plan-and-implement`. |
| [`plan-and-implement.sh`](shell/bin/) | [`plan-and-implement.ps1`](powershell/bin/) | Unattended plan → implement: runs `implementation-planner`, captures its handoff, then runs `plan-implementer`. Keeps the machine awake unless `NO_CAFFEINATE=1` is set. |

## Requirements

- [GitHub Copilot CLI](https://github.com/github/copilot-cli) (`copilot` on your `PATH`)
- Bash variant: `bash`, `git`, and `uuidgen`
- Windows/PowerShell variant: PowerShell 7 (`pwsh`) and `git`
- Bash keep-awake uses macOS `caffeinate`; PowerShell keep-awake uses Windows
  `SetThreadExecutionState`. Set `NO_CAFFEINATE=1` to skip keep-awake in either
  variant.
- `gh` (GitHub CLI) recommended so `plan-implementer` can open pull requests

## Installation

Clone the repo, then run the installer for your shell. Both installers link each
skill into `~/.copilot/skills/` and each script into `~/bin/`, so edits here take
effect immediately.

### macOS/Linux (Bash)

```bash
git clone https://github.com/m7mdganem/AIDevKit.git
cd AIDevKit
./shell/install.sh
```

Make sure `~/bin` is on your `PATH` (the installer warns you if it isn't):

```bash
export PATH="$HOME/bin:$PATH"   # add to ~/.zshrc or ~/.bashrc
```

To remove the symlinks again (backups named `*.bak` are left untouched):

```bash
./shell/install.sh --uninstall
```

### Windows/PowerShell

```powershell
git clone https://github.com/m7mdganem/AIDevKit.git
Set-Location AIDevKit
./powershell/install.ps1
```

If your execution policy blocks local scripts, allow trusted local scripts or
unblock this repo's scripts:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
Unblock-File ./powershell/install.ps1, ./powershell/bin/*.ps1
```

Make sure `~/bin` is on your `PATH` (the installer warns you if it isn't):

```powershell
$env:PATH = "$HOME/bin;$env:PATH"   # persist with your PowerShell profile if needed
```

To remove the symlinks again (backups named `*.bak` are left untouched):

```powershell
./powershell/install.ps1 -u
# or
./powershell/install.ps1 --uninstall
```

Prefer not to symlink? Copy `skills/*` into `~/.copilot/skills/`, then copy
`shell/bin/*.sh` or `powershell/bin/*.ps1` into any directory on your `PATH`.

## Usage

### Full pipeline — discuss, then build

Run from inside the target repository (or set `REPO_DIR`). Discuss the feature,
press **Ctrl-D** when you've decided, and the kit defines, plans, implements, and
opens a PR:

```bash
cd ~/path/to/your/repo
discuss-and-implement.sh "Add CSV export to the reports page"
```

PowerShell:

```powershell
Set-Location ~/path/to/your/repo
discuss-and-implement.ps1 "Add CSV export to the reports page"
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

PowerShell:

```powershell
plan-and-implement.ps1 "Add CSV export to the reports page"

# multi-line prompts via stdin
@'
Plan and implement the feature defined in `docs/features/csv-export.md`.
Treat that document as the source of truth.
'@ | plan-and-implement.ps1
```

### Use a skill directly

You don't need the scripts — invoke any skill from a normal Copilot session:

```bash
copilot -i "Use the implementation-planner skill to plan adding CSV export to the reports page."
```

### Useful environment variables

The `plan-and-implement` scripts (and, where relevant, `discuss-and-implement`)
accept overrides, for example:

| Variable | Default | Purpose |
|----------|---------|---------|
| `REPO_DIR` | current dir | Repository to work in |
| `PLAN_MODEL` | `claude-opus-4.8` | Model for the planning session |
| `IMPL_MODEL` | `gpt-5.5` | Model for the implementation session |
| `IMPL_MAX_CONTINUES` | CLI default | Autopilot continuations for long implement runs |
| `NO_CAFFEINATE` | _(unset)_ | Skip keep-awake in either language variant |

See the header comment of each script for the complete list.

## Repository layout

```
AIDevKit/
├── AGENTS.md                    # repo instructions for dual-language script twins
├── shell/                       # Bash installer and scripts (-> ~/bin)
│   ├── install.sh
│   └── bin/
│       ├── discuss-and-implement.sh
│       └── plan-and-implement.sh
├── powershell/                  # PowerShell 7 installer and scripts (-> ~/bin)
│   ├── install.ps1
│   └── bin/
│       ├── discuss-and-implement.ps1
│       └── plan-and-implement.ps1
├── skills/                      # Copilot CLI skills (-> ~/.copilot/skills)
│   ├── feature-discovery/SKILL.md
│   ├── feature-definer/SKILL.md
│   ├── implementation-planner/SKILL.md
│   └── plan-implementer/SKILL.md
├── LICENSE
└── README.md
```

## License

[MIT](LICENSE) © Mohammad Ghanem
