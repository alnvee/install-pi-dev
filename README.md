# Pi install bundle

This repository contains the `.pi` bundle and an installer that:

1. Removes the existing Pi CLI and the current `~/.pi` directory.
2. Installs `@earendil-works/pi-coding-agent` globally with `npm`.
3. Copies the repository `.pi` folder to `~/.pi`.
4. Uninstalls and reinstalls the packages listed in `.pi/agent/settings.json` with `pi`, then runs `pi update` so the latest versions are fetched on each run.

When you run the script from a local checkout, it uses the checkout’s `.pi` directory as-is and installs from there. When you stream it with `curl | sh`, it downloads the current `main` branch archive from `alnvee/install-pi-dev` so changes to `.pi` are picked up on every install.

## Prerequisites

- **Node.js + npm** (Node 18+ recommended; `pi` is an npm package). If `npm install -g` fails with an EACCES permission error, use a Node version manager (e.g. [nvm](https://github.com/nvm-sh/nvm)) or set a user-level npm prefix instead of running with `sudo`.
- **`curl`** and **`tar`** — required for the remote download path (streamed installs). Local installs from a checkout do not need them.
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

## NotebookLM (Gemini Notebook) research backend

A **`/nlm` extension ships with every install** — the NotebookLM surface inside pi. Type `/nlm` for a menu (select/change your current notebook — remembered for queries and source adds — auth status/login, list notebooks, ask your sources, add a source, doctor) or `/nlm <args>` to run the `nlm` CLI directly. Asking a question surfaces **only the answer** — citation metadata is hidden (the MCP tool still returns it). The extension is also the wrapper that installs the NotebookLM MCP server into the **Docker MCP gateway**: `/nlm` → “Install MCP server in Docker” (or `/nlm setup`) sets it up, and “Remove MCP server from Docker” (`/nlm remove`) tears it down — no reinstall needed.

The bundle also ships a skill (`.pi/skills/alnvee/notebooklm/SKILL.md`) that lets the agent query your research corpus — list notebooks, add sources, and ask grounded questions with citations.

There is **no official public API for consumer NotebookLM**; this integration uses the unofficial `notebooklm-mcp-cli` (`nlm` CLI + `notebooklm-mcp` server, reverse-engineered BOQ RPC, cookie auth). It can break when Google changes the product and is a ToS gray area — acceptable for a personal research setup, not for shared/production deployments. The official Gemini Notebook **Enterprise** API exists but currently lacks a chat/query endpoint, so it cannot do agent Q&A yet.

To set the backend up during install (requires Docker MCP gateway + a Google account):

```sh
PI_INSTALL_NOTEBOOKLM=1 sh ./install.sh
```

Or on demand from inside pi: `/nlm` → “Install MCP server in Docker”. The same installer can be run directly on an existing install:

```sh
sh ~/.pi/scripts/setup-notebooklm.sh
```

The `/nlm` extension, its skill, and the setup script ship by default. To exclude the entire `/nlm` surface from an install, set `PI_INSTALL_NLM=0` (or pass `--no-nlm`) — the extension, skill, and `setup-notebooklm.sh` are then left out, and the backend is never set up (an explicit `PI_INSTALL_NOTEBOOKLM=1` with `/nlm` excluded is an error).

What it does: installs `notebooklm-mcp-cli` (uv/pipx/pip), provisions auth via `nlm login` (browser sign-in; headless via `nlm login --manual --file cookies.txt`), runs the `notebooklm-mcp` HTTP server on `127.0.0.1:9420` as a systemd user service, and registers it in the Docker MCP gateway as a `remote` server. Auth state lives in `~/.notebooklm-mcp-cli` — outside `~/.pi`, so it survives reinstalls. The auth cookies are a durable full-account Google credential: prefer a dedicated account, and keep `~/.notebooklm-mcp-cli` private.

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
- **`pi` does not start after a successful install** — check `node --version` / `npm --version`; if the global `pi` binary exists but errors, reinstall with `npm install -g @earendil-works/pi-coding-agent`.
- **Installer refuses to run** — another `pi` instance is running. Close it (or all instances), then retry; use `--force` only if you accept that its `~/.pi` state will be destroyed.
