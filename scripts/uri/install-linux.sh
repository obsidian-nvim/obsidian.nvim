#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
ROOT_DIR=$(CDPATH='' cd -- "$SCRIPT_DIR/../.." && pwd)
BIN_DIR=${XDG_BIN_HOME:-"$HOME/.local/bin"}
DATA_HOME=${XDG_DATA_HOME:-"$HOME/.local/share"}
STATE_HOME=${XDG_STATE_HOME:-"$HOME/.local/state"}
LAUNCHER=$BIN_DIR/obsidian-nvim-uri
DESKTOP_DIR=$DATA_HOME/applications
DESKTOP_ID=obsidian-nvim-uri.desktop
DESKTOP_FILE=$DESKTOP_DIR/$DESKTOP_ID
STATE_DIR=$STATE_HOME/obsidian.nvim
PREVIOUS_FILE=$STATE_DIR/uri-handler.previous
SCHEME=x-scheme-handler/obsidian

usage() {
  cat <<'EOF'
usage: install-linux.sh install [--force]
       install-linux.sh status
       install-linux.sh test
       install-linux.sh uninstall

Installing replaces the current default obsidian:// handler. Use --force when
another application already owns the scheme.
EOF
}

require_xdg_mime() {
  if ! command -v xdg-mime >/dev/null 2>&1; then
    printf '%s\n' 'install-linux.sh: xdg-mime is required' >&2
    exit 127
  fi
}

current_handler() {
  xdg-mime query default "$SCHEME" 2>/dev/null || true
}

install_handler() {
  force=${1-false}
  current=$(current_handler)
  if [ -n "$current" ] && [ "$current" != "$DESKTOP_ID" ] && [ "$force" != true ]; then
    printf 'obsidian:// is currently handled by %s; rerun with --force to replace it.\n' "$current" >&2
    exit 1
  fi

  nvim_path=$(command -v "${NVIM:-nvim}" 2>/dev/null || true)
  if [ -z "$nvim_path" ]; then
    printf '%s\n' 'install-linux.sh: nvim was not found; set NVIM to its absolute path' >&2
    exit 127
  fi

  mkdir -p "$BIN_DIR" "$DESKTOP_DIR" "$STATE_DIR"
  install -m 0755 "$SCRIPT_DIR/obsidian-nvim-uri" "$LAUNCHER"
  printf '%s\n' "$nvim_path" >"$LAUNCHER.nvim"

  if [ -n "$current" ] && [ "$current" != "$DESKTOP_ID" ]; then
    printf '%s\n' "$current" >"$PREVIOUS_FILE"
  fi

  escaped=$(printf '%s' "$LAUNCHER" | sed 's/[\&|]/\\&/g; s/"/\\"/g')
  sed "s|@LAUNCHER@|\"$escaped\"|" "$ROOT_DIR/data/obsidian-nvim-uri.desktop.in" >"$DESKTOP_FILE"

  if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$DESKTOP_DIR" >/dev/null 2>&1 || true
  fi
  xdg-mime default "$DESKTOP_ID" "$SCHEME"
  printf 'Installed obsidian:// handler: %s\n' "$DESKTOP_FILE"
}

uninstall_handler() {
  current=$(current_handler)
  if [ "$current" = "$DESKTOP_ID" ] && [ -s "$PREVIOUS_FILE" ]; then
    previous=$(head -n 1 "$PREVIOUS_FILE")
    xdg-mime default "$previous" "$SCHEME"
    printf 'Restored previous obsidian:// handler: %s\n' "$previous"
  elif [ "$current" = "$DESKTOP_ID" ]; then
    printf '%s\n' 'No previous handler was recorded; the desktop association may need to be reset manually.' >&2
  fi

  rm -f "$DESKTOP_FILE" "$LAUNCHER" "$LAUNCHER.nvim" "$PREVIOUS_FILE"
  if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$DESKTOP_DIR" >/dev/null 2>&1 || true
  fi
}

require_xdg_mime
command=${1-status}
case "$command" in
  install)
    if [ "${2-}" = "--force" ]; then
      install_handler true
    elif [ -n "${2-}" ]; then
      usage >&2
      exit 2
    else
      install_handler false
    fi
    ;;
  status)
    current=$(current_handler)
    printf 'Current obsidian:// handler: %s\n' "${current:-none}"
    [ "$current" = "$DESKTOP_ID" ]
    ;;
  test)
    if ! command -v xdg-open >/dev/null 2>&1; then
      printf '%s\n' 'install-linux.sh: xdg-open is required for the test' >&2
      exit 127
    fi
    xdg-open 'obsidian://choose-vault'
    ;;
  uninstall) uninstall_handler ;;
  *)
    usage >&2
    exit 2
    ;;
esac
