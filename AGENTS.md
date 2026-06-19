# Agent Instructions

## Dual-language script twins

Every script must exist as a behavior-identical pair at mirrored paths:

- `shell/<path>.sh`: Bash, source of truth for behavior.
- `powershell/<path>.ps1`: PowerShell 7, Windows-first.

Any change to one twin must be applied to the other in the same change/PR. Keep flow, stdout/stderr messages, environment variable names, copilot flags/arguments, prompts, and exit codes in parity.

Platform mechanisms may differ only where necessary, for example:

- `caffeinate` ⇄ `SetThreadExecutionState`
- `ln -s` ⇄ `New-Item -ItemType SymbolicLink` with copy fallback
- `uuidgen` ⇄ `[guid]::NewGuid()`
- `mktemp` + `trap` ⇄ temp dir + `try`/`finally`

| Bash | PowerShell 7 |
|------|--------------|
| `shell/install.sh` | `powershell/install.ps1` |
| `shell/bin/discuss-and-implement.sh` | `powershell/bin/discuss-and-implement.ps1` |
| `shell/bin/plan-and-implement.sh` | `powershell/bin/plan-and-implement.ps1` |

Any new script must be created in both languages at mirrored paths and added to this table. Keep `skills/` language-neutral at the repo root.
