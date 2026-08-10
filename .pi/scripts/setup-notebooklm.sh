#!/bin/sh
#
# Setup the NotebookLM (Gemini Notebook) research backend for the Pi agent.
#
# Installs notebooklm-mcp-cli (the `nlm` CLI + `notebooklm-mcp` server),
# provisions auth, runs the notebooklm-mcp HTTP server on loopback, and
# registers it in the Docker MCP gateway as a remote server so the agent's MCP
# tools can reach it. Shipped in the bundle at ~/.pi/scripts/setup-notebooklm.sh;
# the /nlm extension wraps this script (menu → "Install MCP server in Docker").
#
# Usage: sh setup-notebooklm.sh [--remove]
#
# Env:
#   NOTEBOOKLM_ACCOUNT      Google account (optional) — used as the nlm profile slug
#   NOTEBOOKLM_MCP_PORT     Loopback port for the MCP HTTP server (default 9420)
#   NOTEBOOKLM_MCP_TOKEN    Bearer token for the server; generated if unset
#   NOTEBOOKLM_MCP_PROFILE  Docker MCP gateway profile id to register in (default: default)
#   PI_INSTALL_DRY_RUN      1 to print actions without running them

set -eu

SCRIPT_NAME=$(basename "$0")
DRY_RUN=${PI_INSTALL_DRY_RUN:-0}
PORT=${NOTEBOOKLM_MCP_PORT:-9420}
GATEWAY_PROFILE=${NOTEBOOKLM_MCP_PROFILE:-default}
MCP_TOKEN=${NOTEBOOKLM_MCP_TOKEN:-}
ACCOUNT=${NOTEBOOKLM_ACCOUNT:-}
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/install-pi-dev"
SERVER_YAML="$CONFIG_DIR/notebooklm-mcp.yaml"
ENV_FILE="$CONFIG_DIR/notebooklm-mcp.env"
NLM_HOME="${NLM_HOME:-$HOME/.notebooklm-mcp-cli}"

