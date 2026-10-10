# docker-mql-compiler

A Docker image and a one-file command that compile MQL4 (`.mq4`) and MQL5 (`.mq5`) sources with MetaQuotes' MetaEditor under Wine, on Linux, with no Windows and no MetaTrader terminal running.

The project rules live in [.agents/rules/](.agents/rules/README.md), one file per topic: architecture, Bash code, testing, security, docs and releases, and chat sign-offs. Read the ones that match what you are about to touch before you edit.

## Architecture

- `entrypoint.sh` is the image's whole program (installed as `/usr/local/bin/mql-compiler`). It collects sources from its arguments (relative to the working directory, `/src` by default), makes sure the toolchain and its unpacked standard library are in `/cache/uid-<UID>`, builds a merged include root per platform and user `MQL4`/`MQL5` folder (with any `-I` folders), runs MetaEditor's `/compile` per file under Xvfb, and prints one JSON `file` record per source plus a `summary` (or `--text`/`--format gnu` renderings of the same record). It also handles `--version`, `--update` and `--watch`. `--mt4-terminal`/`--mt5-terminal` swap a platform's MetaEditor and standard library for a mounted portable terminal's (`terminal_dir`, `find_metaeditor`, `stdlib_root`), and that platform is then never installed; a compile installs only the platforms its sources need (`needed_platforms`).
- `wrapper.sh` is the host command `install.sh` writes to `~/.local/bin` or `/usr/local/bin`. It resolves each path argument to an absolute host path, mounts the folder it includes from (the nearest `MQL4` above a `.mq4`, `MQL5` above a `.mq5`, either above a folder, else the folder or the file's folder) at the same path in the container, mounts each `-I` folder as it is, mounts each `--mt4-terminal`/`--mt5-terminal` folder read-only (unless a read-write mount already covers it), dedupes nested mounts, refuses `/`, sets `-w` to the current folder, and adds `--init`, the `mql-compiler-cache` volume on `/cache` and the caller's UID. Its own errors follow the output format: an `{"type":"error"}` record on stdout for JSON. `install.sh` rewrites its `PINNED_IMAGE` line.
- `action.yml` and `action/run.sh` are the GitHub Action: `run.sh prepare` picks the image (the release matching the action's ref) and the cache folder, `actions/cache` keeps the toolchain, `run.sh compile` runs `wrapper.sh`, turns the JSON records into `::error`/`::warning` annotations, writes the job summary and sets the outputs.
- `install.sh` pins a release image (or `:latest` with `--rolling`, or `:dev` with `MQL_COMPILER_ENV=dev`), installs the command or `--uninstall`s it along with its pinned image (never `:dev`), and refuses to overwrite a file without the `mql-compiler-managed-command` marker.

Data flow: `mql-compiler` (host) -> `docker run` -> `entrypoint.sh` -> Wine -> MetaEditor -> `.ex4`/`.ex5` next to the source.

## Stack

- Bash scripts, a Debian trixie image with Wine 10 (64-bit and `wine32:i386`), Xvfb, osslsigncode, jq, inotify-tools.
- No MetaQuotes software in the image or the repo: the first run downloads the RoboForex installers (or `MQL_COMPILER_MT4_URL`/`MQL_COMPILER_MT5_URL`), checks their Authenticode signature (trusted chain, signing certificate's CN starting with "MetaQuotes", see SEC1), and installs them with `/auto`.
- CI: `.github/workflows/pipeline.yml` runs `make lint` and `make test-all`, then the action itself against the freshly built `:dev` image (`uses: ./`), then the reusable docker-image workflow (amd64 only, Grype scan) and, on tags, the ClawHub skill publish.

## Layout

- `tests/test.sh`: end-to-end tests, by hand (`/src`) and through `wrapper.sh` from other folders, against copies of `tests/fixtures/`: an `MQL4` and an `MQL5` tree with experts, indicators, scripts, their own `Include` (including a header that shadows a standard one), a `#resource` file, standard-library users, a broken file, and a loose file outside both trees. Other cases (symlinks, lowercase folders, an MT4 image resource, setup failures, a foreign-UID cache, the Action script, `install.sh`) build their files at run time.
- `tests/unit/`: scripts that run inside the image and test entrypoint functions with one dependency stubbed (the signature report, MetaEditor writing no result).
- `action.yml`, `action/run.sh`: the GitHub Action, tested in CI with `uses: ./`.
- `.agents/skills/mql-compiler/SKILL.md`: the agent skill published to ClawHub.
- `.agents/rules/`: the project rules (ARC, SH, TST, SEC, DOC, CHAT), not published.
- `scripts/ci-dockerhub-login.sh`: CI's retrying Docker Hub login.

## Dev workflow

```bash
make build     # image as :dev, :v<VERSION>, :latest
make test      # first run installs the toolchain into .testing/cache (about 90 s); about 5 minutes after that
make test-all  # make test plus a real release install from Docker Hub (what CI runs)
make lint      # shellcheck, shfmt (-i 4 -ci), hadolint
make sec       # gitleaks, hadolint, grype
make install   # :dev image + command from this checkout
make version V=X.Y.Z   # VERSION and .agents/.codex-plugin/plugin.json, no git
```

Every tool runs from a digest-pinned image. The maintainer cuts releases (DOC15 in `.agents/rules/docs-and-releases.md`).

## Landmines

- MetaEditor's exit code is backwards (1 usually means success). The verdict is the `Result:` line of its UTF-16 log.
- The MT4/MT5 setup launchers exit at once and hand off to a child. `wineserver -w` is what waits for the install, and Xvfb must stay up the whole time, or the child dies with the display.
- `wineserver -p` (kept alive for the compile loop) needs an existing prefix, so it starts only after setup.
- Wine refuses a prefix owned by another UID. That is why the cache is per UID inside one volume, and why `/cache` is sticky and world-writable in the image.
- `/inc:` takes the `MQL4`/`MQL5` folder itself, not its `Include` subfolder, and only one of them. It also breaks on a path with spaces (the terminal sits under `Program Files`). Hence the merged root in a staging folder under `/tmp`: `cp -rs` links of the standard `Include`, the user's `Include` linked over it with `--remove-destination` (user wins), and links to the user's other subfolders for `#resource`.
- `/compile:` breaks on spaces too: MetaEditor writes no result at all. A source path with whitespace is compiled through a link in the staging folder (`stage_source`), and `read_log` maps every staging path back to the real file.
- MetaEditor deletes a failed file's old `.ex4`/`.ex5` itself, but not a read-only one and not when it writes no result, so `compile_one` deletes it first.
- Docker kills every process in the container when the entrypoint exits, so `finish` closes stdout and stderr and waits for the `tee` processes, or `last-run.log` loses its tail.
- One run at a time per UID: `acquire_run_lock` holds `flock` on `.run.lock` for the whole run, setup included. `--watch` releases it while it waits for changes and takes it again for each pass.
- stdout is a contract (JSON Lines by default). `compile_one` builds one JSON `file` record and `print_file_result` renders `--text` and `--format gnu` from that same record, so the formats cannot disagree. `die` writes its `error` record to fd 7, a copy of the real stdout, because it is often called inside a command substitution whose stdout is captured.
- The MetaEditor build comes from the `FileVersion` string in the executable's UTF-16 version resource (`metaeditor_build`, plain `grep -P`), so `--version` needs neither Wine nor a running terminal.
- `--watch` needs `tini` as PID 1 (`docker run --init`, which the wrapper passes); bash as PID 1 ignores SIGTERM and SIGINT. `inotifywait` runs in the background so the INT/TERM trap fires at once.
- osslsigncode's report lists the chain and timestamp certificates too, so `require_signer` checks only the first `Subject:` after `Signer's certificate:` for `/CN=MetaQuotes`.
- The installers do not unpack the standard library. The terminal does, into its `MQL4`/`MQL5` folder, on its first `/portable` start. `unpack_stdlib` starts it, waits for `Include/Trade/Trade.mqh` (MT5) or `Include/stdlib.mqh` (MT4), then `wineserver -k`.
- Paths in the container must equal host paths for the output to make sense, which is why the wrapper mounts at the same path and passes `realpath`ed arguments. Mounting only `Experts` hides the user's `Include`.
- The image is amd64 only: MT4's MetaEditor is 32-bit and needs Wine's i386 packages.
- Docker Hub: the reusable workflow needs `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN` (Read, Write and Delete scope).
