#!/bin/sh

set -eu

SCRIPT_NAME=$(basename "$0")
REPO_URL=${PI_INSTALL_REPO_URL:-https://github.com/alnvee/install-pi-dev}
REPO_BRANCH=${PI_INSTALL_REPO_BRANCH:-main}
DRY_RUN=${PI_INSTALL_DRY_RUN:-0}
SKIP_CHECKSUM=${PI_INSTALL_SKIP_CHECKSUM:-0}
FORCE=${PI_INSTALL_FORCE:-0}

# Expected SHA256 of the release tarball (update on each release)
# Generate with: curl -sL <archive_url> | sha256sum
RELEASE_TARBALL_SHA256=${PI_INSTALL_RELEASE_SHA256:-}

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

TMP_DIR=

cleanup() {
	if [ -n "$TMP_DIR" ]; then
		run rm -rf "$TMP_DIR"
	fi
}

trap cleanup EXIT INT TERM

# Refuse to wipe $HOME/.pi while another pi instance is running -- the install
# replaces that directory, destroying the running instance's session state.
check_no_running_pi() {
	[ "$FORCE" -eq 1 ] && return 0

	command -v pgrep >/dev/null 2>&1 || return 0

	pids=$(pgrep -x pi 2>/dev/null || true)
	[ -n "$pids" ] || return 0

	# shellcheck disable=SC2086
	die "running pi instance(s) detected (PID: $(printf '%s ' $pids)); install replaces \$HOME/.pi which destroys their session state -- close them, or set PI_INSTALL_FORCE=1 (or pass --force) to override"
}

verify_checksum() {
	file=$1
	expected=$2

	if [ -z "$expected" ]; then
		log "Warning: no expected checksum provided; skipping verification (set PI_INSTALL_RELEASE_SHA256 or use --skip-checksum to suppress)"
		return 0
	fi

	require_cmd sha256sum
	actual=$(sha256sum "$file" | cut -d' ' -f1)

	if [ "$actual" != "$expected" ]; then
		die "checksum mismatch: expected $expected, got $actual"
	fi

	log "Checksum verified: $actual"
}

download_source_dir() {
	require_cmd curl
	require_cmd tar

	[ -n "$REPO_URL" ] || die "PI_INSTALL_REPO_URL is required when no local .pi checkout is available"

	TMP_DIR=$(mktemp -d)
	archive_path="$TMP_DIR/pi-source.tar.gz"
	archive_url="$REPO_URL/archive/refs/heads/$REPO_BRANCH.tar.gz"

	# stdout is the function's return channel (captured by resolve_source_dir), so
	# progress messages go to stderr.
	dry_log "Downloading Pi sources from $archive_url" >&2
	run curl -fsSL "$archive_url" -o "$archive_path"

	if [ "$SKIP_CHECKSUM" -eq 0 ]; then
		verify_checksum "$archive_path" "$RELEASE_TARBALL_SHA256" >&2
	else
		log "Skipping checksum verification (PI_INSTALL_SKIP_CHECKSUM=1)" >&2
	fi

	dry_log "Extracting archive to $TMP_DIR" >&2
	run tar -xzf "$archive_path" -C "$TMP_DIR"

	source_dir=$(find "$TMP_DIR" -mindepth 1 -maxdepth 1 -type d | head -n 1)
	[ -n "$source_dir" ] || die "unable to locate the extracted source tree"

	printf '%s\n' "$source_dir"
}

resolve_source_dir() {
	if [ -n "${PI_INSTALL_SOURCE_DIR:-}" ]; then
		[ -f "$PI_INSTALL_SOURCE_DIR/.pi/agent/settings.json" ] || die "PI_INSTALL_SOURCE_DIR does not contain .pi/agent/settings.json"
		printf '%s\n' "$PI_INSTALL_SOURCE_DIR"
		return
	fi

	if [ -f "./.pi/agent/settings.json" ]; then
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
	[ -n "$packages" ] || return 0

	(
		cd "$HOME"
		printf '%s\n' "$packages" | while IFS= read -r package; do
			[ -n "$package" ] || continue
			dry_log "Uninstalling Pi package: $package"
			run pi uninstall "$package" >/dev/null 2>&1 || true
		done

		printf '%s\n' "$packages" | while IFS= read -r package; do
			[ -n "$package" ] || continue
			dry_log "Installing Pi package: $package"
			run pi install "$package"
		done
	)
}

refresh_pi_packages() {
	command -v pi >/dev/null 2>&1 || die "pi command not found after installation"

	dry_log "Refreshing Pi packages to the latest versions"
	run pi update
}

verify_subagent_layout() {
	install_root=$1

	# Verify core agent structure that comes from the source bundle
	[ -d "$install_root/agent" ] || die "missing agent directory: $install_root/agent"
	[ -f "$install_root/agent/settings.json" ] || die "missing settings.json: $install_root/agent/settings.json"
	[ -f "$install_root/agent/SYSTEM.md" ] || die "missing SYSTEM.md: $install_root/agent/SYSTEM.md"
	# agent/agents and agent/chains are created by pi packages during 'pi install'
}

sync_dir_into_agent_scope() {
	install_root=$1
	dir_name=$2
	legacy_dir="$install_root/$dir_name"
	agent_dir="$install_root/agent/$dir_name"

	dry_log "Syncing $dir_name: $legacy_dir -> $agent_dir"
	run mkdir -p "$agent_dir"

	if [ -d "$legacy_dir" ]; then
		run cp -R "$legacy_dir/." "$agent_dir/"
		run rm -rf "$legacy_dir"
	fi
}

print_plan() {
	cat <<EOF
Installation plan:
  Source: ${PI_INSTALL_SOURCE_DIR:-local .pi or $REPO_URL/$REPO_BRANCH}
  Target: $HOME/.pi
  Dry-run mode: $([ "$DRY_RUN" -eq 1 ] && echo "enabled" || echo "disabled")
  Checksum verification: $([ "$SKIP_CHECKSUM" -eq 0 ] && echo "enabled" || echo "disabled")

Steps:
  1. Uninstall existing Pi CLI packages (@mariozechner/pi-coding-agent, @earendil-works/pi-coding-agent, pi-coding-agent)
  2. Remove existing $HOME/.pi directory
  3. Install Pi CLI (@earendil-works/pi-coding-agent)
  4. Copy .pi bundle to $HOME/.pi
  5. Verify subagent layout
  6. Sync skills to $HOME/.pi/agent/skills
  7. Sync prompts to $HOME/.pi/agent/prompts
  8. Install Pi packages from settings.json
  9. Refresh Pi packages (pi update)
EOF
}

main() {
	require_cmd npm
	require_cmd node
	require_cmd mktemp

	while [ "$#" -gt 0 ]; do
		case "$1" in
		--dry-run | --plan)
			DRY_RUN=1
			;;
		--skip-checksum)
			SKIP_CHECKSUM=1
			;;
		--force)
			FORCE=1
			;;
		-h | --help)
			cat <<EOF
