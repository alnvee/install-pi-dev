#!/bin/sh

set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
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

# Run from a neutral cwd so install.sh does not pick up ./pi via
# resolve_source_dir's local-checkout shortcut (exercised by the
# remote-download tests below).
cd "$TMP_DIR"

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

# Mock pgrep reporting no running pi instances, so the running-instance guard
# does not abort the test installs on dev machines with live pi processes.
cat >"$TMP_BIN/pgrep" <<EOF
#!/bin/sh
exit 1
EOF
chmod +x "$TMP_BIN/pgrep"

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

# --- Additional regression tests ---

# 1) --dry-run prints the plan, exits 0, and touches nothing.
DRY_HOME="$TMP_DIR/dryhome"
mkdir -p "$DRY_HOME"
: >"$NPM_LOG"
: >"$PI_LOG"
DRY_OUTPUT=$(PATH="$TMP_BIN:$PATH" HOME="$DRY_HOME" PI_INSTALL_SOURCE_DIR="$SOURCE_DIR" \
	PI_MATTPOCOCK_SKILLS_REPO="file://$TMP_DIR/missing-repo" \
	sh "$ROOT_DIR/install.sh" --dry-run)
printf '%s\n' "$DRY_OUTPUT" | grep -F 'Installation plan:' >/dev/null
test ! -e "$DRY_HOME/.pi"
test ! -s "$NPM_LOG"
test ! -s "$PI_LOG"

# 2) Invalid PI_INSTALL_SOURCE_DIR (missing settings.json) aborts non-zero.
if PATH="$TMP_BIN:$PATH" HOME="$TMP_HOME" PI_INSTALL_SOURCE_DIR="$TMP_DIR" \
	sh "$ROOT_DIR/install.sh" >/dev/null 2>&1; then
	echo "expected invalid source dir to fail" >&2
	exit 1
fi

# 3) Empty packages list -> no pi install/uninstall calls.
EMPTY_SOURCE="$TMP_DIR/emptysource"
cp -R "$ROOT_DIR" "$EMPTY_SOURCE"
rm -rf "$EMPTY_SOURCE/.git" "$EMPTY_SOURCE/.pi/sessions"
printf '%s\n' '{ "packages": [] }' >"$EMPTY_SOURCE/.pi/agent/settings.json"
EMPTY_HOME="$TMP_DIR/emptyhome"
mkdir -p "$EMPTY_HOME"
: >"$NPM_LOG"
: >"$PI_LOG"
PATH="$TMP_BIN:$PATH" HOME="$EMPTY_HOME" PI_INSTALL_SOURCE_DIR="$EMPTY_SOURCE" \
	PI_MATTPOCOCK_SKILLS_REPO="file://$TMP_DIR/missing-repo" \
	sh "$ROOT_DIR/install.sh" >/dev/null
test -f "$EMPTY_HOME/.pi/agent/settings.json"
grep -Fx 'update' "$PI_LOG" >/dev/null
if grep -E '^(install|uninstall) ' "$PI_LOG" >/dev/null; then
	echo "expected no pi install/uninstall for empty packages" >&2
	exit 1
fi

# 4) Remote download path: source archive served over a file:// URL.
SRC_REPO="$TMP_DIR/sourcerepo"
SRC_FIXTURE="$TMP_DIR/sourcefixture"
mkdir -p "$SRC_REPO/archive/refs/heads"
cp -R "$ROOT_DIR" "$SRC_FIXTURE"
rm -rf "$SRC_FIXTURE/.git" "$SRC_FIXTURE/.pi/sessions"
tar -czf "$SRC_REPO/archive/refs/heads/main.tar.gz" -C "$TMP_DIR" sourcefixture

REMOTE_HOME="$TMP_DIR/remotehome"
mkdir -p "$REMOTE_HOME"
PATH="$TMP_BIN:$PATH" HOME="$REMOTE_HOME" PI_INSTALL_REPO_URL="file://$SRC_REPO" \
	PI_MATTPOCOCK_SKILLS_REPO="file://$TMP_DIR/missing-repo" \
	sh "$ROOT_DIR/install.sh" >/dev/null
test -f "$REMOTE_HOME/.pi/agent/settings.json"

# 5) Checksum mismatch aborts before running npm/pi or copying anything.
: >"$NPM_LOG"
: >"$PI_LOG"
if PATH="$TMP_BIN:$PATH" HOME="$REMOTE_HOME" PI_INSTALL_REPO_URL="file://$SRC_REPO" \
	PI_INSTALL_RELEASE_SHA256="0000000000000000000000000000000000000000000000000000000000000000" \
	PI_MATTPOCOCK_SKILLS_REPO="file://$TMP_DIR/missing-repo" \
	sh "$ROOT_DIR/install.sh" >/dev/null 2>&1; then
	echo "expected checksum mismatch to fail" >&2
	exit 1
fi
test ! -s "$NPM_LOG"
test ! -s "$PI_LOG"

# 6) npm install -g failure aborts the installer non-zero.
FAIL_BIN="$TMP_DIR/failbin"
mkdir -p "$FAIL_BIN"
printf '#!/bin/sh\nexit 1\n' >"$FAIL_BIN/npm"
chmod +x "$FAIL_BIN/npm"
FAIL_HOME="$TMP_DIR/failhome"
mkdir -p "$FAIL_HOME"
if PATH="$FAIL_BIN:$TMP_BIN:$PATH" HOME="$FAIL_HOME" PI_INSTALL_SOURCE_DIR="$SOURCE_DIR" \
	PI_MATTPOCOCK_SKILLS_REPO="file://$TMP_DIR/missing-repo" \
	sh "$ROOT_DIR/install.sh" >/dev/null 2>&1; then
	echo "expected npm failure to abort install" >&2
	exit 1
fi

# 7) Running pi instance aborts the install unless PI_INSTALL_FORCE=1.
GUARD_BIN="$TMP_DIR/guardbin"
mkdir -p "$GUARD_BIN"
printf '#!/bin/sh\nprintf "4242\\n"\n' >"$GUARD_BIN/pgrep"
chmod +x "$GUARD_BIN/pgrep"

GUARD_HOME="$TMP_DIR/guardhome"
mkdir -p "$GUARD_HOME"
if PATH="$GUARD_BIN:$TMP_BIN:$PATH" HOME="$GUARD_HOME" PI_INSTALL_SOURCE_DIR="$SOURCE_DIR" \
	PI_MATTPOCOCK_SKILLS_REPO="file://$TMP_DIR/missing-repo" \
	sh "$ROOT_DIR/install.sh" >/dev/null 2>&1; then
	echo "expected running-pi guard to abort install" >&2
	exit 1
fi
test ! -e "$GUARD_HOME/.pi"

# PI_INSTALL_FORCE=1 overrides the guard.
PATH="$GUARD_BIN:$TMP_BIN:$PATH" HOME="$GUARD_HOME" PI_INSTALL_SOURCE_DIR="$SOURCE_DIR" \
	PI_INSTALL_FORCE=1 PI_MATTPOCOCK_SKILLS_REPO="file://$TMP_DIR/missing-repo" \
	sh "$ROOT_DIR/install.sh" >/dev/null
test -f "$GUARD_HOME/.pi/agent/settings.json"

printf '%s\n' "Smoke test passed"
