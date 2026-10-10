# Changelog

All notable changes per release. Versions follow [semver](https://semver.org) pre-1.0 conventions: minor bumps may include breaking changes (called out explicitly), patch bumps are docs, build and fixes only.

## v0.1.0, 2026-10-10

- First release. `psyb0t/mql-compiler` compiles `.mq4` and `.mq5` files with MetaEditor under Wine 10 on Debian trixie, writes the `.ex4` and `.ex5` next to the sources, prints errors and warnings with file, line and column, and exits `0` when everything compiled, `1` on compile errors and `2` on bad usage or a failed setup.
- The first run downloads the MT4 and MT5 installers (RoboForex's by default, overridable with `MQL_COMPILER_MT4_URL` and `MQL_COMPILER_MT5_URL`), refuses any that MetaQuotes did not sign, and installs them into `/cache`, one folder per user ID.
- `#include <...>` resolves against the nearest `MQL4` or `MQL5` folder above each source.
- `install.sh` installs the `mql-compiler` command per user (`~/.local/bin`) or system wide (`/usr/local/bin`), pinned to the newest release image or `:latest` with `--rolling`, and keeps the toolchain in the `mql-compiler-cache` Docker volume. `--uninstall` removes the command.
- `.agents/skills/mql-compiler` is the agent skill, published to ClawHub.
