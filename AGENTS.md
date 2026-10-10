# docker-mql-compiler

A Docker image and a one-file command that compile MQL4 (`.mq4`) and MQL5 (`.mq5`) sources with MetaQuotes' MetaEditor under Wine, on Linux, with no Windows and no MetaTrader terminal running.

## Architecture

- `entrypoint.sh` is the image's whole program (installed as `/usr/local/bin/mql-compiler`). It collects sources under `/src`, makes sure the toolchain is in `/cache/uid-<UID>`, runs MetaEditor's `/compile` per file under Xvfb, and prints `OK`/`FAIL` lines with the compiler messages.
- `wrapper.sh` is the host command `install.sh` writes to `~/.local/bin` or `/usr/local/bin`. It is a `docker run` with `$PWD` on `/src`, the `mql-compiler-cache` volume on `/cache`, and the caller's UID. `install.sh` rewrites its `PINNED_IMAGE` line.
- `install.sh` pins a release image (or `:latest` with `--rolling`, or `:dev` with `MQL_COMPILER_ENV=dev`), installs or `--uninstall`s the command, and refuses to overwrite a file without the `mql-compiler-managed-command` marker.

Data flow: `mql-compiler` (host) -> `docker run` -> `entrypoint.sh` -> Wine -> MetaEditor -> `.ex4`/`.ex5` next to the source.

## Stack

- Bash scripts, a Debian trixie image with Wine 10 (64-bit and `wine32:i386`), Xvfb, osslsigncode, jq.
- No MetaQuotes software in the image or the repo: the first run downloads the RoboForex installers (or `MQL_COMPILER_MT4_URL`/`MQL_COMPILER_MT5_URL`), checks they are signed by MetaQuotes, and installs them with `/auto`.
- CI: `.github/workflows/pipeline.yml` runs `make lint` and `make test`, then the reusable docker-image workflow (amd64 only, Grype scan) and, on tags, the ClawHub skill publish.

## Layout

- `tests/test.sh`: end-to-end tests against copies of `tests/fixtures/` (an `MQL4` and an `MQL5` tree with their own `Include`, plus a broken file).
- `.agents/skills/mql-compiler/SKILL.md`: the agent skill published to ClawHub.
- `scripts/ci-dockerhub-login.sh`: CI's retrying Docker Hub login.

## Dev workflow

```bash
make build     # image as :dev, :v<VERSION>, :latest
make test      # first run installs the toolchain into .testing/cache (about 90 s)
make lint      # shellcheck, shfmt (-i 4 -ci), hadolint
make sec       # gitleaks, hadolint, grype
make install   # :dev image + command from this checkout
make version V=X.Y.Z   # VERSION and .agents/.codex-plugin/plugin.json, no git
```

Every tool runs from a digest-pinned image. Releases go through git-update, never raw git.

## Landmines

- MetaEditor's exit code is backwards (1 usually means success). The verdict is the `Result:` line of its UTF-16 log.
- The MT4/MT5 setup launchers exit at once and hand off to a child. `wineserver -w` is what waits for the install, and Xvfb must stay up the whole time, or the child dies with the display.
- `wineserver -p` (kept alive for the compile loop) needs an existing prefix, so it starts only after setup.
- Wine refuses a prefix owned by another UID. That is why the cache is per UID inside one volume, and why `/cache` is sticky and world-writable in the image.
- `/inc:` takes the `MQL4`/`MQL5` folder itself, not its `Include` subfolder.
- The image is amd64 only: MT4's MetaEditor is 32-bit and needs Wine's i386 packages.
- Docker Hub: the reusable workflow needs `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN` (Read, Write and Delete scope).
