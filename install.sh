#!/bin/sh

set -eu

SCRIPT_NAME=$(basename "$0")
REPO_URL=${PI_INSTALL_REPO_URL:-https://github.com/alnvee/install-pi-dev}
REPO_BRANCH=${PI_INSTALL_REPO_BRANCH:-main}
NOTEBOOKLM_IMAGE_TAG=${NOTEBOOKLM_IMAGE_TAG:-notebooklm/notebooklm-mcp:latest}
NOTEBOOKLM_AUTH_IMAGE_TAG=${NOTEBOOKLM_AUTH_IMAGE_TAG:-notebooklm/notebooklm-auth:latest}
NOTEBOOKLM_AUTH_DIR=${NOTEBOOKLM_AUTH_DIR:-$HOME/.notebooklm-mcp-cli}
DOCKER_MCP_DIR=${DOCKER_MCP_DIR:-$HOME/.docker/mcp}
DOCKER_MCP_PROFILE=${PI_DOCKER_MCP_PROFILE:-default}
INSTALL_DOCKER_COMPONENTS=${PI_INSTALL_DOCKER_COMPONENTS:-0}

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

write_notebooklm_catalog() {
  mkdir -p "$DOCKER_MCP_DIR/catalogs"

  cat > "$DOCKER_MCP_DIR/catalogs/notebooklm.yaml" <<EOF
version: 3
name: notebooklm
displayName: NotebookLM Overlay
registry:
  notebooklm-mcp:
    description: NotebookLM CLI and MCP server packaged for the Docker MCP gateway.
    title: NotebookLM
    type: server
    longLived: true
    dateAdded: "2026-05-09T00:00:00Z"
    image: $NOTEBOOKLM_IMAGE_TAG
    ref: ""
    readme: https://github.com/jacob-bd/notebooklm-mcp-cli/blob/main/docs/MCP_GUIDE.md
    toolsUrl: https://github.com/jacob-bd/notebooklm-mcp-cli/blob/main/docs/MCP_GUIDE.md
    source: https://github.com/jacob-bd/notebooklm-mcp-cli
    upstream: https://github.com/jacob-bd/notebooklm-mcp-cli
    icon: https://raw.githubusercontent.com/jacob-bd/notebooklm-mcp-cli/main/docs/media/header.jpg
    env:
      - name: NOTEBOOKLM_MCP_TRANSPORT
        value: stdio
    volumes:
      - "$NOTEBOOKLM_AUTH_DIR:/root/.notebooklm-mcp-cli"
    prompts: 0
    resources: {}
    metadata:
      owner: alnvee
      category: productivity
      tags:
        - notebooklm
        - ai
        - productivity
      license: MIT License
  notebooklm-auth:
    description: NotebookLM authentication helper exposed as an MCP tool.
    title: NotebookLM Auth
    type: server
    longLived: true
    dateAdded: "2026-05-09T00:00:00Z"
    image: $NOTEBOOKLM_AUTH_IMAGE_TAG
    ref: ""
    readme: https://github.com/jacob-bd/notebooklm-mcp-cli/blob/main/docs/AUTHENTICATION.md
    toolsUrl: https://github.com/jacob-bd/notebooklm-mcp-cli/blob/main/docs/AUTHENTICATION.md
    source: https://github.com/jacob-bd/notebooklm-mcp-cli
    upstream: https://github.com/jacob-bd/notebooklm-mcp-cli
    icon: https://raw.githubusercontent.com/jacob-bd/notebooklm-mcp-cli/main/docs/media/header.jpg
    env:
      - name: NOTEBOOKLM_MCP_TRANSPORT
        value: stdio
    volumes:
      - "$NOTEBOOKLM_AUTH_DIR:/root/.notebooklm-mcp-cli"
    prompts: 0
    resources: {}
    metadata:
      owner: alnvee
      category: productivity
      tags:
        - notebooklm
        - auth
        - productivity
      license: MIT License
EOF
}

write_notebooklm_registry() {
  mkdir -p "$DOCKER_MCP_DIR/registry.d"

  cat > "$DOCKER_MCP_DIR/registry.d/notebooklm.yaml" <<EOF
registry:
  notebooklm-mcp:
    ref: ""
  notebooklm-auth:
    ref: ""
EOF
}

build_notebooklm_image() {
  require_cmd docker

  mkdir -p "$NOTEBOOKLM_AUTH_DIR"

  log "Building NotebookLM MCP image"
  docker build \
    --tag "$NOTEBOOKLM_IMAGE_TAG" \
    --file "$source_dir/docker/notebooklm-mcp/Dockerfile" \
    "$source_dir"

  log "Building NotebookLM auth helper image"
  docker build \
    --tag "$NOTEBOOKLM_AUTH_IMAGE_TAG" \
    --file "$source_dir/docker/notebooklm-auth/Dockerfile" \
    "$source_dir"
}

attach_notebooklm_to_docker_profile() {
  require_cmd docker

  log "Attaching NotebookLM to the Docker MCP profile: $DOCKER_MCP_PROFILE"
  docker mcp profile server add "$DOCKER_MCP_PROFILE" \
    --server "file://$DOCKER_MCP_DIR/catalogs/notebooklm.yaml"
}

verify_notebooklm_tools_visible() {
  require_cmd docker

  log "Verifying NotebookLM tools are visible in the Docker MCP gateway"
  tools_output=$(docker mcp tools ls --format human)

  printf '%s\n' "$tools_output" | grep -F 'notebook_describe - Get AI-generated notebook summary with suggested topics.' >/dev/null || die "NotebookLM summary tool is not visible in the Docker MCP gateway"
  printf '%s\n' "$tools_output" | grep -F 'notebooklm_login' >/dev/null || die "NotebookLM auth tool is not visible in the Docker MCP gateway"
}

normalize_flag() {
  case "$1" in
    1|true|TRUE|yes|YES|on|ON)
      printf '%s\n' 1
      ;;
    *)
      printf '%s\n' 0
      ;;
  esac
}

