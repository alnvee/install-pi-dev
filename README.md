# Pi install bundle

This repository contains the `.pi` bundle and an installer that:

1. Removes the existing Pi CLI and the current `~/.pi` directory.
2. Installs `@mariozechner/pi-coding-agent` globally with `npm`.
3. Copies the repository `.pi` folder to `~/.pi`.
4. Installs the packages listed in `.pi/settings.json` with `pi install`.

When you run the script from a local checkout, it uses the checkout’s `.pi` directory. When you stream it with `curl | sh`, it downloads the current `main` branch archive from `alnvee/install-pi-dev` so changes to `.pi` are picked up on every install.

## Usage

From a local checkout:

```sh
sh ./install.sh
```

From the published installer:

```sh
curl -fsSL https://raw.githubusercontent.com/alnvee/install-pi-dev/main/install.sh | sh
```

To verify the install flow without touching your real home directory:

```sh
./scripts/smoke-test.sh
```
