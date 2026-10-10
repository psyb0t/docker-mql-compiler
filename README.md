# docker-mql-compiler

[![CI](https://github.com/psyb0t/docker-mql-compiler/actions/workflows/pipeline.yml/badge.svg?branch=master)](https://github.com/psyb0t/docker-mql-compiler/actions/workflows/pipeline.yml)
[![version](https://raw.githubusercontent.com/psyb0t/docker-mql-compiler/badges/version.svg)](https://github.com/psyb0t/docker-mql-compiler/releases)
[![license](https://raw.githubusercontent.com/psyb0t/docker-mql-compiler/badges/license.svg)](LICENSE)
[![Docker Pulls](https://img.shields.io/docker/pulls/psyb0t/mql-compiler?style=flat-square)](https://hub.docker.com/r/psyb0t/mql-compiler)

Compile MQL4 and MQL5 on Linux with one command. No Windows, no MetaTrader window, no account. It runs MetaQuotes' own MetaEditor under Wine in a container, compiles your `.mq4` and `.mq5` files, drops the `.ex4` and `.ex5` next to them, and exits with the compiler's errors in your terminal.

```console
$ mql-compiler
OK   MQL4/Experts/Grid.mq4 -> MQL4/Experts/Grid.ex4 (0 warnings)
FAIL MQL5/Experts/Scalper.mq5 (1 errors, 0 warnings)
     MQL5/Experts/Scalper.mq5(41,7) : error 256: undeclared identifier 'lots'
OK   MQL5/Indicators/Bands.mq5 -> MQL5/Indicators/Bands.ex5 (2 warnings)
$ echo $?
1
```

## Contents

- [Quick start](#quick-start)
- [Using `mql-compiler`](#using-mql-compiler)
- [How it works](#how-it-works)
- [Environment variables](#environment-variables)
- [Running the image directly](#running-the-image-directly)
- [Agent integrations](#agent-integrations)
- [Development](#development)
- [License](#license)

## Quick start

Docker installed and running is the only prerequisite.

```bash
# per user: installs ~/.local/bin/mql-compiler
curl -fsSL https://raw.githubusercontent.com/psyb0t/docker-mql-compiler/master/install.sh | bash

# system wide: installs /usr/local/bin/mql-compiler
curl -fsSL https://raw.githubusercontent.com/psyb0t/docker-mql-compiler/master/install.sh | sudo bash -s -- --system
```

The installer pins the newest release image and writes the `mql-compiler` command. That one file is the whole install; there is no config folder. Run the installer again to upgrade, and it drops the image it replaced. `--rolling` pins `:latest` instead of a release, and `--uninstall` removes the command.

Then, in a folder with MQL sources, run `mql-compiler`. The first run downloads and installs MT4 and MT5 into a Docker volume, about a minute and a half. After that a compile takes a few seconds.

## Using `mql-compiler`

```bash
mql-compiler                  # every .mq4 and .mq5 under the current directory
mql-compiler MQL5/Experts     # one folder
mql-compiler Foo.mq5 Bar.mq4  # these files
mql-compiler --setup          # only download and install the toolchain
mql-compiler --help
```

- **Paths** are relative to the current directory, the only folder the container sees. A file outside it can't be compiled from there.
- **Outputs** land next to their sources and belong to you: `Foo.mq5` gives `Foo.ex5`, `Bar.mq4` gives `Bar.ex4`.
- **Includes:** `#include <...>` resolves against the nearest folder above the source named `MQL4` or `MQL5`, the layout of a terminal's data folder. Run it inside your `MQL5` folder or one level above, and experts compile against that folder's own `Include`. `#include "..."` resolves next to the source as usual.
- **Output:** one `OK` or `FAIL` line per file, then the compiler's errors and warnings with file, line and column. Progress goes to stderr as JSON lines, so `mql-compiler 2>/dev/null` shows only the results.
- **Exit status:** `0` every file compiled, `1` at least one has compile errors, `2` bad usage or a toolchain that could not be set up.

## How it works

- **The image** is Debian trixie with Wine 10 (64-bit plus the 32-bit half that MT4's MetaEditor needs), Xvfb as an invisible display, and the compile script. It contains no MetaQuotes software.
- **The toolchain:** the first run downloads the MT4 and MT5 installers, refuses any that is not validly code-signed by MetaQuotes, and installs both silently under Wine. The default installers are RoboForex's; `MQL_COMPILER_MT4_URL` and `MQL_COMPILER_MT5_URL` pick another broker's or MetaQuotes' own. The compiler is the same either way.
- **The cache:** the installed toolchain, about 2 GB, lives in the Docker volume `mql-compiler-cache`, one folder per user ID, so everyone on a machine shares one volume. `docker volume rm mql-compiler-cache` frees it, and the next run installs again. The container runs as your UID, so compiled files are yours.
- **Compiling:** each file goes to MetaEditor's command-line compiler with `/inc` pointing at the source's `MQL4` or `MQL5` folder. MetaEditor's exit code can't be trusted (it often returns 1 on success), so the script reads the `Result:` line of its log and turns the Windows paths in it back into yours.

## Environment variables

Read by the `mql-compiler` command:

| Variable | Default | What it does |
|---|---|---|
| `MQL_COMPILER_IMAGE` | the pinned release | Runs another image |
| `MQL_COMPILER_VOLUME` | `mql-compiler-cache` | Docker volume that holds the toolchain |
| `MQL_COMPILER_MT4_URL` | RoboForex's MT4 installer | MT4 installer for the first run |
| `MQL_COMPILER_MT5_URL` | RoboForex's MT5 installer | MT5 installer for the first run |

The installer URLs matter only while the toolchain is being installed. To switch an existing cache to another broker's installers, remove the volume first.

## Running the image directly

The command is a thin `docker run`. By hand:

```bash
docker run --rm \
  --user "$(id -u):$(id -g)" \
  -v "$PWD":/src \
  -v mql-compiler-cache:/cache \
  psyb0t/mql-compiler:latest MQL5/Experts
```

Mount the sources at `/src` and keep `/cache` on a volume. Without the volume every run installs the toolchain again.

## Agent integrations

[`.agents/skills/mql-compiler`](.agents/skills/mql-compiler/SKILL.md) teaches a coding agent (Claude Code, Codex, OpenClaw) to install the command, compile, and read the results. Every release publishes it to [ClawHub](https://clawhub.ai).

## Development

```bash
make build      # build psyb0t/mql-compiler:dev, :v<VERSION> and :latest
make test       # compile tests/fixtures with the built image and check the results
make lint       # shellcheck and shfmt on the scripts, hadolint on the Dockerfile
make format     # rewrite the scripts with shfmt
make sec        # gitleaks secrets scan, hadolint, grype vulnerability scan of the image
make install    # build :dev and install the command from this checkout
make uninstall  # remove the installed command
make version    # print the version; V=X.Y.Z sets it
make help       # every target
```

Every tool runs from a digest-pinned image, so the host needs only Docker and Make. `make test` installs the toolchain into `.testing/cache` on its first run and reuses it afterwards. CI runs `make lint` and `make test`, builds and pushes the image with a Grype scan on every push, and publishes the skill to ClawHub on release tags.

## License

[WTFPL](LICENSE). MetaTrader, MetaEditor and their installers are MetaQuotes software. They are not in this repository or the image; the first run downloads them from the broker. See [THIRD_PARTY.md](THIRD_PARTY.md).
