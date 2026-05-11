# Pi install bundle

This repository contains the `.pi` bundle and an installer that:

1. Removes the existing Pi CLI and the current `~/.pi` directory.
2. Installs `@earendil-works/pi-coding-agent` globally with `npm`.
3. Copies the repository `.pi` folder to `~/.pi`.
4. Uninstalls and reinstalls the packages listed in `.pi/agent/settings.json` with `pi`, then runs `pi update` so the latest versions are fetched on each run.
5. Optionally, when run with `--with-docker` or `PI_INSTALL_DOCKER_COMPONENTS=1`, builds the NotebookLM Docker images, writes the Docker MCP overlay files, copies the MCP gateway config, and attaches NotebookLM to the active Docker MCP profile.
6. Switches the installed `.pi/agent/SYSTEM.md` to the Docker-aware variant only for Docker-enabled installs; the base install keeps a system prompt without the `mcp-agent` reference.

When you run the script from a local checkout, it uses the checkout’s `.pi` directory. When you stream it with `curl | sh`, it downloads the current `main` branch archive from `alnvee/install-pi-dev` so changes to `.pi` are picked up on every install.

Docker is optional for the base install. Use `--with-docker` only if you want the NotebookLM Docker images and MCP gateway overlay.

The installer assumes the Docker MCP profile is named `default`. If your local Docker setup uses a different profile, set `PI_DOCKER_MCP_PROFILE` before running the installer.

## Workspace Contract

This repo expects a workspace-local `./.env` file with `NOTEBOOKLM_NOTEBOOK_URL` set for the active project notebook. The notebook URL is intentionally not hardcoded in repo docs because it can differ per workspace.

The MCP skill that should be used for Docker gateway work lives at [`.pi/skills/alnvee/mcp/SKILL.md`](/home/aln/Projects/install-pi-dev/.pi/skills/alnvee/mcp/SKILL.md).

If you are creating a new workspace, copy [`.env.example`](/home/aln/Projects/install-pi-dev/.env.example) to `./.env` and set the notebook URL before trying to query NotebookLM.

## Usage

From a local checkout:

```sh
sh ./install.sh
```

To include the NotebookLM Docker/MCP pieces as part of the install:

```sh
sh ./install.sh --with-docker
```

From the published installer:

```sh
curl -fsSL https://raw.githubusercontent.com/alnvee/install-pi-dev/main/install.sh | sh
```

To verify the install flow without touching your real home directory:

```sh
./scripts/smoke-test.sh
```

After a Docker-enabled install, verify the NotebookLM server is attached and visible with:

```sh
docker mcp profile server ls --filter profile=default | rg notebooklm
docker mcp tools ls --format human | rg 'notebook_describe|notebooklm_login|source_describe'
```

The NotebookLM service is packaged as a Docker image and registered with the same gateway that backs `MCP_DOCKER`. If you need to refresh NotebookLM auth, call the `notebooklm_login` tool on the `notebooklm-auth` MCP server.

