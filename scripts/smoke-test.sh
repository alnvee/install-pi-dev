#!/bin/sh

set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
TMP_DIR_NO_DOCKER=$(mktemp -d)
TMP_HOME_NO_DOCKER="$TMP_DIR_NO_DOCKER/home"
TMP_BIN_NO_DOCKER="$TMP_DIR_NO_DOCKER/bin"
NPM_LOG_NO_DOCKER="$TMP_DIR_NO_DOCKER/npm.log"
PI_LOG_NO_DOCKER="$TMP_DIR_NO_DOCKER/pi.log"

TMP_DIR_DOCKER=$(mktemp -d)
TMP_HOME_DOCKER="$TMP_DIR_DOCKER/home"
TMP_BIN_DOCKER="$TMP_DIR_DOCKER/bin"
NPM_LOG_DOCKER="$TMP_DIR_DOCKER/npm.log"
PI_LOG_DOCKER="$TMP_DIR_DOCKER/pi.log"
DOCKER_LOG="$TMP_DIR_DOCKER/docker.log"

cleanup() {
  rm -rf "$TMP_DIR_NO_DOCKER" "$TMP_DIR_DOCKER"
}

trap cleanup EXIT INT TERM

mkdir -p "$TMP_HOME_NO_DOCKER" "$TMP_BIN_NO_DOCKER" "$TMP_HOME_DOCKER" "$TMP_BIN_DOCKER"

test -f "$ROOT_DIR/.env"
grep -Eq '^NOTEBOOKLM_NOTEBOOK_URL=https://notebooklm\.google\.com/notebook/[^[:space:]]+$' "$ROOT_DIR/.env"

cat > "$TMP_BIN_NO_DOCKER/npm" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$NPM_LOG_NO_DOCKER"
exit 0
EOF

cat > "$TMP_BIN_NO_DOCKER/pi" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$PI_LOG_NO_DOCKER"
exit 0
EOF

chmod +x "$TMP_BIN_NO_DOCKER/npm" "$TMP_BIN_NO_DOCKER/pi"

PATH="$TMP_BIN_NO_DOCKER:$PATH" HOME="$TMP_HOME_NO_DOCKER" PI_INSTALL_SOURCE_DIR="$ROOT_DIR" sh "$ROOT_DIR/install.sh"

test -f "$TMP_HOME_NO_DOCKER/.pi/agent/settings.json"
test ! -e "$TMP_HOME_NO_DOCKER/.pi/settings.json"
test -f "$TMP_HOME_NO_DOCKER/.pi/agent/SYSTEM.md"
test -f "$TMP_HOME_NO_DOCKER/.pi/agent/agents/planner.md"
test -f "$TMP_HOME_NO_DOCKER/.pi/agent/chains/feature.chain.md"
test -f "$TMP_HOME_NO_DOCKER/.pi/agent/extensions/subagent/config.json"
test -f "$TMP_HOME_NO_DOCKER/.pi/agent/skills/alnvee/mcp/SKILL.md"
test ! -e "$TMP_HOME_NO_DOCKER/.pi/skills"
test ! -e "$TMP_HOME_NO_DOCKER/.config/mcp/mcp.json"
test ! -e "$TMP_HOME_NO_DOCKER/.docker/mcp/catalogs/notebooklm.yaml"
test ! -e "$TMP_HOME_NO_DOCKER/.docker/mcp/registry.d/notebooklm.yaml"

