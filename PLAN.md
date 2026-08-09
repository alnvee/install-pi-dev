# Improvement Plan — install-pi-dev

## Context

`install-pi-dev` is a personal Pi (AI coding agent) install bundle. It ships:

- `install.sh` (358 lines): uninstalls old Pi CLI, removes `~/.pi`, installs `@earendil-works/pi-coding-agent` globally, refreshes mattpocock skills from upstream, copies the `.pi` bundle to `~/.pi`, syncs skills/prompts into agent scope, installs packages from `settings.json`, runs `pi update`.
- `scripts/smoke-test.sh` (113 lines): end-to-end test with mock `npm`/`pi` binaries (passes today).
- `.pi/` bundle: `agent/SYSTEM.md`, `settings.json`, `models.json`, 30 skills (alnvee + mattpocock), `npm/` + `sessions/` (gitignored runtime artifacts).

Current state verified: smoke test passes, both scripts are `sh -n` clean, **no CI**, **no shellcheck**, **no uninstall path**, `docker/` contains only a stale untracked `__pycache__` artifact, `.gitignore` references a non-existent `.env.example`.

Goal: make the installer more reliable, better tested, and easier to maintain — **without changing its core model** (latest-everything, replace `~/.pi` on install).

## Decisions (user-confirmed)

1. **Scope: P0 set only.** Safety/checksum redesigns (config backup, tagged-release checksums, EACCES handling, partial-install resume) are documented below as deferred, not implemented.
2. **Config on reinstall: keep current behavior.** `~/.pi` (incl. `auth.json`, `models.json`, custom skills) is fully replaced on every install. README will document this explicitly.
3. **Remote tarball integrity: keep skip-by-default.** `PI_INSTALL_RELEASE_SHA256` remains optional; README documents the tradeoff.

## Approach

Four parallel workstreams, each independently verifiable:

1. **Hardening `install.sh`** — add `mktemp` to `require_cmd`, dedupe the two near-identical sync functions, add post-install `pi --version` verification, fix shellcheck findings.
2. **New `uninstall.sh`** — reverse of install: uninstall packages from `settings.json`, uninstall global CLI, remove `~/.pi`. Supports `--dry-run`, refuses to run with unsafe `HOME`.
3. **Testing + CI** — expand the smoke test (dry-run, invalid source dir, empty packages, remote-download path, checksum mismatch, npm failure) and add a GitHub Actions workflow that runs `shellcheck` + the smoke test on every push/PR.
4. **Docs & hygiene** — `.env.example`, delete stale `docker/` artifact, README updates (prerequisites, overwrite behavior, uninstall, troubleshooting, security note).

## Files to modify

| File | Change |
| --- | --- |
| `install.sh` | `mktemp` prereq (A6); dedupe sync fns (C11); post-install `pi --version` (A4); shellcheck fixes (C12) |
| `uninstall.sh` (new) | Reverse installer (A3) |
| `scripts/smoke-test.sh` | New cases (B9) incl. dry-run assertions |
| `.github/workflows/ci.yml` (new) | shellcheck + smoke test on push/PR (B8) |
| `.env.example` (new) | Document `PI_INSTALL_*` vars (C13) |
| `README.md` | Prereqs, overwrite behavior, uninstall, troubleshooting, security note (E16) |
| `docker/` (delete) | Stale untracked `notebooklm-mcp/__pycache__` (D15) |

## Reuse

- `install.sh` helpers `log` / `dry_log` / `die` / `require_cmd` / `run` — reuse the same pattern in `uninstall.sh`.
- `packages_from_settings` (install.sh) — the `node` heredoc parsing `.pi/agent/settings.json`; `uninstall.sh` needs the identical package-list logic (extract to a shared script or duplicate deliberately).
- Smoke-test fixture pattern (local `file://` tar archive for the skills repo) — reuse for a source-repo fixture to exercise `download_source_dir` without network.

## Steps

