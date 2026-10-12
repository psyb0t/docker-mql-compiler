# Changelog

All notable changes per release. Versions follow [semver](https://semver.org) pre-1.0 conventions: minor bumps may include breaking changes (called out explicitly), patch bumps are docs, build and fixes only.

## Unreleased

- Added FTMO to the README's recommended brokers and prop firms, with its MT4 and MT5 support and simulated trading accounts described.

## v0.5.0, 2026-10-10

- The cached MT4 and MT5 terminals are now portable folders, `terminals/mt4` and `terminals/mt5` in the cache volume, instead of installs under `Program Files`. After installing a terminal and unpacking its standard library, setup moves its folder there, and every compile uses it exactly like a `--mt4-terminal`/`--mt5-terminal` folder. An existing cache is moved on its next run, with no download; MetaEditor builds stay as they were.

## v0.4.0, 2026-10-10

- `--mt4-terminal DIR` and `--mt5-terminal DIR` compile with the MetaEditor and standard library of a portable terminal you already have, instead of the cached install. The folder is mounted read-only and nothing is written into it, except the `.ex4`/`.ex5` of a source compiled from inside its own `MQL4`/`MQL5` folder. The cached toolchain stays as it was. A folder without MetaEditor, or whose terminal has never been started and so has not unpacked its standard library, is exit `2`. `--version` with the option reports that terminal's build.
- A platform given its own terminal is never downloaded or installed, and a compile now installs only the platforms its sources need. Before, the first run always installed both MT4 and MT5; now a first run of only `.mq5` files installs MT5 alone, and MT4 follows the first time a `.mq4` is compiled. `--setup`, `--update` and `--watch` still install both.

## v0.3.2, 2026-10-10

- Tests cover every feature. New end-to-end cases: a first run whose installer cannot be downloaded or has no signature, `--update` failing and putting the old toolchain back, `--setup`, a cache folder owned by another UID, the installer URL reaching the image, symlinks, lowercase `mql5` folders, the `-Idir` form, quotes in paths, an MT4 image `#resource`, `--watch` reacting to an `-I` folder and letting other runs in between passes, the GitHub Action's annotations, job summary and outputs, and `install.sh` (dev install, refusing foreign files, uninstall removing the pinned image).
- `tests/unit/` runs entrypoint functions inside the image with one dependency stubbed: every branch of the installer signature check, including the revocation-list fallback, and a MetaEditor that writes no result.
- `make test-all` adds a real release and `--rolling` install from Docker Hub; CI runs it.
- The entrypoint runs `main` only when executed, so the unit tests can source it. No behavior changes.

## v0.3.1, 2026-10-10

- Documentation only. The README's agent integrations section lists [peen](https://github.com/psyb0t/peen) among the agents the skill works with.

## v0.3.0, 2026-10-10

- Breaking: results on stdout are JSON Lines by default. Each source gets a `file` record with its status, output path, error and warning counts, and every message as `{severity, file, line, column, code, text}`. A `summary` record follows each pass, and a run that cannot start prints an `error` record instead. The old `OK`/`FAIL` lines are behind `--text`. See "What comes out" in the README.
- `--format gnu` prints `path:line:column: severity: text [code]` lines that editors jump to; `--format json|text|gnu` picks any of the three.
- `--werror` counts a file with warnings as failed.
- `-I DIR` / `--include DIR` adds an include folder outside the `MQL4`/`MQL5` tree, such as a shared library. The command mounts it, and it sits between the standard library and your own `Include`, which still wins.
- `--watch` compiles, then compiles again whenever a `.mq4`, `.mq5` or `.mqh` under the given paths changes, until Ctrl-C. It lets other runs use the cache between passes.
- `--version` prints the image version and the MetaEditor builds in the cache. `--update` reinstalls MT4 and MT5 from the newest installers and puts the old toolchain back if that fails.
- A GitHub Action (`uses: psyb0t/docker-mql-compiler@v0.3.0`) compiles in CI, marks every error and warning on its source line, writes a job summary, and keeps the toolchain in the Actions cache.
- The command's own errors (a missing path, refusing `/`) are JSON `error` records on stdout too, and it runs the container with `--init` so Ctrl-C and `docker stop` reach the compiler.
- The README lists recommended brokers.

## v0.2.1, 2026-10-10

- Paths with spaces compile. MetaEditor wrote no result for a source whose path had a space in it, so every such file failed with "MetaEditor wrote no result". The file is now compiled through a space-free link to its `MQL4`/`MQL5` folder (or its own folder when loose), and the messages show the real paths.
- A stale `.ex4`/`.ex5` no longer survives a failed compile. MetaEditor deletes the old output when a file has errors, but not a read-only one and not when it writes no result. The old output is now deleted before each file compiles.
- Two runs at once no longer collide. They shared one Wine prefix and one log file; now a run holds a lock for its whole length, and a second run logs that it is waiting and starts when the first ends.
- The run log keeps its last lines. A run that failed quickly could leave `last-run.log` empty, because the container exited before the copy was written. The script now waits for it.
- Errors in standard headers point at the real file, its path in the toolchain. They showed the header under your own `Include` folder, where no such file exists.
- A path with `&` in it no longer garbles the messages. Path rewriting uses plain string replacement instead of `sed`, and drops the current folder only where a path starts.
- A `.mq4` inside an `MQL5` folder inside an `MQL4` folder finds its includes. The command mounted the nearest `MQL4` or `MQL5` folder, while the compiler looks for `MQL4` above a `.mq4` and `MQL5` above a `.mq5`; the command now mounts the folder the compiler uses.
- Running with no path from `/` fails with exit `2` and a message, instead of Docker refusing the mount with exit `125`.
- The signer check reads only the signing certificate. It accepted "MetaQuotes" anywhere in any subject of the report; it now requires the signing certificate's common name to start with `MetaQuotes`.
- `--uninstall` removes the image the command was pinned to. The local `:dev` image and the cache volume stay.
- The README walks through a run step by step: the file order, one file at a time in one container, how the extension picks MT4 or MT5, how the `MQL4`/`MQL5` folder picks the includes, where the `.ex4`/`.ex5` and the run log go, and how to read the log.
- The docs no longer claim files compile in path order across arguments. The order is the arguments as given, each folder's files sorted, a duplicate only once.
- The exit codes are documented in full: no sources found exits `2`, a file MetaEditor wrote no result for counts as `1`, and a Docker failure returns Docker's own code (usually `125`).
- The README, the skill and the installation reference cover the amd64-only image, what the container can see, symlinks, parallel runs, switching installers with a new `MQL_COMPILER_VOLUME`, and every error message the tool prints.
- `--help` lists `--setup` and `-h` in its synopsis and says where the run log goes.
- `.agents/rules/` holds the project rules for contributors, linked from `AGENTS.md`.

## v0.2.0, 2026-10-10

- Standard-library includes work. `#include <Trade/Trade.mqh>`, `<stdlib.mqh>` and the rest failed with "file not found" in v0.1.x because the installers leave the standard library packed and MetaEditor takes a single include root. Setup now starts each terminal once to unpack its `MQL4`/`MQL5` folder.
- Every compile gets a temporary include root: the terminal's standard `Include` with the `Include` of the nearest `MQL4`/`MQL5` folder above the source laid over it, plus links to that folder's other subfolders. Your headers and the standard ones both resolve, a header of yours with the same path as a standard one wins, and `#resource "\\Files\\..."` paths resolve. Nothing is written into your folders or the toolchain.
- A source outside any `MQL4`/`MQL5` folder compiles against the standard library alone.
- Paths can be absolute or relative and sit anywhere; no `cd` needed. The command mounts the nearest `MQL4`/`MQL5` folder above each path (or the folder, or the file's folder) at the same path inside the container and runs in the current folder. Output paths are relative to the current folder when inside it, absolute otherwise.
- Running with no arguments inside a subfolder such as `MQL5/Experts` now finds `MQL5/Include`.
- A file named twice (directly and through its folder) compiles once.
- `--help`, the README, the agent skill and its installation reference explain the tree layout, include resolution, mounts and first-run setup.
- The tests cover the standard library on both platforms, indicators and scripts on both, a user header shadowing a standard one, `#resource`, a missing resource, a loose file, and the command run from other folders with relative and absolute paths.

## v0.1.2, 2026-10-10

- The README is rewritten in the house voice, with the same commands and facts.
- The agent skill has an installation reference, `.agents/skills/mql-compiler/references/installation.md`: per-user and system-wide installs, upgrades, uninstalling, custom installers, checks and troubleshooting.
- `CLAUDE.md` is gone; `AGENTS.md` is the agent guide.

## v0.1.1, 2026-10-10

- The installer signature check survives a flaky revocation server. It needs the certificate authority's revocation list, and when that download failed (as it did on GitHub's runners for v0.1.0, so no image was published) the whole first run failed. The check now retries three times. If the list still can't be fetched, it verifies the signature, digest and certificate chain without the online revocation lookup and logs a warning with `reason=crl_unreachable`. A bad digest, an untrusted chain or a revoked certificate still fails at once.

## v0.1.0, 2026-10-10

- First release. `psyb0t/mql-compiler` compiles `.mq4` and `.mq5` files with MetaEditor under Wine 10 on Debian trixie, writes the `.ex4` and `.ex5` next to the sources, prints errors and warnings with file, line and column, and exits `0` when everything compiled, `1` on compile errors and `2` on bad usage or a failed setup.
- The first run downloads the MT4 and MT5 installers (RoboForex's by default, overridable with `MQL_COMPILER_MT4_URL` and `MQL_COMPILER_MT5_URL`), refuses any that MetaQuotes did not sign, and installs them into `/cache`, one folder per user ID.
- `#include <...>` resolves against the nearest `MQL4` or `MQL5` folder above each source.
- `install.sh` installs the `mql-compiler` command per user (`~/.local/bin`) or system wide (`/usr/local/bin`), pinned to the newest release image or `:latest` with `--rolling`, and keeps the toolchain in the `mql-compiler-cache` Docker volume. `--uninstall` removes the command.
- `.agents/skills/mql-compiler` is the agent skill, published to ClawHub.
