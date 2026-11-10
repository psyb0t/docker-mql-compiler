# mql-compiler

Instructions for coding agents (Codex, Claude Code and others) and for people changing this repository. Users of the command want the documentation site, https://psyb0t.github.io/docker-mql-compiler/, not this file. Agents that only compile MQL with the command want the skill in `.agents/skills/mql-compiler/SKILL.md`.

## Agent setup

`CLAUDE.md` is a committed symlink to `AGENTS.md`, and `.claude` is a committed symlink to `.agents`, so Claude Code reads the same instructions, rules and skills as Codex. Claude's Edit and Write tools refuse to write through a symlink, so edit `AGENTS.md` and `.agents/rules/*.md` directly.

## What it is

A Docker image (`psyb0t/mql-compiler`, amd64 only) and a one-file host command (`mql-compiler`) that compile MQL4 (`.mq4`) and MQL5 (`.mq5`) sources with MetaQuotes' MetaEditor under Wine, on Linux, with no Windows and no MetaTrader terminal running. Results come out as JSON Lines on stdout. The repository also holds a composite GitHub Action, an installer and an agent skill. No MetaQuotes software is in the image or the repository: the first run downloads the installers, checks their signature and caches the toolchain in a Docker volume.

## Architecture

- `entrypoint.sh` is the image's whole program (installed as `/usr/local/bin/mql-compiler`). It collects sources from its arguments (relative to the working directory, `/src` by default), makes sure the toolchain and its unpacked standard library are in `/cache/uid-<UID>`, builds a merged include root per platform and user `MQL4`/`MQL5` directory (with any `-I` directories), runs MetaEditor's `/compile` per file under Xvfb, and prints one JSON `file` record per source plus a `summary` (or `--text`/`--format gnu` renderings of the same record). It also handles `--version`, `--setup`, `--update` and `--watch`. `--mt4-terminal`/`--mt5-terminal` swap a platform's MetaEditor and standard library for a mounted portable terminal's (`terminal_dir`, `find_metaeditor`, `stdlib_root`), and that platform is then never installed; a compile installs only the platforms its sources need (`needed_platforms`).
- `wrapper.sh` is the host command `install.sh` writes to `~/.local/bin` or `/usr/local/bin`. It resolves each path argument to an absolute host path, mounts the directory it includes from (the nearest `MQL4` above a `.mq4`, `MQL5` above a `.mq5`, either above a directory, else the directory or the file's directory) at the same path in the container, mounts each `-I` directory as it is, mounts each `--mt4-terminal`/`--mt5-terminal` directory read-only (unless a read-write mount already covers it), dedupes nested mounts, refuses `/`, sets `-w` to the current directory, and adds `--init`, the seccomp profile, the `mql-compiler-cache` volume on `/cache` and the caller's UID. Its own errors follow the output format: an `{"type":"error"}` record on stdout for JSON. `install.sh` rewrites its `PINNED_IMAGE` and `SECCOMP_PROFILE` lines.
- `action.yml` and `action/run.sh` are the GitHub Action: `run.sh prepare` picks the image (the release matching the action's ref) and the cache directory, `actions/cache` keeps the toolchain, `run.sh compile` runs `wrapper.sh`, turns the JSON records into `::error`/`::warning` annotations, writes the job summary and sets the outputs.
- `install.sh` pins a release image (or `:latest` with `--rolling`, or `:dev` with `MQL_COMPILER_ENV=dev`), installs the command and `seccomp/wine.json` next to it, or `--uninstall`s both along with the pinned image (never `:dev`), and refuses to overwrite a file without the `mql-compiler-managed-command` marker.

Data flow: `mql-compiler` (host) -> `docker run` -> `entrypoint.sh` -> Wine -> MetaEditor -> `.ex4`/`.ex5` next to the source.

## Stack

- Bash scripts, a Debian trixie image with Wine 11 from WineHQ (`winehq-stable`, 64-bit and `wine-stable-i386`, version and signing key pinned in the `Dockerfile`), Xvfb, osslsigncode, jq, inotify-tools.
- No MetaQuotes software in the image or the repo: the first run downloads the RoboForex installers (or `MQL_COMPILER_MT4_URL`/`MQL_COMPILER_MT5_URL`), checks their Authenticode signature (trusted chain, signing certificate's CN starting with "MetaQuotes", see SEC1), and installs them with `/auto`.
- Lint, scan and docs tools run from digest-pinned images in the `Makefile`: shellcheck, shfmt, hadolint, gitleaks, grype, and GitHub Pages' Jekyll build image.
- Docs: `docs/` is a GitHub Pages site (Jekyll, Just the Docs `v0.12.0` remote theme, the bundled `mocha` color scheme in `docs/_sass/`).
- CI: `.github/workflows/pipeline.yml` calling `psyb0t/reusable-github-workflows`. Every push runs `make lint` and `make test-ci` (the `code` job) and the Action itself against a freshly built image (the `action` job, `uses: ./`). A `master` push then builds and pushes `:latest` and `:sha-<commit>` (amd64 only, Grype scan reported to the Security tab). A `v*` tag waits for that commit's `master` run, promotes the same digest to `:vX.Y.Z`, cuts the GitHub release from the tag message, and publishes the skill to ClawHub.

## Layout

| Path | What it holds |
| --- | --- |
| `entrypoint.sh` | The image's program: sources, toolchain setup, include root, compile loop, output |
| `wrapper.sh` | The host `mql-compiler` command: mounts, UID, seccomp, then `docker run` |
| `install.sh` | Installs, upgrades and removes the command and its seccomp profile |
| `Dockerfile` | Debian trixie, WineHQ Wine 11, Xvfb, osslsigncode, jq, inotify-tools; copies only `entrypoint.sh` and `VERSION` |
| `VERSION` | The single release version, mirrored into `.agents/.codex-plugin/plugin.json` by `make version` |
| `action.yml`, `action/run.sh` | The composite GitHub Action |
| `seccomp/wine.json` | Docker's default seccomp profile plus `userfaultfd`, generated by `scripts/make-seccomp.sh` through `make seccomp` |
| `scripts/` | `make-seccomp.sh` and CI's retrying Docker Hub login, `ci-dockerhub-login.sh` |
| `tests/test.sh` | End-to-end suite, by hand (`/src`) and through `wrapper.sh` from other directories, against copies of `tests/fixtures/` |
| `tests/fixtures/` | An `MQL4` and an `MQL5` tree (experts, indicators, scripts, their own `Include` with a header that shadows a standard one, a `#resource` file, standard-library users, a broken file) and a loose file outside both. Other cases (symlinks, lowercase directories, an MT4 image resource, setup failures, a foreign-UID cache, the Action script, `install.sh`) build their files at run time |
| `tests/unit/` | Scripts that run inside the image and test entrypoint functions with one dependency stubbed |
| `docs/` | The documentation site (GitHub Pages) |
| `.agents/skills/mql-compiler/` | The agent skill published to ClawHub, and its `references/installation.md` |
| `.agents/.claude-plugin/`, `.agents/.codex-plugin/` | Claude Code and Codex plugin manifests |
| `.agents/rules/` | Rules for changing this repository |
| `.github/workflows/` | `pipeline.yml` plus repository housekeeping workflows |
| `THIRD_PARTY.md` | What the image redistributes and what the first run downloads |

## Commands

Docker, Make, Bash, `curl` and `jq` are enough. Every tool runs from a digest-pinned image.

```bash
make help              # every target
make build             # image as :dev, :v<VERSION>, :latest
make test              # first run installs the toolchain into .testing/cache (about 90 s); about 5 minutes after that
make test-all          # make test plus a real release install from Docker Hub
make test-ci           # make test-all under a 25-minute limit, prints the compiler log on failure (what CI runs)
make lint              # shellcheck, shfmt (-i 4 -ci), hadolint
make sec               # gitleaks, hadolint, grype
make install           # :dev image + command from this checkout
make docs              # build the documentation site into .testing/docs-site
make version V=X.Y.Z   # VERSION and .agents/.codex-plugin/plugin.json, no git
make seccomp           # regenerate seccomp/wine.json from Docker's pinned default profile
```

Check a docs change by building it with `make docs` and opening `.testing/docs-site`.

## Landmines

- MetaEditor's exit code is the number of files it compiled (1 for a good file, 0 for a failed one), not an error code. The verdict is the `Result:` line of its UTF-16 log.
- The MT4/MT5 setup launchers may exit at once and hand off to a child, or stay until the install is done. `wineserver -w` is what waits for the install, and Xvfb must stay up the whole time, or the child dies with the display. The web installer starts the terminal with `/install` when it is done, and none of them has a time limit, so `install_platform` runs the launcher and that wait inside one deadline (`wine_within`, `MQL_COMPILER_INSTALL_TIMEOUT`, 600 s) and stops what is left with `wineserver -k`. `wineboot --init` gets the same treatment (300 s). The v0.5.1 and v0.5.2 CI runs sat in the first install until GitHub cancelled them.
- `wineserver -p` (kept alive for the compile loop) needs an existing prefix, so it starts only after setup.
- Wine refuses a prefix owned by another UID. That is why the cache is per UID inside one volume, and why `/cache` is sticky and world-writable in the image.
- `/inc:` takes the `MQL4`/`MQL5` directory itself, not its `Include` subdirectory, and only one of them. It also breaks on a path with spaces (a mounted terminal's directory often has some). Hence the merged root in a staging directory under `/tmp`: `cp -rs` links of the standard `Include`, the user's `Include` linked over it with `--remove-destination` (user wins), and links to the user's other subdirectories for `#resource`.
- `/compile:` breaks on spaces too: MetaEditor writes no result at all. A source path with whitespace is compiled through a link in the staging directory (`stage_source`), and `read_log` maps every staging path back to the real file.
- MetaEditor deletes a failed file's old `.ex4`/`.ex5` itself, but not a read-only one and not when it writes no result, so `compile_one` deletes it first.
- Docker kills every process in the container when the entrypoint exits, so `finish` closes stdout and stderr and waits for the `tee` processes, or `last-run.log` loses its tail.
- One run at a time per UID: `acquire_run_lock` holds `flock` on `.run.lock` for the whole run, setup included. `--watch` releases it while it waits for changes and takes it again for each pass.
- stdout is a contract (JSON Lines by default). `compile_one` builds one JSON `file` record and `print_file_result` renders `--text` and `--format gnu` from that same record, so the formats cannot disagree. `die` writes its `error` record to fd 7, a copy of the real stdout, because it is often called inside a command substitution whose stdout is captured.
- The MetaEditor build comes from the `FileVersion` string in the executable's UTF-16 version resource (`metaeditor_build`, plain `grep -P`), so `--version` needs neither Wine nor a running terminal.
- `--watch` needs `tini` as PID 1 (`docker run --init`, which the wrapper passes); bash as PID 1 ignores SIGTERM and SIGINT. `inotifywait` runs in the background so the INT/TERM trap fires at once.
- osslsigncode's report lists the chain and timestamp certificates too, so `require_signer` checks only the first `Subject:` after `Signer's certificate:` for `/CN=MetaQuotes`.
- The installers do not unpack the standard library. The terminal does, into its `MQL4`/`MQL5` directory, on its first `/portable` start. `unpack_stdlib` starts it, waits for `Include/Trade/Trade.mqh` (MT5) or `Include/stdlib.mqh` (MT4), then `wineserver -k`.
- Cached terminals are portable directories at `drive_c/terminals/mt4` and `mt5`, not under `Program Files`: `make_portable` moves the installed directory there after the standard library is unpacked, and the first run on an older cache does the same move with no download. `find_metaeditor` looks only in the platform's terminal directory; `find_installed_metaeditor` is only for finding the installer's directory to move.
- Paths in the container must equal host paths for the output to make sense, which is why the wrapper mounts at the same path and passes `realpath`ed arguments. Mounting only `Experts` hides the user's `Include`.
- The image is amd64 only: MT4's MetaEditor is 32-bit and needs Wine's i386 packages.
- Under Linux 7.0 (Ubuntu 26.04, GitHub's `ubuntu-latest`), Docker's default seccomp filter refuses `userfaultfd`, which Wine 11 calls at startup, and Wine stops with `wine: socket : Function not implemented`. `seccomp/wine.json` is Docker's default profile plus that call (`make seccomp`, base pinned by checksum). The wrapper passes it as `--security-opt seccomp=` (`SECCOMP_PROFILE`, written by `install.sh` like `PINNED_IMAGE`, or `MQL_COMPILER_SECCOMP`), `action/run.sh` points the wrapper at the action's own copy, and every container `tests/test.sh` starts gets it.
- Debian's Wine 10.0 cannot run MetaTrader 5 build 6304 or later: the terminal stops at a modal "A debugger has been found running in your system" (so the installer's leftover `terminal64.exe /install` and `unpack_stdlib` wait forever) and MetaEditor's `/compile` exits 222 with no log. WineHQ's Wine 11.0 runs both. Raise `WINE_VERSION` in the `Dockerfile` only after a fresh install and `make test` pass on it.
- The reusable code workflow runs `make lint` and `make test-ci` with no secrets, so those pulls from Docker Hub are anonymous. The `action` job and the image workflow log in with `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN` (the image workflow needs Read, Write and Delete scope).
- Jekyll runs Liquid over every page in `docs/`, so a `${{ ... }}` workflow expression in a code block renders as nothing. Wrap such a block in `<!-- {% raw %} -->` and `<!-- {% endraw %} -->`.

## Rules

Rules for every change live in `.agents/rules/`, one file per topic. Read the ones that match what you are about to touch before you edit.

| File | Prefix | Covers |
| --- | --- | --- |
| `architecture.md` | ARC | The three scripts and what each owns, the run order, mounts, the include root, the cache |
| `bash-code.md` | SH | Bash as practised here: the `ERR` trap, exit-code constants, Bash 3.2 in the wrapper, logging, stdout versus stderr |
| `testing.md` | TST | The end-to-end suite, unit scripts, fixtures, the test cache |
| `security.md` | SEC | Installer signature checks, the container's privileges, where pins live, CI secrets |
| `docs-and-releases.md` | DOC | Which file owns which docs fact, the docs site, voice, CHANGELOG heading, `make version`, tags, CI publishing |
| `chat.md` | CHAT | How an agent signs off its chat replies, PR, issue and discussion comments, messages and commit messages |

Every rule starts with a bold ID: one prefix per file and a number counted from 1 in that file. Cite rules by ID (for example "TST3") in reviews, commits and code comments. IDs are never reused or renumbered: a removed rule's ID stays retired, and a new rule takes the next free number in its file. Where a test, lint or script enforces a rule, the rule names it. When a rule and the code disagree, the code and its tests win; fix the rule in the same change.