expected_packages=$(node -e '
const fs = require("fs");
const settings = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
process.stdout.write((settings.packages || []).join("\n"));
' "$ROOT_DIR/.pi/agent/settings.json")

grep -Fx 'uninstall -g @mariozechner/pi-coding-agent @earendil-works/pi-coding-agent pi-coding-agent' "$NPM_LOG_NO_DOCKER" >/dev/null
grep -Fx 'install -g @earendil-works/pi-coding-agent' "$NPM_LOG_NO_DOCKER" >/dev/null

for package in $expected_packages; do
  grep -Fx "uninstall $package" "$PI_LOG_NO_DOCKER" >/dev/null
  grep -Fx "install $package" "$PI_LOG_NO_DOCKER" >/dev/null
done

grep -Fx 'update' "$PI_LOG_NO_DOCKER" >/dev/null

cat > "$TMP_BIN_DOCKER/npm" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$NPM_LOG_DOCKER"
exit 0
EOF

cat > "$TMP_BIN_DOCKER/pi" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$PI_LOG_DOCKER"
exit 0
EOF

cat > "$TMP_BIN_DOCKER/docker" <<EOF
#!/bin/sh
case "\$*" in
  'mcp tools ls --format human')
    printf '%s\n' '59: - notebook_describe - Get AI-generated notebook summary with suggested topics.'
    printf '%s\n' '70: - notebooklm_login -'
    printf '%s\n' '85: - source_describe - Get AI-generated source summary with keyword chips.'
    exit 0
    ;;
esac
printf '%s\n' "\$*" >> "$DOCKER_LOG"
exit 0
EOF

chmod +x "$TMP_BIN_DOCKER/npm" "$TMP_BIN_DOCKER/pi" "$TMP_BIN_DOCKER/docker"

PATH="$TMP_BIN_DOCKER:$PATH" HOME="$TMP_HOME_DOCKER" PI_INSTALL_SOURCE_DIR="$ROOT_DIR" sh "$ROOT_DIR/install.sh" --with-docker

test -f "$TMP_HOME_DOCKER/.pi/agent/settings.json"
test ! -e "$TMP_HOME_DOCKER/.pi/settings.json"
test -f "$TMP_HOME_DOCKER/.pi/agent/SYSTEM.md"
test -f "$TMP_HOME_DOCKER/.pi/agent/agents/planner.md"
test -f "$TMP_HOME_DOCKER/.pi/agent/chains/feature.chain.md"
test -f "$TMP_HOME_DOCKER/.pi/agent/extensions/subagent/config.json"
test -f "$TMP_HOME_DOCKER/.pi/agent/skills/alnvee/mcp/SKILL.md"
test ! -e "$TMP_HOME_DOCKER/.pi/skills"
test -f "$TMP_HOME_DOCKER/.config/mcp/mcp.json"
test -f "$TMP_HOME_DOCKER/.docker/mcp/catalogs/notebooklm.yaml"
test -f "$TMP_HOME_DOCKER/.docker/mcp/registry.d/notebooklm.yaml"

python -m py_compile "$ROOT_DIR/docker/notebooklm-auth/server.py"

grep -Fx "build --tag notebooklm/notebooklm-mcp:latest --file $ROOT_DIR/docker/notebooklm-mcp/Dockerfile $ROOT_DIR" "$DOCKER_LOG" >/dev/null
grep -Fx "build --tag notebooklm/notebooklm-auth:latest --file $ROOT_DIR/docker/notebooklm-auth/Dockerfile $ROOT_DIR" "$DOCKER_LOG" >/dev/null
grep -Fx "mcp profile server add default --server file://$TMP_HOME_DOCKER/.docker/mcp/catalogs/notebooklm.yaml" "$DOCKER_LOG" >/dev/null
grep -F 'catalogs/notebooklm.yaml' "$TMP_HOME_DOCKER/.config/mcp/mcp.json" >/dev/null
grep -F 'registry.d/notebooklm.yaml' "$TMP_HOME_DOCKER/.config/mcp/mcp.json" >/dev/null

grep -Fx 'uninstall -g @mariozechner/pi-coding-agent @earendil-works/pi-coding-agent pi-coding-agent' "$NPM_LOG_DOCKER" >/dev/null
grep -Fx 'install -g @earendil-works/pi-coding-agent' "$NPM_LOG_DOCKER" >/dev/null

for package in $expected_packages; do
  grep -Fx "uninstall $package" "$PI_LOG_DOCKER" >/dev/null
  grep -Fx "install $package" "$PI_LOG_DOCKER" >/dev/null
done

grep -Fx 'update' "$PI_LOG_DOCKER" >/dev/null

printf '%s\n' "Smoke test passed"