- [x] **S1 — install.sh hardening**
  - `mktemp` added to `require_cmd`. ✅
  - `sync_skills_into_agent_scope` + `sync_prompts_into_agent_scope` merged into one `sync_dir_into_agent_scope <install_root> <dir_name>`. ✅
  - Post-install `pi --version` verification with `die` guidance added. ✅
  - **New (incident-driven, S1b): running-pi guard** — `check_no_running_pi()` aborts before the destructive steps if `pgrep -x pi` finds a live instance (install replaces `$HOME/.pi`, destroying the running instance's session/context-mode state). Escape hatch: `--force` / `PI_INSTALL_FORCE=1`. Verified live: correctly blocked the three running instances. ✅
- [x] **S2 — shellcheck pass** — `install.sh` + `scripts/smoke-test.sh` clean under `koalaman/shellcheck:stable` (exit 0). ✅
- [x] **S3 — new `uninstall.sh`** — file exists with `--dry-run`/`--plan`, `-h`, unsafe-HOME refusal, and the three reverse steps. **Running-pi guard added** (same as S1b) — uninstall also `rm -rf`s `$HOME/.pi`, so it now refuses while another pi instance is running (`--force` / `PI_INSTALL_FORCE=1` overrides). ✅ Verified: dry-run prints the reverse plan; guard fires against the live instance; full install→uninstall cycle in a throwaway HOME removes `~/.pi` and issues `pi uninstall` per package + `npm uninstall -g`.
- [x] **S5 — CI workflow** — `.github/workflows/ci.yml`: on `push` + `pull_request`, ubuntu-latest: (1) `shellcheck` the three scripts, (2) `sh scripts/smoke-test.sh` (node ships on the runner). Fail on warnings. ✅
- [x] **S6 — `.env.example`** — documents `PI_INSTALL_REPO_URL`, `PI_INSTALL_REPO_BRANCH`, `PI_INSTALL_SOURCE_DIR`, `PI_INSTALL_DRY_RUN`, `PI_INSTALL_SKIP_CHECKSUM`, `PI_INSTALL_FORCE`, `PI_INSTALL_RELEASE_SHA256`, `PI_MATTPOCOCK_SKILLS_REPO`, `PI_MATTPOCOCK_SKILLS_BRANCH`. ✅ (`.gitignore` already whitelists it via `!.env.example`.)
- [x] **S7 — hygiene** — deleted `docker/notebooklm-mcp/__pycache__`; the `docker/` dir contained nothing else, so it's fully removed. `.gitignore` kept as-is. ✅
- [x] **S8 — README** — prerequisites (Node/npm, `curl`, `tar`, `sha256sum`, `pgrep`); explicit "what gets overwritten" (full `~/.pi` replacement incl. auth — per decision 2); uninstall usage; `--force` / `PI_INSTALL_FORCE` documented; security note on `curl | sh` + optional `PI_INSTALL_RELEASE_SHA256`; troubleshooting (npm EACCES → nvm/prefix hint, offline → bundled skills kept, `pi` won't start). ✅

## Bugs found while implementing (all pre-existing, now fixed in `install.sh` + `smoke-test.sh`)

1. **Empty-packages kill under `set -e`** — `[ -n "$packages" ] || return` in `install_pi_packages` returned the failed test's status (1), aborting the install before `pi update` when `settings.json` had no packages. Fixed: `return 0`. (Reproduced on HEAD before any of our edits.)
2. **`download_source_dir` stdout pollution** — `source_dir=$(resolve_source_dir)` captured `dry_log`/`verify_checksum` output along with the path, so remote installs resolved to a multi-line "directory" and died at the settings check. Hidden until the smoke test started running from a neutral cwd (the old `./.pi` shortcut short-circuited the remote path). Fixed: progress messages now go to stderr; stdout is the pure return channel.
3. **Smoke test never exercised the remote path** — it ran from the repo root, so `resolve_source_dir` took the local-checkout shortcut and the download/checksum code was dead. Fixed: smoke test now `cd`s into its throwaway `TMP_DIR`.

## Verification

- `./scripts/smoke-test.sh` passes — existing + S4 cases.
- `shellcheck install.sh uninstall.sh scripts/smoke-test.sh` clean (CI enforces on push/PR).
- `sh ./install.sh --dry-run` prints the plan; `sh ./uninstall.sh --dry-run` prints the reverse plan.
- Manual end-to-end in throwaway `HOME` (`TMP_HOME=$(mktemp -d); HOME=$TMP_HOME sh ./install.sh`) then `HOME=$TMP_HOME sh ./uninstall.sh`; confirm `~/.pi` gone.
- CI run green on the PR.

## Deferred (documented, not implemented)

- A1: preserve `auth.json`/`models.json` across reinstalls — **user chose to keep current wipe behavior**.
- A2: tagged-release tarball + committed `SHA256SUMS` for real integrity — **user chose skip-by-default**.
- A5: npm global EACCES detection hint (README troubleshooting covers it textually).
- A7: partial-state recovery if a `pi install` fails mid-list.
- B10: derive `print_plan` steps from the code (drift risk remains, partially mitigated by S4 dry-run assertion).
- C14: skip `agent/prompts` sync when source is empty (kept as forward-compat).
