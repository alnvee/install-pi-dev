#!/bin/sh

set -eu

SCRIPT_NAME=$(basename "$0")
REPO_URL=${PI_INSTALL_REPO_URL:-https://github.com/alnvee/install-pi-dev}
REPO_BRANCH=${PI_INSTALL_REPO_BRANCH:-main}

log() {
  printf '%s\n' "$*"
}

die() {
  printf '%s: %s\n' "$SCRIPT_NAME" "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

TMP_DIR=

cleanup() {
  if [ -n "$TMP_DIR" ]; then
    rm -rf "$TMP_DIR"
  fi
}

trap cleanup EXIT INT TERM

download_source_dir() {
  require_cmd curl
  require_cmd tar

  [ -n "$REPO_URL" ] || die "PI_INSTALL_REPO_URL is required when no local .pi checkout is available"

  TMP_DIR=$(mktemp -d)
  archive_path="$TMP_DIR/pi-source.tar.gz"
  archive_url="$REPO_URL/archive/refs/heads/$REPO_BRANCH.tar.gz"

  log "Downloading Pi sources from $archive_url"
  curl -fsSL "$archive_url" -o "$archive_path"
  tar -xzf "$archive_path" -C "$TMP_DIR"

  source_dir=$(find "$TMP_DIR" -mindepth 1 -maxdepth 1 -type d | head -n 1)
  [ -n "$source_dir" ] || die "unable to locate the extracted source tree"

  printf '%s\n' "$source_dir"
}

resolve_source_dir() {
  if [ -n "${PI_INSTALL_SOURCE_DIR:-}" ]; then
    [ -f "$PI_INSTALL_SOURCE_DIR/.pi/settings.json" ] || die "PI_INSTALL_SOURCE_DIR does not contain .pi/settings.json"
    printf '%s\n' "$PI_INSTALL_SOURCE_DIR"
    return
  fi

  if [ -f "./.pi/settings.json" ]; then
    pwd
    return
  fi

  download_source_dir
}

packages_from_settings() {
  node - "$1" <<'NODE'
const fs = require('fs');

const settingsPath = process.argv[2];
const settings = JSON.parse(fs.readFileSync(settingsPath, 'utf8'));
const packages = Array.isArray(settings.packages) ? [...new Set(settings.packages.filter(Boolean))] : [];

process.stdout.write(packages.join('\n'));
NODE
}

install_pi_packages() {
  settings_path=$1

  command -v pi >/dev/null 2>&1 || die "pi command not found after installation"

  packages=$(packages_from_settings "$settings_path")
  [ -n "$packages" ] || return

  (
    cd "$HOME"
    printf '%s\n' "$packages" | while IFS= read -r package; do
      [ -n "$package" ] || continue
      log "Uninstalling Pi package: $package"
      pi uninstall "$package" >/dev/null 2>&1 || true

      log "Installing Pi package: $package"
      pi install "$package"
    done
  )
}

refresh_pi_packages() {
  command -v pi >/dev/null 2>&1 || die "pi command not found after installation"

  log "Refreshing Pi packages to the latest versions"
  pi update
}

main() {
  require_cmd npm
  require_cmd node

  source_dir=$(resolve_source_dir)
  settings_path="$source_dir/.pi/settings.json"

  [ -f "$settings_path" ] || die "missing .pi/settings.json in $source_dir"

  log "Removing existing Pi CLI package"
  npm uninstall -g @mariozechner/pi-coding-agent @earendil-works/pi-coding-agent pi-coding-agent >/dev/null 2>&1 || true

  log "Removing existing Pi home directory"
  rm -rf "$HOME/.pi"

  log "Installing Pi CLI package"
  npm install -g @earendil-works/pi-coding-agent

  target_dir="$HOME/.pi"
  log "Copying Pi bundle to $target_dir"
  mkdir -p "$HOME"
  cp -R "$source_dir/.pi" "$target_dir"

  install_pi_packages "$target_dir/settings.json"
  refresh_pi_packages

  log "Pi installation complete"
}

main "$@"
