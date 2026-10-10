# Changelog

All notable changes per release. Versions follow [semver](https://semver.org) pre-1.0 conventions: minor bumps may include breaking changes (called out explicitly), patch bumps are docs, build and fixes only.

## v0.2.0, 2026-10-10

- Standard-library includes work. `#include <Trade/Trade.mqh>`, `<stdlib.mqh>` and the rest failed with "file not found" in v0.1.x because the installers leave the standard library packed and MetaEditor takes a single include root. Setup now starts each terminal once to unpack its `MQL4`/`MQL5` folder, and an existing cache does this on its next run without a reinstall.
- Every compile gets a temporary include root: the terminal's standard `Include` with the `Include` of the nearest `MQL4`/`MQL5` folder above the source laid over it, plus links to that folder's other subfolders. Your headers and the standard ones both resolve, a header of yours with the same path as a standard one wins, and `#resource "\\Files\\..."` paths resolve. Nothing is written into your folders or the toolchain.
- A source outside any `MQL4`/`MQL5` folder compiles against the standard library alone.
- Paths can be absolute or relative and sit anywhere; no `cd` needed. The command mounts the nearest `MQL4`/`MQL5` folder above each path (or the folder, or the file's folder) at the same path inside the container and runs in the current folder. Output paths are relative to the current folder when inside it, absolute otherwise. In v0.1.x paths had to be inside the current folder; every path that worked then still works.
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