should_install_docker_components() {
  [ "$(normalize_flag "$INSTALL_DOCKER_COMPONENTS")" -eq 1 ]
}

main() {
  require_cmd npm
  require_cmd node

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --with-docker|--install-docker)
        INSTALL_DOCKER_COMPONENTS=1
        ;;
      --without-docker|--no-docker)
        INSTALL_DOCKER_COMPONENTS=0
        ;;
      -h|--help)
        cat <<EOF
Usage: sh ./install.sh [--with-docker|--install-docker]

By default, the installer only sets up Pi.
Use --with-docker or PI_INSTALL_DOCKER_COMPONENTS=1 to also install the NotebookLM Docker/MCP components.
EOF
        return 0
        ;;
      *)
        die "unknown argument: $1"
        ;;
    esac
    shift
  done

  source_dir=$(resolve_source_dir)
  notebooklm_dockerfile="$source_dir/docker/notebooklm-mcp/Dockerfile"
  notebooklm_auth_dockerfile="$source_dir/docker/notebooklm-auth/Dockerfile"
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

  if should_install_docker_components; then
    require_cmd docker
    [ -f "$source_dir/.mcp.json" ] || die "missing .mcp.json in $source_dir"
    [ -f "$notebooklm_dockerfile" ] || die "missing docker/notebooklm-mcp/Dockerfile in $source_dir"
    [ -f "$notebooklm_auth_dockerfile" ] || die "missing docker/notebooklm-auth/Dockerfile in $source_dir"

    log "Copying MCP config to $HOME/.config/mcp/mcp.json"
    mkdir -p "$HOME/.config/mcp"
    cp -f "$source_dir/.mcp.json" "$HOME/.config/mcp/mcp.json"

    write_notebooklm_catalog
    write_notebooklm_registry
    build_notebooklm_image
    attach_notebooklm_to_docker_profile
    verify_notebooklm_tools_visible
  else
    log "Skipping NotebookLM Docker components (use --with-docker or PI_INSTALL_DOCKER_COMPONENTS=1 to enable)"
  fi

  install_pi_packages "$target_dir/settings.json"
  refresh_pi_packages

  log "Pi installation complete"
}

main "$@"
