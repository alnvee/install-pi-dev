#!/bin/sh

set -eu

SCRIPT_NAME=$(basename "$0")
DRY_RUN=${PI_INSTALL_DRY_RUN:-0}
FORCE=${PI_INSTALL_FORCE:-0}
PI_PACKAGE="@earendil-works/pi-coding-agent"
LEGACY_PI_PACKAGES="@mariozechner/pi-coding-agent pi-coding-agent"

log() {
	printf '%s\n' "$*"
}

dry_log() {
	if [ "$DRY_RUN" -eq 1 ]; then
		printf '[DRY-RUN] %s\n' "$*"
	else
		log "$*"
	fi
}

die() {
	printf '%s: %s\n' "$SCRIPT_NAME" "$*" >&2
	exit 1
}

require_cmd() {
	command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

run() {
	if [ "$DRY_RUN" -eq 1 ]; then
		dry_log "$*"
	else
		"$@"
	fi
}

# Refuse to wipe $HOME/.pi while another pi instance is running -- uninstall
# removes that directory, destroying the running instance's session state.
check_no_running_pi() {
	[ "$FORCE" -eq 1 ] && return 0

	command -v pgrep >/dev/null 2>&1 || return 0

	pids=$(pgrep -x pi 2>/dev/null || true)
	[ -n "$pids" ] || return 0

	# shellcheck disable=SC2086
	die "running pi instance(s) detected (PID: $(printf '%s ' $pids)); uninstall removes \$HOME/.pi which destroys their session state -- close them, or set PI_INSTALL_FORCE=1 (or pass --force) to override"
}

# Mirrors install.sh's packages_from_settings so this script stays
# self-contained (both can be streamed with curl | sh).
packages_from_settings() {
	node - "$1" <<'NODE'
const fs = require('fs');

const settingsPath = process.argv[2];
const settings = JSON.parse(fs.readFileSync(settingsPath, 'utf8'));
const packages = Array.isArray(settings.packages) ? [...new Set(settings.packages.filter(Boolean))] : [];

process.stdout.write(packages.join('\n'));
NODE
}

uninstall_pi_packages() {
	settings_path=$1

	if ! command -v pi >/dev/null 2>&1; then
		log "pi command not found; skipping per-package uninstall"
		return 0
	fi

	packages=$(packages_from_settings "$settings_path")
	[ -n "$packages" ] || return 0

	(
		cd "$HOME"
		printf '%s\n' "$packages" | while IFS= read -r package; do
			[ -n "$package" ] || continue
			dry_log "Uninstalling Pi package: $package"
			run pi uninstall "$package" >/dev/null 2>&1 || true
		done
	)
}

uninstall_global_cli() {
	dry_log "Uninstalling global Pi CLI: $PI_PACKAGE $LEGACY_PI_PACKAGES"
	# shellcheck disable=SC2086 # intentional word-splitting of the package list
	run npm uninstall -g $PI_PACKAGE $LEGACY_PI_PACKAGES >/dev/null 2>&1 || true
}

teardown_notebooklm() {
	if [ -f "$HOME/.pi/scripts/setup-notebooklm.sh" ]; then
		dry_log "Tearing down NotebookLM backend (removes its MCP server from the Docker gateway)"
		run sh "$HOME/.pi/scripts/setup-notebooklm.sh" --remove >/dev/null 2>&1 || true
	fi
}

remove_pi_home() {
	if [ -d "$HOME/.pi" ]; then
		dry_log "Removing $HOME/.pi"
		run rm -rf "$HOME/.pi"
	else
		log "No $HOME/.pi directory to remove"
	fi
}

print_plan() {
	cat <<EOF
Uninstall plan:
  Target: $HOME/.pi

Steps:
  1. Uninstall Pi packages from $HOME/.pi/agent/settings.json (pi uninstall)
  2. Uninstall global Pi CLI (npm uninstall -g $PI_PACKAGE $LEGACY_PI_PACKAGES)
  3. Tear down the NotebookLM backend (remove its MCP server from the Docker gateway, if installed)
  4. Remove $HOME/.pi
EOF
}

usage() {
	cat <<EOF
Usage: sh ./uninstall.sh [OPTIONS]

Removes the Pi CLI and configuration installed by install.sh:
  1. Runs 'pi uninstall' for every package listed in $HOME/.pi/agent/settings.json
  2. Runs 'npm uninstall -g' for the Pi CLI (@earendil-works/pi-coding-agent and legacy names)
  3. Tear down the NotebookLM backend (remove its MCP server from the Docker gateway, if installed)
  4. Removes the $HOME/.pi directory

Options:
  --dry-run, --plan                  Show the uninstall plan without executing
  --force                            Proceed even if another pi instance is running
  -h, --help                         Show this help

Environment variables:
  PI_INSTALL_DRY_RUN                 1 to enable dry-run mode
  PI_INSTALL_FORCE                   1 to proceed even if another pi instance is running

Examples:
  # Preview what would be removed
  sh ./uninstall.sh --dry-run

  # Uninstall Pi
  sh ./uninstall.sh
EOF
}

main() {
	while [ "$#" -gt 0 ]; do
		case "$1" in
		--dry-run | --plan)
			DRY_RUN=1
			;;
		--force)
			FORCE=1
			;;
		-h | --help)
			usage
			return 0
			;;
		*)
			die "unknown argument: $1"
			;;
		esac
		shift
	done

	# Safety: never touch a missing or root HOME.
	if [ -z "${HOME:-}" ] || [ "$HOME" = "/" ]; then
		die "refusing to run: HOME is unset or is /"
	fi

	if [ "$DRY_RUN" -eq 1 ]; then
		print_plan
		return 0
	fi

	check_no_running_pi

	require_cmd node
	require_cmd npm

	settings_path="$HOME/.pi/agent/settings.json"
	if [ -f "$settings_path" ]; then
		uninstall_pi_packages "$settings_path"
	else
		log "No $settings_path found; skipping per-package uninstall"
	fi

	uninstall_global_cli
	teardown_notebooklm
	remove_pi_home

	log "Pi uninstallation complete"
}

main "$@"