log() { printf '%s\n' "$*"; }
die() {
	printf '%s: %s\n' "$SCRIPT_NAME" "$*" >&2
	exit 1
}
require_cmd() { command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"; }
run() {
	if [ "$DRY_RUN" -eq 1 ]; then
		log "[DRY-RUN] $*"
	else
		"$@"
	fi
}

usage() {
	cat <<EOF
Usage: sh $SCRIPT_NAME [--remove]

Installs the NotebookLM backend for the Pi agent:
  1. Installs notebooklm-mcp-cli (nlm CLI + notebooklm-mcp server)
  2. Provisions auth (nlm login)
  3. Runs the notebooklm-mcp HTTP server on 127.0.0.1:$PORT (systemd user service)
  4. Registers it in the Docker MCP gateway as a remote server

Options:
  --remove    Tear down: remove the server from the Docker MCP gateway, stop
              the service, and delete the generated config (keeps nlm + auth)
  -h, --help  Show this help

Environment variables:
  NOTEBOOKLM_ACCOUNT       Google account (optional) — becomes the nlm profile slug
  NOTEBOOKLM_MCP_PORT      Loopback port (default 9420)
  NOTEBOOKLM_MCP_TOKEN     Bearer token; auto-generated if unset
  NOTEBOOKLM_MCP_PROFILE   Docker MCP gateway profile (default: default)
  PI_INSTALL_DRY_RUN       1 to print actions without running them
EOF
}

install_backend() {
	if command -v uv >/dev/null 2>&1; then
		log "Installing notebooklm-mcp-cli via uv"
		run uv tool install --force notebooklm-mcp-cli
		BIN_DIR="$HOME/.local/bin"
	elif command -v pipx >/dev/null 2>&1; then
		log "Installing notebooklm-mcp-cli via pipx"
		run pipx install --force notebooklm-mcp-cli
		BIN_DIR="$HOME/.local/bin"
	else
		require_cmd python3
		log "Installing notebooklm-mcp-cli via pip --user"
		run python3 -m pip install --user notebooklm-mcp-cli
		BIN_DIR="$(python3 -c 'import site; print(site.USER_BASE)' 2>/dev/null)/bin"
	fi
	if [ "$DRY_RUN" -eq 1 ]; then
		return 0
	fi

	command -v nlm >/dev/null 2>&1 || command -v "$BIN_DIR/nlm" >/dev/null 2>&1 ||
		die "nlm CLI not found after install (checked PATH and $BIN_DIR); add $BIN_DIR to PATH"
}

nlm_bin() {
	command -v nlm || printf '%s\n' "$BIN_DIR/nlm"
}

provision_auth() {
	bin=$(nlm_bin)
	profile_flag=""
	if [ -n "$ACCOUNT" ]; then
		profile=$(printf '%s' "$ACCOUNT" | tr 'A-Z@.' 'a-z__' | tr -cd 'a-z0-9_-' | sed 's/^[-_]*//' | cut -c1-32)
		[ -n "$profile" ] || profile="default"
		profile_flag="--profile $profile"
	fi

	if [ "$DRY_RUN" -eq 1 ]; then
		log "[DRY-RUN] $bin login --check $profile_flag"
		log "[DRY-RUN] $bin login $profile_flag   # browser sign-in, if not authenticated"
		return 0
	fi

	if "$bin" login --check $profile_flag >/dev/null 2>&1; then
		log "Already authenticated${profile_flag:+ (profile $profile)}; re-mint with 'nlm login' if the session expires"
		return 0
	fi

	log "Opening Google sign-in in your browser (one-time; nlm extracts cookies automatically)"
	# shellcheck disable=SC2086 # profile_flag is intentionally word-split
	if ! run "$bin" login $profile_flag; then
		cat <<EOF
$SCRIPT_NAME: interactive sign-in failed or no display available.
On a headless box, either:
  - export cookies from a logged-in browser and run
      '$bin login --manual --file cookies.txt' $profile_flag, or
  - copy an existing profile directory into $NLM_HOME/profiles from a machine that already signed in.
EOF
		exit 1
	fi
}

start_service() {
	require_cmd openssl
	[ -n "$MCP_TOKEN" ] || MCP_TOKEN=$(openssl rand -hex 32)
	notebooklm_mcp_bin=$(command -v notebooklm-mcp || printf '%s\n' "$BIN_DIR/notebooklm-mcp")

	# Token lives in ONE 0600 env file, referenced by systemd and the nohup
	# fallback alike (never on a command line or in a world-readable unit).
	run mkdir -p "$CONFIG_DIR"
	log "Writing server token to $ENV_FILE (0600)"
	run sh -c "umask 077 && printf 'NOTEBOOKLM_MCP_TOKEN=%s\\n' '$MCP_TOKEN' > '$ENV_FILE'"

	if command -v systemctl >/dev/null 2>&1; then
		UNIT="$HOME/.config/systemd/user/notebooklm-mcp.service"
		log "Installing systemd user service: $UNIT"
		run mkdir -p "$(dirname "$UNIT")"
		run sh -c "cat > '$UNIT' <<EOF
[Unit]
Description=NotebookLM MCP server (loopback HTTP for the Pi agent)
After=network-online.target

[Service]
ExecStart=$notebooklm_mcp_bin --transport http --host 127.0.0.1 --port $PORT
EnvironmentFile=$ENV_FILE
Restart=on-failure

[Install]
WantedBy=default.target
EOF"
		run systemctl --user daemon-reload
		run systemctl --user enable --now notebooklm-mcp
		# Keep the user service alive across logins/reboots (fails without privileges; ignore).
		command -v loginctl >/dev/null 2>&1 && run loginctl enable-linger "$(id -un)" 2>/dev/null || true
	else
		log "systemd not available; starting server in background (restart manually on reboot)"
		run sh -c ". '$ENV_FILE' && nohup '$notebooklm_mcp_bin' --transport http --host 127.0.0.1 --port $PORT >/dev/null 2>&1 &"
	fi
}

register_gateway() {
	require_cmd docker

	log "Writing gateway server entry: $SERVER_YAML"
	run mkdir -p "$CONFIG_DIR"
	run sh -c "umask 077 && cat > '$SERVER_YAML' <<EOF
name: notebooklm
title: NotebookLM (Gemini Notebook)
type: remote
description: Grounded Q&A over the user's NotebookLM research corpus
remote:
  url: http://127.0.0.1:$PORT/mcp
  headers:
    Authorization: Bearer $MCP_TOKEN
EOF"

	log "Registering in Docker MCP gateway profile '$GATEWAY_PROFILE'"
	run docker mcp profile server add "$GATEWAY_PROFILE" --server "file://$SERVER_YAML"

	log "Verifying: docker mcp tools ls | grep -i notebook"
	run docker mcp tools ls | grep -i notebook || true
}

remove_backend() {
	require_cmd docker

	log "Removing 'notebooklm' from Docker MCP gateway profile '$GATEWAY_PROFILE'"
	run docker mcp profile server remove "$GATEWAY_PROFILE" notebooklm >/dev/null 2>&1 || true

	log "Stopping the NotebookLM MCP service"
	if command -v systemctl >/dev/null 2>&1 && [ -f "$HOME/.config/systemd/user/notebooklm-mcp.service" ]; then
		run systemctl --user disable --now notebooklm-mcp >/dev/null 2>&1 || true
		run rm -f "$HOME/.config/systemd/user/notebooklm-mcp.service"
		run systemctl --user daemon-reload >/dev/null 2>&1 || true
	else
		# Kill any loopback notebooklm-mcp server started by this script.
		run pkill -f "notebooklm-mcp --transport http" >/dev/null 2>&1 || true
	fi

	log "Removing generated gateway config"
	run rm -f "$SERVER_YAML" "$ENV_FILE"

	log "NotebookLM MCP server removed."
	log "  Kept: nlm CLI + auth ($NLM_HOME) — still usable via /nlm."
	log "  Fully remove the CLI with: uv tool uninstall notebooklm-mcp-cli"
}

main() {
	MODE=setup
	for arg in "$@"; do
		case "$arg" in
		--remove)
			MODE=remove
			;;
		-h | --help)
			usage
			return 0
			;;
		*)
			die "unknown argument: $arg"
			;;
		esac
	done

	[ "$DRY_RUN" -eq 1 ] && log "[DRY-RUN] Previewing NotebookLM $MODE"

	if [ "$MODE" = "remove" ]; then
		remove_backend
		return 0
	fi

	install_backend
	provision_auth
	start_service
	register_gateway

	log "NotebookLM setup complete."
	log "  Server:    http://127.0.0.1:$PORT/mcp (token in $ENV_FILE)"
	log "  Auth:      $NLM_HOME"
	log "  Quick test: docker mcp tools call notebook_query notebook_id=<your-notebook> question='what is this about?'"
}

main "$@"
