#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
APP_DIR=${OBSIDIAN_NVIM_APP_DIR:-"$HOME/Applications"}
APP=$APP_DIR/ObsidianNvimURI.app
CONTENTS=$APP/Contents
MACOS=$CONTENTS/MacOS
RESOURCES=$CONTENTS/Resources
BUNDLE_ID=io.github.obsidian-nvim.uri
STATE_DIR=${XDG_STATE_HOME:-"$HOME/Library/Application Support/obsidian.nvim"}
PREVIOUS_FILE=$STATE_DIR/uri-handler.previous

usage() {
  cat <<'EOF'
usage: install-macos.sh install [--force]
       install-macos.sh status
       install-macos.sh test
       install-macos.sh uninstall

The installer requires swiftc and duti. Installing replaces the current default
obsidian:// handler; use --force when another application owns the scheme.
EOF
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'install-macos.sh: required command not found: %s\n' "$1" >&2
    exit 127
  fi
}

current_bundle() {
  duti -x obsidian 2>/dev/null | tail -n 1 || true
}

install_handler() {
  force=${1-false}
  current=$(current_bundle)
  if [ -n "$current" ] && [ "$current" != "$BUNDLE_ID" ] && [ "$force" != true ]; then
    printf 'obsidian:// is currently handled by %s; rerun with --force to replace it.\n' "$current" >&2
    exit 1
  fi

  nvim_path=$(command -v "${NVIM:-nvim}" 2>/dev/null || true)
  if [ -z "$nvim_path" ]; then
    printf '%s\n' 'install-macos.sh: nvim was not found; set NVIM to its absolute path' >&2
    exit 127
  fi

  mkdir -p "$MACOS" "$RESOURCES" "$STATE_DIR"
  swiftc "$SCRIPT_DIR/macos/ObsidianNvimURI.swift" -o "$MACOS/ObsidianNvimURI"
  install -m 0755 "$SCRIPT_DIR/obsidian-nvim-uri" "$RESOURCES/obsidian-nvim-uri"
  printf '%s\n' "$nvim_path" >"$RESOURCES/obsidian-nvim-uri.nvim"
  cat >"$CONTENTS/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>ObsidianNvimURI</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>ObsidianNvimURI</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSUIElement</key><true/>
  <key>CFBundleURLTypes</key><array><dict>
    <key>CFBundleTypeRole</key><string>Editor</string>
    <key>CFBundleURLName</key><string>Obsidian URI</string>
    <key>CFBundleURLSchemes</key><array><string>obsidian</string></array>
  </dict></array>
</dict></plist>
EOF

  if [ -n "$current" ] && [ "$current" != "$BUNDLE_ID" ]; then
    printf '%s\n' "$current" >"$PREVIOUS_FILE"
  fi
  codesign --force --deep --sign - "$APP" >/dev/null
  lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
  "$lsregister" -f "$APP"
  duti -s "$BUNDLE_ID" obsidian all
  printf 'Installed obsidian:// handler: %s\n' "$APP"
}

uninstall_handler() {
  current=$(current_bundle)
  if [ "$current" = "$BUNDLE_ID" ] && [ -s "$PREVIOUS_FILE" ]; then
    previous=$(head -n 1 "$PREVIOUS_FILE")
    duti -s "$previous" obsidian all
    printf 'Restored previous obsidian:// handler: %s\n' "$previous"
  elif [ "$current" = "$BUNDLE_ID" ]; then
    printf '%s\n' 'No previous handler was recorded; choose a new default handler manually.' >&2
  fi
  rm -rf "$APP"
  rm -f "$PREVIOUS_FILE"
}

require_command duti
command=${1-status}
case "$command" in
  install)
    require_command swiftc
    require_command codesign
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
    current=$(current_bundle)
    printf 'Current obsidian:// handler: %s\n' "${current:-none}"
    [ "$current" = "$BUNDLE_ID" ]
    ;;
  test) open 'obsidian://choose-vault' ;;
  uninstall) uninstall_handler ;;
  *)
    usage >&2
    exit 2
    ;;
esac