Usage: sh ./install.sh [OPTIONS]

Options:
  --dry-run, --plan                  Show installation plan without executing
  --skip-checksum                    Skip tarball checksum verification
  --force                            Proceed even if another pi instance is running
  -h, --help                         Show this help

Environment variables:
  PI_INSTALL_REPO_URL                GitHub repo URL (default: https://github.com/alnvee/install-pi-dev)
  PI_INSTALL_REPO_BRANCH             Branch to install from (default: main)
  PI_INSTALL_SOURCE_DIR              Local .pi directory to use instead of downloading
  PI_INSTALL_DRY_RUN                 1 to enable dry-run mode
  PI_INSTALL_SKIP_CHECKSUM           1 to skip checksum verification
  PI_INSTALL_FORCE                   1 to proceed even if another pi instance is running
  PI_INSTALL_RELEASE_SHA256          Expected SHA256 of release tarball

Examples:
  # Local install
  sh ./install.sh

  # Dry-run to preview changes
  sh ./install.sh --dry-run

  # Remote install with checksum verification
  PI_INSTALL_RELEASE_SHA256=abc123... curl -fsSL https://raw.githubusercontent.com/alnvee/install-pi-dev/main/install.sh | sh
EOF
			return 0
			;;
		*)
			die "unknown argument: $1"
			;;
		esac
		shift
	done

	if [ "$DRY_RUN" -eq 1 ]; then
		print_plan
		return 0
	fi

	check_no_running_pi

	source_dir=$(resolve_source_dir)
	settings_path="$source_dir/.pi/agent/settings.json"

	[ -f "$settings_path" ] || die "missing .pi/agent/settings.json in $source_dir"

	log "Removing existing Pi CLI package"
	run npm uninstall -g @mariozechner/pi-coding-agent @earendil-works/pi-coding-agent pi-coding-agent >/dev/null 2>&1 || true

	log "Removing existing Pi home directory"
	run rm -rf "$HOME/.pi"

	log "Installing Pi CLI package"
	run npm install -g @earendil-works/pi-coding-agent

	target_dir="$HOME/.pi"
	log "Copying Pi bundle to $target_dir"
	run mkdir -p "$HOME"
	run cp -R "$source_dir/.pi" "$target_dir"

	# Drop dev-machine runtime artifacts that should not ship in the bundle
	# (they are gitignored, so local checkouts would otherwise copy them).
	run rm -rf "$target_dir/sessions" "$target_dir/npm"

	verify_subagent_layout "$target_dir"
	sync_dir_into_agent_scope "$target_dir" skills
	sync_dir_into_agent_scope "$target_dir" prompts

	install_pi_packages "$settings_path"
	refresh_pi_packages

	log "Verifying Pi CLI installation"
	if ! pi_version=$(pi --version 2>&1); then
		die "global install succeeded but 'pi --version' failed; check your node/npm installation, or reinstall @earendil-works/pi-coding-agent manually"
	fi
	log "Pi CLI version: $pi_version"

	log "Pi installation complete"
}

main "$@"
