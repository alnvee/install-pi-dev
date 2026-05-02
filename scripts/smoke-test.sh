#!/bin/sh

set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
TMP_DIR=$(mktemp -d)
TMP_HOME="$TMP_DIR/home"
TMP_BIN="$TMP_DIR/bin"
NPM_LOG="$TMP_DIR/npm.log"
PI_LOG="$TMP_DIR/pi.log"

cleanup() {
  rm -rf "$TMP_DIR"
}

trap cleanup EXIT INT TERM

mkdir -p "$TMP_HOME" "$TMP_BIN"

cat > "$TMP_BIN/npm" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$NPM_LOG"
exit 0
EOF

cat > "$TMP_BIN/pi" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$PI_LOG"
exit 0
EOF

chmod +x "$TMP_BIN/npm" "$TMP_BIN/pi"

PATH="$TMP_BIN:$PATH" HOME="$TMP_HOME" PI_INSTALL_SOURCE_DIR="$ROOT_DIR" sh "$ROOT_DIR/install.sh"

test -f "$TMP_HOME/.pi/settings.json"
test -f "$TMP_HOME/.pi/agents/planner.md"
test -f "$TMP_HOME/.pi/prompts/pr.md"

expected_packages=$(node -e '
const fs = require("fs");
const settings = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
process.stdout.write((settings.packages || []).join("\n"));
' "$ROOT_DIR/.pi/settings.json")

grep -Fx 'uninstall -g @mariozechner/pi-coding-agent pi-coding-agent' "$NPM_LOG" >/dev/null
grep -Fx 'install -g @mariozechner/pi-coding-agent' "$NPM_LOG" >/dev/null

for package in $expected_packages; do
  grep -Fx "install $package" "$PI_LOG" >/dev/null
done

printf '%s\n' "Smoke test passed"
