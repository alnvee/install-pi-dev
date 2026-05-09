# Pi install bundle

This repository contains the `.pi` bundle and an installer that:

1. Removes the existing Pi CLI and the current `~/.pi` directory.
2. Installs `@earendil-works/pi-coding-agent` globally with `npm`.
3. Copies the repository `.pi` folder to `~/.pi`.
4. Uninstalls and reinstalls the packages listed in `.pi/settings.json` with `pi`, then runs `pi update` so the latest versions are fetched on each run.
5. Optionally, when run with `--with-docker` or `PI_INSTALL_DOCKER_COMPONENTS=1`, builds the NotebookLM Docker images, writes the Docker MCP overlay files, and copies the MCP gateway config.

When you run the script from a local checkout, it uses the checkout’s `.pi` directory. When you stream it with `curl | sh`, it downloads the current `main` branch archive from `alnvee/install-pi-dev` so changes to `.pi` are picked up on every install.

Docker is optional for the base install. Use `--with-docker` only if you want the NotebookLM Docker images and MCP gateway overlay.

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

The NotebookLM service is packaged as a Docker image and registered with the same gateway that backs `MCP_DOCKER`. If you need to refresh NotebookLM auth, call the `notebooklm_login` tool on the `notebooklm-auth` MCP server.
