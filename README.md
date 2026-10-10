# docker-mql-compiler

[![CI](https://github.com/psyb0t/docker-mql-compiler/actions/workflows/pipeline.yml/badge.svg?branch=master)](https://github.com/psyb0t/docker-mql-compiler/actions/workflows/pipeline.yml)
[![version](https://raw.githubusercontent.com/psyb0t/docker-mql-compiler/badges/version.svg)](https://github.com/psyb0t/docker-mql-compiler/releases)
[![license](https://raw.githubusercontent.com/psyb0t/docker-mql-compiler/badges/license.svg)](LICENSE)
[![Docker Pulls](https://img.shields.io/docker/pulls/psyb0t/mql-compiler?style=flat-square)](https://hub.docker.com/r/psyb0t/mql-compiler)

Compile MQL4 and MQL5 on Linux without booting a goddamn Windows box. One command, and MetaQuotes' own MetaEditor wakes up inside a Wine container, chews through your `.mq4` and `.mq5` files, shits out `.ex4` and `.ex5` right next to them, and screams the compiler errors into your terminal like a proper CLI tool should.

No Windows. No MetaTrader window to babysit. No broker account. No clicking "Compile" in a GUI that looks like it escaped from 2009.

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

- [What this fucker does](#what-this-fucker-does)
- [Quick start](#quick-start)
- [Using the damn thing](#using-the-damn-thing)
- [How the sausage gets made](#how-the-sausage-gets-made)
- [Environment variables](#environment-variables)
- [Running the image by hand](#running-the-image-by-hand)
- [Agent integrations](#agent-integrations)
- [Development](#development)
- [License](#license)

> [!WARNING]
> This compiles your EA. It does not make your EA any good. If the thing compiles clean and then martingales your account into the ground, that one's on you.

## What this fucker does

- **Real MetaEditor, both flavours.** MT4's 32-bit `metaeditor.exe` for `.mq4`, MT5's `MetaEditor64.exe` for `.mq5`. The actual MetaQuotes compilers, not some reverse-engineered knockoff that chokes on half your includes.
- **One command, CLI-shaped.** Point it at files or folders, get `OK`/`FAIL` per file, compiler errors with file, line and column, and an exit code your scripts and CI can trust: `0` clean, `1` compile errors, `2` you fucked up the arguments.
- **Your `Include` folder just works.** `#include <...>` resolves against the nearest `MQL4` or `MQL5` folder above each source, so a terminal-style tree compiles against its own headers.
- **No MetaQuotes binaries in the image.** The first run downloads the MT4 and MT5 installers, refuses to run any that MetaQuotes didn't sign, and caches the installed toolchain in a Docker volume. After that, a compile takes a few seconds.
- **Installs like a normal tool.** One `curl | bash`, one file on your `PATH`, no config folder crapping up your home directory.

## Quick start

All you need is Docker, installed and running.

```bash
# per user: drops the command into ~/.local/bin
curl -fsSL https://raw.githubusercontent.com/psyb0t/docker-mql-compiler/master/install.sh | bash

# system wide: /usr/local/bin, for the whole box
curl -fsSL https://raw.githubusercontent.com/psyb0t/docker-mql-compiler/master/install.sh | sudo bash -s -- --system
```

The installer pins the newest release image and writes the `mql-compiler` command. That single file is the entire install. Run the installer again to upgrade; it throws away the image it replaced. `--rolling` pins `:latest` instead of a release, and `--uninstall` gets rid of the command.

Then go to a folder full of MQL sources and run `mql-compiler`. The first run spends about a minute and a half downloading and installing MT4 and MT5 into a Docker volume. Every run after that takes seconds.

## Using the damn thing

```bash
mql-compiler                  # every .mq4 and .mq5 under the current directory
mql-compiler MQL5/Experts     # one folder
mql-compiler Foo.mq5 Bar.mq4  # these exact files
mql-compiler --setup          # just download and install the toolchain, compile nothing
mql-compiler --help
```

- **Paths** are relative to the current directory, which is the only folder the container gets to see. A file outside it can't be compiled from there, so `cd` closer.
- **Outputs** land next to their sources and belong to you, not root: `Foo.mq5` gives `Foo.ex5`, `Bar.mq4` gives `Bar.ex4`.
- **Includes:** `#include <...>` looks in the nearest folder above the source named `MQL4` or `MQL5`, which is how a terminal's data folder is laid out. Run it inside your `MQL5` folder or one level above it and your experts compile against that folder's own `Include`. `#include "..."` resolves next to the source, as always.
- **Output:** one `OK` or `FAIL` line per file, then that file's errors and warnings. Progress and logs go to stderr as JSON lines, so `mql-compiler 2>/dev/null` shows nothing but the results.
- **Exit status:** `0` every file compiled, `1` at least one has compile errors, `2` bad path, bad option, or the toolchain couldn't be installed.

## How the sausage gets made

- **The image** is Debian trixie with Wine 10 (the 64-bit half plus the 32-bit half that MT4's ancient MetaEditor needs), Xvfb as a fake display nobody ever looks at, and one bash script. Not a single MetaQuotes byte in it.
- **The toolchain:** on the first run the script downloads the MT4 and MT5 installers, checks that each is validly code-signed by MetaQuotes (anything else gets refused), and installs both silently under Wine. The installers default to RoboForex's; point `MQL_COMPILER_MT4_URL` and `MQL_COMPILER_MT5_URL` at any broker's or MetaQuotes' own. The compiler inside is the same either way.
- **The cache:** the installed toolchain is about 2 GB and lives in the Docker volume `mql-compiler-cache`, one folder per user ID, so everybody on a box shares a single volume. `docker volume rm mql-compiler-cache` nukes it and the next run installs again. The container runs as your UID, so the compiled files are yours.
- **Compiling:** every file goes through MetaEditor's command-line compiler with `/inc` pointed at the source's `MQL4` or `MQL5` folder. MetaEditor's exit code is a lying piece of shit (it usually returns 1 when everything went fine), so the script ignores it, reads the `Result:` line of the compile log instead, and turns the Windows paths in there back into yours.

## Environment variables

The `mql-compiler` command reads these:

| Variable | Default | What it does |
|---|---|---|
| `MQL_COMPILER_IMAGE` | the pinned release | Runs some other image |
| `MQL_COMPILER_VOLUME` | `mql-compiler-cache` | Docker volume that holds the toolchain |
| `MQL_COMPILER_MT4_URL` | RoboForex's MT4 installer | MT4 installer for the first run |
| `MQL_COMPILER_MT5_URL` | RoboForex's MT5 installer | MT5 installer for the first run |

The installer URLs only matter while the toolchain is being installed. To switch an existing cache to another broker's installers, kill the volume first.

## Running the image by hand

The command is just a thin `docker run`. Doing it yourself:

```bash
docker run --rm \
  --user "$(id -u):$(id -g)" \
  -v "$PWD":/src \
  -v mql-compiler-cache:/cache \
  psyb0t/mql-compiler:latest MQL5/Experts
```

Mount your sources at `/src` and keep `/cache` on a volume. Skip the volume and every single run reinstalls the whole toolchain, which gets old fast.

## Agent integrations

[`.agents/skills/mql-compiler`](.agents/skills/mql-compiler/SKILL.md) teaches a coding agent (Claude Code, Codex, OpenClaw) to install the command, compile, and read the errors without making shit up. Every release publishes it to [ClawHub](https://clawhub.ai).

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

Every tool runs from a digest-pinned image, so the host needs Docker and Make and nothing else. `make test` installs the toolchain into `.testing/cache` the first time and reuses it after. CI runs `make lint` and `make test`, builds and pushes the image with a Grype scan on every push, and ships the skill to ClawHub on release tags.

## License

[WTFPL](LICENSE). Do what the fuck you want.

MetaTrader, MetaEditor and their installers are MetaQuotes software and none of it lives in this repo or the image. The first run downloads it from the broker, and MetaQuotes' license covers it. See [THIRD_PARTY.md](THIRD_PARTY.md).
