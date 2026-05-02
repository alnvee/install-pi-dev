# Pi install bundle

This repository contains the `.pi` bundle and an installer that:

1. Removes the existing Pi CLI and the current `~/.pi` directory.
2. Installs `@mariozechner/pi-coding-agent` globally with `npm`.
3. Copies the repository `.pi` folder to `~/.pi`.
4. Installs the packages listed in `.pi/settings.json` with `pi install`.

When you run the script from a local checkout, it uses the checkout’s `.pi` directory. When you stream it with `curl | sh`, set `PI_INSTALL_REPO_URL` to the GitHub repo root that contains this bundle so the script can download the current archive and pick up changes to `.pi` on every install.

## Usage

From a local checkout:

```sh
sh ./install.sh
```

From the published installer:

```sh
PI_INSTALL_REPO_URL=https://github.com/OWNER/REPO \
	curl -fsSL https://pi.dev/install.sh | sh
```