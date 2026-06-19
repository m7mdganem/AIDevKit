#!/usr/bin/env bash
#
# install.sh — link this kit's skills and scripts into the places the tools expect.
#
#   skills/<name>/  ->  ~/.copilot/skills/<name>   (Copilot CLI skills)
#   bin/*.sh        ->  ~/bin/*.sh                  (pipeline scripts on your PATH)
#
# Symlinks are used so edits in this repo take effect immediately. Anything that
# already exists at a target path is backed up to "<path>.bak" before linking.
#
# Usage:
#   ./install.sh              # install (symlink) everything
#   ./install.sh --uninstall  # remove only the symlinks that point back into this repo
#
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_SRC="$(cd "$REPO_DIR/.." && pwd)/skills"
BIN_SRC="$REPO_DIR/bin"
SKILLS_DEST="$HOME/.copilot/skills"
BIN_DEST="$HOME/bin"

GRN=$'\033[1;32m'; YEL=$'\033[1;33m'; RED=$'\033[1;31m'; DIM=$'\033[2m'; RST=$'\033[0m'
info()  { printf '%s%s%s\n' "$GRN" "$1" "$RST"; }
warn()  { printf '%s%s%s\n' "$YEL" "$1" "$RST"; }
note()  { printf '%s%s%s\n' "$DIM" "$1" "$RST"; }
err()   { printf '%s%s%s\n' "$RED" "$1" "$RST" >&2; }

# link <source> <target>
link() {
  local src="$1" dest="$2"
  if [[ -L "$dest" && "$(readlink "$dest")" == "$src" ]]; then
    note "  = already linked: $dest"
    return
  fi
  if [[ -e "$dest" || -L "$dest" ]]; then
    mv "$dest" "$dest.bak"
    warn "  ~ backed up existing $dest -> $dest.bak"
  fi
  ln -s "$src" "$dest"
  info "  + linked $dest"
}

# unlink <source> <target> — remove target only if it links back into this repo
unlink_one() {
  local src="$1" dest="$2"
  if [[ -L "$dest" && "$(readlink "$dest")" == "$src" ]]; then
    rm "$dest"
    info "  - removed $dest"
  else
    note "  = skipped (not linked here): $dest"
  fi
}

install_all() {
  mkdir -p "$SKILLS_DEST" "$BIN_DEST"

  info "Linking skills -> $SKILLS_DEST"
  for skill in "$SKILLS_SRC"/*/; do
    [[ -d "$skill" ]] || continue
    link "${skill%/}" "$SKILLS_DEST/$(basename "$skill")"
  done

  info "Linking scripts -> $BIN_DEST"
  for script in "$BIN_SRC"/*.sh; do
    [[ -f "$script" ]] || continue
    chmod +x "$script"
    link "$script" "$BIN_DEST/$(basename "$script")"
  done

  echo
  info "Done."
  case ":$PATH:" in
    *":$BIN_DEST:"*) : ;;
    *) warn "Note: $BIN_DEST is not on your PATH. Add this to your shell profile:"
       echo "      export PATH=\"\$HOME/bin:\$PATH\"" ;;
  esac
}

uninstall_all() {
  info "Removing skill links from $SKILLS_DEST"
  for skill in "$SKILLS_SRC"/*/; do
    [[ -d "$skill" ]] || continue
    unlink_one "${skill%/}" "$SKILLS_DEST/$(basename "$skill")"
  done

  info "Removing script links from $BIN_DEST"
  for script in "$BIN_SRC"/*.sh; do
    [[ -f "$script" ]] || continue
    unlink_one "$script" "$BIN_DEST/$(basename "$script")"
  done
  echo
  info "Uninstalled. (Any *.bak backups were left untouched.)"
}

case "${1:-}" in
  --uninstall|-u) uninstall_all ;;
  ""|--install|-i) install_all ;;
  *) err "Usage: $0 [--install | --uninstall]"; exit 1 ;;
esac
