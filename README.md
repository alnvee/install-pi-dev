# Pi install bundle

This repository contains the `.pi` bundle and an installer that:

1. Removes the existing Pi CLI and the current `~/.pi` directory.
2. Installs `@earendil-works/pi-coding-agent` globally with `npm`.
3. Refreshes the bundled mattpocock skills from [`github.com/mattpocock/skills`](https://github.com/mattpocock/skills) so the install always uses the latest upstream versions. On failure (offline, no curl/tar) the bundled copies are kept.
4. Copies the repository `.pi` folder to `~/.pi`.
5. Uninstalls and reinstalls the packages listed in `.pi/agent/settings.json` with `pi`, then runs `pi update` so the latest versions are fetched on each run.

When you run the script from a local checkout, it uses the checkout’s `.pi` directory — so the mattpocock refresh updates the repo’s `.pi/skills/mattpocock` first (you can commit the refreshed copies), then installs from there. When you stream it with `curl | sh`, it downloads the current `main` branch archive from `alnvee/install-pi-dev` so changes to `.pi` are picked up on every install.

The mattpocock refresh can be pointed elsewhere with `PI_MATTPOCOCK_SKILLS_REPO` / `PI_MATTPOCOCK_SKILLS_BRANCH`.

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

To smoke-test the published installer in a throwaway home directory:

```sh
TMP_HOME="$(mktemp -d)"
HOME="$TMP_HOME" curl -fsSL https://raw.githubusercontent.com/alnvee/install-pi-dev/main/install.sh | sh
```

The smoke test runs the installer against a throwaway `HOME` with mock `npm`/`pi` binaries and asserts the resulting `~/.pi` layout, the package install sequence, and that runtime artifacts (sessions, npm dir) are not shipped.
