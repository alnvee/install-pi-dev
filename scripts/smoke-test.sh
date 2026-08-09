#!/bin/sh

set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
TMP_DIR=$(mktemp -d)
TMP_HOME="$TMP_DIR/home"
TMP_BIN="$TMP_DIR/bin"
SOURCE_DIR="$TMP_DIR/source"
SKILL_REPO="$TMP_DIR/skillrepo"
NPM_LOG="$TMP_DIR/npm.log"
PI_LOG="$TMP_DIR/pi.log"
SKILL_MARKER="mattpocock-skills-refresh-marker"

cleanup() {
	rm -rf "$TMP_DIR"
}

trap cleanup EXIT INT TERM

# Fixture upstream repo mimicking github.com/mattpocock/skills
# (archive root containing skills/<bucket>/<name>/SKILL.md).
mkdir -p "$TMP_DIR/fixture/skills/engineering/demo" "$SKILL_REPO/archive/refs/heads"
cat >"$TMP_DIR/fixture/skills/engineering/demo/SKILL.md" <<EOF
---
name: demo
---
$SKILL_MARKER
EOF
tar -czf "$SKILL_REPO/archive/refs/heads/main.tar.gz" -C "$TMP_DIR" fixture

# Working copy of the repo so the refresh step never mutates the real checkout.
cp -R "$ROOT_DIR" "$SOURCE_DIR"
rm -rf "$SOURCE_DIR/.git" "$SOURCE_DIR/.pi/sessions"

mkdir -p "$TMP_HOME" "$TMP_BIN"

cat >"$TMP_BIN/npm" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$NPM_LOG"
exit 0
EOF

cat >"$TMP_BIN/pi" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$PI_LOG"
exit 0
EOF

chmod +x "$TMP_BIN/npm" "$TMP_BIN/pi"

# First install: refresh path. The fake upstream replaces the bundled
# mattpocock skills (engineering/demo) before the bundle is copied.
PATH="$TMP_BIN:$PATH" HOME="$TMP_HOME" PI_INSTALL_SOURCE_DIR="$SOURCE_DIR" \
	PI_MATTPOCOCK_SKILLS_REPO="file://$SKILL_REPO" \
	sh "$ROOT_DIR/install.sh"

test -f "$TMP_HOME/.pi/agent/settings.json"
test ! -e "$TMP_HOME/.pi/settings.json"
test -f "$TMP_HOME/.pi/agent/SYSTEM.md"
test -f "$TMP_HOME/.pi/agent/skills/alnvee/mcp/SKILL.md"
test -d "$TMP_HOME/.pi/agent/prompts"
test ! -e "$TMP_HOME/.pi/skills"
test ! -e "$TMP_HOME/.pi/prompts"
test ! -e "$TMP_HOME/.pi/sessions"
test ! -e "$TMP_HOME/.pi/npm"
test ! -e "$TMP_HOME/.config/mcp/mcp.json"

# The upstream copy lands in the source dir first ("copied to this repository"),
# then in the installed agent skills.
test -f "$SOURCE_DIR/.pi/skills/mattpocock/engineering/demo/SKILL.md"
grep -F "$SKILL_MARKER" "$SOURCE_DIR/.pi/skills/mattpocock/engineering/demo/SKILL.md" >/dev/null
test -f "$TMP_HOME/.pi/agent/skills/mattpocock/engineering/demo/SKILL.md"
grep -F "$SKILL_MARKER" "$TMP_HOME/.pi/agent/skills/mattpocock/engineering/demo/SKILL.md" >/dev/null
# The bundled engineering bucket was replaced by the upstream one.
test ! -e "$TMP_HOME/.pi/agent/skills/mattpocock/engineering/tdd"

expected_packages=$(node -e '
const fs = require("fs");
const settings = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
process.stdout.write((settings.packages || []).join("\n"));
' "$ROOT_DIR/.pi/agent/settings.json")

grep -Fx 'uninstall -g @mariozechner/pi-coding-agent @earendil-works/pi-coding-agent pi-coding-agent' "$NPM_LOG" >/dev/null
grep -Fx 'install -g @earendil-works/pi-coding-agent' "$NPM_LOG" >/dev/null

for package in $expected_packages; do
	grep -Fx "uninstall $package" "$PI_LOG" >/dev/null
	grep -Fx "install $package" "$PI_LOG" >/dev/null
done

last_uninstall=$(grep -n '^uninstall ' "$PI_LOG" | tail -1 | cut -d: -f1)
first_install=$(grep -n '^install ' "$PI_LOG" | head -1 | cut -d: -f1)
test "$last_uninstall" -lt "$first_install"

grep -Fx 'update' "$PI_LOG" >/dev/null

# Second install: refresh fallback. Unreachable upstream keeps the bundled copies.
rm -rf "$SOURCE_DIR"
cp -R "$ROOT_DIR" "$SOURCE_DIR"
rm -rf "$SOURCE_DIR/.git" "$SOURCE_DIR/.pi/sessions"
rm -rf "$TMP_HOME"
mkdir -p "$TMP_HOME"
: >"$NPM_LOG"
: >"$PI_LOG"

PATH="$TMP_BIN:$PATH" HOME="$TMP_HOME" PI_INSTALL_SOURCE_DIR="$SOURCE_DIR" \
	PI_MATTPOCOCK_SKILLS_REPO="file://$TMP_DIR/missing-repo" \
	sh "$ROOT_DIR/install.sh"

test -f "$TMP_HOME/.pi/agent/skills/mattpocock/engineering/tdd/SKILL.md"

printf '%s\n' "Smoke test passed"
