# Pi install bundle

This repository contains the `.pi` bundle and an installer that:

1. Removes the existing Pi CLI and the current `~/.pi` directory.
2. Installs `@earendil-works/pi-coding-agent` globally with `npm`.
3. Refreshes the bundled mattpocock skills from [`github.com/mattpocock/skills`](https://github.com/mattpocock/skills) so the install always uses the latest upstream versions. On failure (offline, no curl/tar) the bundled copies are kept.
4. Copies the repository `.pi` folder to `~/.pi`.
5. Uninstalls and reinstalls the packages listed in `.pi/agent/settings.json` with `pi`, then runs `pi update` so the latest versions are fetched on each run.

When you run the script from a local checkout, it uses the checkout’s `.pi` directory — so the mattpocock refresh updates the repo’s `.pi/skills/mattpocock` first (you can commit the refreshed copies), then installs from there. When you stream it with `curl | sh`, it downloads the current `main` branch archive from `alnvee/install-pi-dev` so changes to `.pi` are picked up on every install.

The mattpocock refresh can be pointed elsewhere with `PI_MATTPOCOCK_SKILLS_REPO` / `PI_MATTPOCOCK_SKILLS_BRANCH`.

## Prerequisites

- **Node.js + npm** (Node 18+ recommended; `pi` is an npm package). If `npm install -g` fails with an EACCES permission error, use a Node version manager (e.g. [nvm](https://github.com/nvm-sh/nvm)) or set a user-level npm prefix instead of running with `sudo`.
- **`curl`** and **`tar`** — required for the remote download path (streamed installs and the mattpocock skills refresh). If they are missing, the installer falls back to the bundled skills.
- **`sha256sum`** — only needed when `PI_INSTALL_RELEASE_SHA256` is set.
- **`pgrep`** — used by the running-instance safety check (see below). The installer skips the check if `pgrep` is unavailable.

## What gets overwritten

**Every install fully replaces `~/.pi`** — including `auth.json`, `models.json`, and any custom skills or settings you have added locally. Only what ships in this repository's `.pi/` bundle (plus whatever `pi install`/`pi update` fetch) survives. Back up anything in `~/.pi` you want to keep before reinstalling.

The installer also refuses to run while another `pi` instance is running, because replacing `~/.pi` destroys the running instance's session state. Close other instances first, or pass `--force` (or set `PI_INSTALL_FORCE=1`) to override.

## Usage

From a local checkout:

```sh
sh ./install.sh
```

From the published installer:

```sh
curl -fsSL https://raw.githubusercontent.com/alnvee/install-pi-dev/main/install.sh | sh
```

Preview the plan without making changes (also works streamed):

```sh
sh ./install.sh --dry-run
```

Force the install even though another `pi` instance is running:

```sh
sh ./install.sh --force
```

### Uninstalling

Remove the Pi CLI, its packages, and `~/.pi`:

```sh
sh ./uninstall.sh
```

Preview what uninstall would remove:

```sh
sh ./uninstall.sh --dry-run
```

Like the installer, uninstall refuses to run while another `pi` instance is running (`--force` overrides).

## Configuration

All installer behavior is configurable via environment variables — see [`.env.example`](.env.example) for the full list with defaults, including `PI_INSTALL_REPO_URL`, `PI_INSTALL_SOURCE_DIR`, `PI_INSTALL_DRY_RUN`, `PI_INSTALL_FORCE`, and `PI_INSTALL_RELEASE_SHA256`.

## Security note

Streaming a script with `curl | sh` runs whatever the URL currently serves, so it is only safe against a repository/network you trust. For stronger integrity, pin the release tarball with `PI_INSTALL_RELEASE_SHA256`:

```sh
PI_INSTALL_RELEASE_SHA256=<sha256> \
  curl -fsSL https://raw.githubusercontent.com/alnvee/install-pi-dev/main/install.sh | sh
```

Generate the expected hash with `curl -sL <archive_url> | sha256sum`, where `<archive_url>` is `https://github.com/alnvee/install-pi-dev/archive/refs/heads/main.tar.gz`.

## Testing

To verify the install flow without touching your real home directory:

```sh
./scripts/smoke-test.sh
```

The smoke test runs the installer against a throwaway `HOME` with mock `npm`/`pi` binaries and asserts the resulting `~/.pi` layout, the package install sequence, and that runtime artifacts (sessions, npm dir) are not shipped.

To smoke-test the published installer in a throwaway home directory:

```sh
TMP_HOME="$(mktemp -d)"
HOME="$TMP_HOME" curl -fsSL https://raw.githubusercontent.com/alnvee/install-pi-dev/main/install.sh | sh
```

## Troubleshooting

- **`npm install -g` fails with EACCES** — your npm global prefix is not user-writable. Install Node via nvm (or set a user prefix with `npm config set prefix ~/.npm-global` and add it to `PATH`) instead of using `sudo`.
- **No network / skills refresh fails** — the installer logs a warning and keeps the bundled mattpocock skills, so the install still completes.
- **`pi` does not start after a successful install** — check `node --version` / `npm --version`; if the global `pi` binary exists but errors, reinstall with `npm install -g @earendil-works/pi-coding-agent`.
- **Installer refuses to run** — another `pi` instance is running. Close it (or all instances), then retry; use `--force` only if you accept that its `~/.pi` state will be destroyed.
