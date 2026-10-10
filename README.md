# docker-mql-compiler

[![CI](https://github.com/psyb0t/docker-mql-compiler/actions/workflows/pipeline.yml/badge.svg?branch=master)](https://github.com/psyb0t/docker-mql-compiler/actions/workflows/pipeline.yml)
[![version](https://raw.githubusercontent.com/psyb0t/docker-mql-compiler/badges/version.svg)](https://github.com/psyb0t/docker-mql-compiler/releases)
[![license](https://raw.githubusercontent.com/psyb0t/docker-mql-compiler/badges/license.svg)](LICENSE)
[![Docker Pulls](https://img.shields.io/docker/pulls/psyb0t/mql-compiler?style=flat-square)](https://hub.docker.com/r/psyb0t/mql-compiler)

Compile MQL4 and MQL5 on Linux without booting a goddamn Windows box. One command, and MetaQuotes' own MetaEditor wakes up inside a Wine container, chews through your `.mq4` and `.mq5` files, shits out `.ex4` and `.ex5` right next to them, and hands back every error as JSON your agent can actually use. Humans get `--text`.

No Windows. No MetaTrader window to babysit. No broker account. No clicking "Compile" in a GUI that looks like it escaped from 2009.

```console
$ mql-compiler 2>/dev/null
{"type":"file","source":"MQL4/Experts/Grid.mq4","platform":"mt4","status":"ok","output":"MQL4/Experts/Grid.ex4","errors":0,"warnings":0,"messages":[]}
{"type":"file","source":"MQL5/Experts/Scalper.mq5","platform":"mt5","status":"failed","output":null,"errors":1,"warnings":0,"messages":[{"severity":"error","file":"MQL5/Experts/Scalper.mq5","line":41,"column":7,"code":256,"text":"undeclared identifier 'lots'"}]}
{"type":"summary","total":2,"compiled":1,"failed":1,"werror":false}
$ echo $?
1

$ mql-compiler --text 2>/dev/null
OK   MQL4/Experts/Grid.mq4 -> MQL4/Experts/Grid.ex4 (0 warnings)
FAIL MQL5/Experts/Scalper.mq5 (1 errors, 0 warnings)
     MQL5/Experts/Scalper.mq5(41,7) : error 256: undeclared identifier 'lots'
```

## Contents

- [What this fucker does](#what-this-fucker-does)
- [Quick start](#quick-start)
- [Using the damn thing](#using-the-damn-thing)
  - [Bring your own terminal](#bring-your-own-terminal)
- [How the sausage gets made](#how-the-sausage-gets-made)
- [Environment variables](#environment-variables)
- [GitHub Action](#github-action)
- [Running the image by hand](#running-the-image-by-hand)
- [Agent integrations](#agent-integrations)
- [Development](#development)
- [Recommended brokers](#recommended-brokers)
- [License](#license)

> [!WARNING]
> This compiles your EA. It does not make your EA any good. If the thing compiles clean and then martingales your account into the ground, that one's on you.

## What this fucker does

- **Real MetaEditor, both flavours.** MT4's 32-bit `metaeditor.exe` for `.mq4`, MT5's `MetaEditor64.exe` for `.mq5`. The actual MetaQuotes compilers, not some reverse-engineered knockoff that chokes on half your includes.
- **Built for agents.** Point it at files or folders and get one JSON record per file: status, output path, and every error and warning with file, line, column and code. No regex-scraping MetaEditor's log. Plus an exit code your scripts and CI can trust: `0` clean, `1` something failed, `2` you fucked up the arguments or the setup died. `--text` and `--format gnu` are there for meatbags and their editors.
- **CI in four lines.** A GitHub Action compiles your EAs on every push and marks the errors right on the source lines in the PR.
- **Dev loop.** `--watch` recompiles on save, `--werror` fails on warnings, `-I` pulls in a shared library from wherever it lives.
- **Includes work like in the terminal.** `#include <Trade/Trade.mqh>` finds the MetaQuotes standard library, `#include <MyStuff/Thing.mqh>` finds your own `Include` folder, and if you hacked a standard header in your tree, your copy wins.
- **Point it at anything, from anywhere.** Files, folders, relative paths, absolute paths, MT4 and MT5 mixed in one run. Experts, indicators, scripts, libraries, it doesn't give a shit what the program is. No `cd` dance.
- **No MetaQuotes binaries in the image.** The first run downloads the MT4 and MT5 installers, refuses to run any that MetaQuotes' own certificate didn't sign, and caches the installed toolchain in a Docker volume. After that, a compile takes a few seconds.
- **Installs like a normal tool.** One `curl | bash`, one file on your `PATH`, no config folder crapping up your home directory.

## Quick start

All you need is Docker, installed and running, on an x86-64 (amd64) box. MT4's MetaEditor is 32-bit Windows code and needs Wine's i386 half, so there's no ARM image: Apple Silicon and other ARM machines are out unless Docker emulates amd64 for you.

```bash
# per user: drops the command into ~/.local/bin
curl -fsSL https://raw.githubusercontent.com/psyb0t/docker-mql-compiler/master/install.sh | bash

# system wide: /usr/local/bin, for the whole box
curl -fsSL https://raw.githubusercontent.com/psyb0t/docker-mql-compiler/master/install.sh | sudo bash -s -- --system
```

The installer pins the newest release image and writes the `mql-compiler` command. That single file is the entire install. Run the installer again to upgrade; it throws away the image it replaced. `--rolling` pins `:latest` instead of a release, and `--uninstall` gets rid of the command and its image. The cache volume stays, since every user on the box shares it; `docker volume rm mql-compiler-cache` takes it out.

Then go to a folder full of MQL sources and run `mql-compiler`. The first run spends about a minute and a half downloading and installing MT4 and MT5 into a Docker volume. Every run after that takes seconds.

## Using the damn thing

```bash
mql-compiler [OPTIONS] [FILE or FOLDER ...]

mql-compiler                                    # every .mq4 and .mq5 under the current folder
mql-compiler ~/trading/MQL5/Experts             # one folder, recursively
mql-compiler MQL5/Experts/Scalper.mq5           # just the one EA out of your hundred
mql-compiler ~/a/MQL4/Experts/Grid.mq4 Foo.mq5  # files from all over the place, both platforms
mql-compiler --text MQL5                        # OK/FAIL lines for humans
mql-compiler --watch MQL5/Experts               # recompile on every save until Ctrl-C
mql-compiler -I ~/libs/mql5 MQL5                # a shared library outside the tree
mql-compiler --mt5-terminal ~/mt/RoboForex MQL5 # compile with your own portable terminal's MetaEditor
mql-compiler --setup                            # just download and install the toolchain, compile nothing
mql-compiler --help
```

| Option | What it does |
|---|---|
| `-I DIR`, `--include DIR` | Lays `DIR` over the standard `Include`, so `#include <MyLib/x.mqh>` also finds `DIR/MyLib/x.mqh`. Repeat it for more folders. The folder gets mounted too. |
| `--mt4-terminal DIR`, `--mt5-terminal DIR` | Compiles `.mq4` (or `.mq5`) files with the MetaEditor and standard library of the portable terminal in `DIR` instead of the cached one. See [bring your own terminal](#bring-your-own-terminal). |
| `--werror` | A file with warnings counts as failed (`status: "failed"`, exit `1`). |
| `--watch` | Compiles, then compiles everything again whenever a `.mq4`, `.mq5` or `.mqh` under the given paths or `-I` folders changes. Runs until Ctrl-C. |
| `--text` | `OK`/`FAIL` lines plus MetaEditor's own message lines, instead of JSON. |
| `--format FORMAT` | `json` (the default), `text`, or `gnu`: `path:line:column: error: text [code]` lines that VS Code, vim and emacs jump to. |
| `--setup` | Installs the toolchain and stops. Handy before a timed job. |
| `--update` | Reinstalls MT4 and MT5 from the newest installers. The old toolchain stays put until the new one works. |
| `--version` | The image version and the exact MetaEditor builds in your cache. |
| `-h`, `--help` | The built-in help. |

### What happens when you run it

1. **Paths get checked and mounted.** Every argument is a file or a folder, relative or absolute, anywhere on the box. No arguments means the current folder, so don't run it bare from your home folder unless you want all of it scanned (from `/` it refuses outright). A path that doesn't exist kills the run with exit `2` before anything compiles. The command mounts what's needed (see [the mounts](#how-the-sausage-gets-made)) and starts **one** container for the whole run.
2. **The file list gets built.** A file is taken as is; a symlink is followed, and its output lands next to the real file. A folder is searched recursively for `.mq4` and `.mq5` (any case), sorted by path; symlinked files inside it are skipped. Arguments are handled in the order you gave them, and a file that shows up twice (named directly and through its folder) stays in its first spot only. Naming a `.mqh` or any other non-source file directly is exit `2`; inside a folder those are just skipped. A folder with no sources at all is exit `2` too.
3. **The toolchain gets checked.** On the very first run this is where MT4 and MT5 get installed (about a minute and a half), and only the ones your sources need: a run of nothing but `.mq5` files installs just MT5, and a platform you handed your own terminal for never gets downloaded at all. After that it's a quick look at the cache.
4. **Files compile one at a time, never in parallel,** in the order from step 2, MT4 and MT5 files mixed. **The extension alone picks the compiler:** `.mq4` goes to MT4's `metaeditor.exe`, `.mq5` to MT5's `MetaEditor64.exe`. The folder a file sits in doesn't change that. It only decides which `Include` the file sees: a `.mq4` looks for the nearest folder called `MQL4` above it, a `.mq5` for the nearest `MQL5` (any case, `mql5` works too). So a `.mq4` dumped inside `MQL5/Experts` still compiles with MT4, but it won't see `MQL5/Include`.
5. **Results land next to the sources.** `Foo.mq5` gives `Foo.ex5` in the same folder, `Bar.mq4` gives `Bar.ex4`, owned by you, not root. The old `.ex4`/`.ex5` gets deleted right before each file compiles, so whatever sits there after the run came out of this run: no stale build that looks fresh, even when MetaEditor crashes. A failure doesn't stop the run; every file gets its turn.
6. **You get the report.** On stdout, one JSON record per file as each one finishes, then a summary (see [what comes out](#what-comes-out)). Paths read relative to your current folder when they're inside it, absolute when they aren't. Errors point at the real file: your header for your header, and for a standard one the header's path in the toolchain (`/cache/uid-<UID>/wine/drive_c/...`, inside the cache volume). Progress and logs go to stderr as JSON lines too, so `mql-compiler 2>/dev/null` shows nothing but the results. A copy of the whole run, `--setup` and failed runs included, goes to `uid-<your UID>/logs/last-run.log` in the cache volume, replaced every run: `docker run --rm -v mql-compiler-cache:/c busybox cat /c/uid-$(id -u)/logs/last-run.log` reads it.
7. **The exit status sums it up:** `0` every file compiled, `1` at least one failed (compile errors, warnings under `--werror`, or MetaEditor choked and wrote no result), `2` bad path, bad option, nothing to compile, or the toolchain couldn't be installed. If Docker itself fails (daemon down, image can't be pulled), you get Docker's own code, usually `125`. A `--watch` run stopped with Ctrl-C exits `130`.

### What comes out

stdout is [JSON Lines](https://jsonlines.org): one object per line, each with a `type`.

- **`file`**, one per source:
  - `source`: the path as given back to you;
  - `platform`: `mt4` or `mt5`;
  - `status`: `ok` or `failed`;
  - `output`: the `.ex4`/`.ex5` path, or `null` when nothing was built;
  - `errors`, `warnings`: MetaEditor's counts, `null` when it wrote no result;
  - `messages`: every error and warning as `{severity, file, line, column, code, text}`;
  - `log`: MetaEditor's raw lines, only when it wrote no result.
- **`summary`**, last: `total`, `compiled`, `failed`, `werror`. `--watch` prints one after every pass.
- **`error`**, instead of everything else when the run can't start (bad path, bad option, broken setup): `message`.
- **`version`**, from `--version`, `--setup` and `--update`: `version`, `mt4_metaeditor`, `mt5_metaeditor`.

`jq` makes short work of it: `mql-compiler 2>/dev/null | jq -r 'select(.status == "failed") | .source'` lists what broke.

### Watching, warnings and shared libraries

`--watch` holds the container open, compiles, then sits on inotify and runs another full pass whenever a source or header changes under the paths you gave it or an `-I` folder. Between passes it lets go of the cache lock, so a one-off `mql-compiler` in another terminal still gets a turn. Ctrl-C stops it cleanly.

`--werror` turns a file with warnings into a failure, with its status and the exit code to match. The `.ex4`/`.ex5` still gets built; the flag only changes the verdict.

`-I` is for code that doesn't live in your `MQL4`/`MQL5` tree: a shared library repo, a vendored framework. Point it at the folder that would sit inside `Include`, so `-I ~/libs/mql5` with `~/libs/mql5/MyLib/Money.mqh` makes `#include <MyLib/Money.mqh>` work. The layering is standard library first, then each `-I` in order, then your own `Include` on top.

### Keeping MetaEditor current

The cache keeps whatever MetaEditor build got installed first, forever. `mql-compiler --version` shows which builds you're on, and `mql-compiler --update` reinstalls both from the newest installers (about a minute and a half). If the reinstall fails, the old toolchain comes back as it was.

### Bring your own terminal

Already got a portable MT4 or MT5 terminal sitting on disk, the folder with `terminal64.exe`, `MetaEditor64.exe` and `MQL5` side by side? Point the compiler at it and it uses that terminal's MetaEditor and that terminal's standard library instead of the cached ones:

```bash
mql-compiler --mt5-terminal "/trading/MT5 - SomeBroker" MQL5
mql-compiler --mt4-terminal ~/mt4 --mt5-terminal ~/mt5 .   # both platforms
```

Handy when you need the exact MetaEditor build your broker's terminal runs, or when you'd rather not download anything: a platform with its own terminal is never downloaded or installed, so a first run with `--mt5-terminal` on `.mq5` files only sets up a bare Wine prefix. Your terminal gets mounted **read-only** and nothing gets written into it, except the `.ex4`/`.ex5` next to a source you compile from inside it (its own `MQL5` folder stays writable). The cached toolchain isn't touched either: leave the option off next time and you're back on the cached build.

The terminal needs to have been started at least once, so it has unpacked its standard library (`MQL5/Include/Trade/Trade.mqh`, `MQL4/Include/stdlib.mqh`). A folder without MetaEditor or without those headers is exit `2` before anything compiles. `--version` with the option shows that terminal's build.

Two runs at once take turns: they share one Wine install and one log file, so the second one logs that it's waiting and starts when the first is done. Handing everything to one run is faster.

Paths with spaces work. MetaEditor itself chokes on them, so such a file gets compiled through a space-free link to its `MQL4`/`MQL5` folder (or its own folder, when it's loose), and the messages show your real paths again.

### How your tree should look

Same as a terminal's data folder. Keep sources under a folder called `MQL4` or `MQL5`, with your headers in its `Include`:

```text
anywhere/
├── MQL4/
│   ├── Experts/  Indicators/  Scripts/  Libraries/
│   └── Include/          # your MT4 headers
└── MQL5/
    ├── Experts/  Indicators/  Scripts/  Libraries/
    ├── Files/  Images/   # stuff your #resource lines pull in
    └── Include/          # your MT5 headers
```

`MQL4` and `MQL5` don't have to be siblings and don't have to sit anywhere special. A file outside any `MQL4`/`MQL5` folder still compiles; it just gets the standard library, no `Include` of yours, and no `\\`-rooted `#resource` paths.

The container only sees the mounted folder (the `MQL4`/`MQL5` one, or a loose file's own folder), read-write. An `#include "../../elsewhere/x.mqh"` or a symlink that points out of it is a missing file in there.

### How includes get resolved

MetaEditor reads `#include <...>` from exactly one `Include` folder. Your sources need two: the MetaQuotes standard library and your own headers. So the tool builds a throwaway folder that has both, once per platform and `MQL4`/`MQL5` folder in a run:

1. Links to the matching terminal's standard `Include` (`Trade/`, `Arrays/`, `stdlib.mqh`, the whole lot): MT4's for a `.mq4`, MT5's for a `.mq5`.
2. Links to every `-I` folder's files, laid on top in the order you gave them.
3. Links to the files in the `Include` of the nearest `MQL4` (for `.mq4`) or `MQL5` (for `.mq5`) folder above your source, laid on top of all that. Same path in two layers? **The later one wins, and yours is last.** Edited `Trade/Trade.mqh` in your tree? Your version gets compiled.
4. Links to the rest of that `MQL4`/`MQL5` folder (`Files`, `Images`, `Indicators`, ...), so `#resource "\\Files\\data.txt"` and friends resolve.

MetaEditor gets that folder as its include root. Nothing gets written into your folders or the terminal's, and the folder is gone when the run ends. `#include "..."` resolves next to the source, as always.

## How the sausage gets made

- **The image** is Debian trixie with Wine 10 (the 64-bit half plus the 32-bit half that MT4's ancient MetaEditor needs), Xvfb as a fake display nobody ever looks at, and one bash script. Not a single MetaQuotes byte in it.
- **The toolchain:** on the first run the script downloads the MT4 and MT5 installers, checks each one's Authenticode signature (valid digest, a certificate chain the image's CA bundle trusts, and a signing certificate whose common name starts with `MetaQuotes`; anything else gets refused), and installs both silently under Wine. If the certificate authority's revocation server is down, it retries three times, then checks everything but revocation and logs a warning with `reason=crl_unreachable`. The installers default to RoboForex's; point `MQL_COMPILER_MT4_URL` and `MQL_COMPILER_MT5_URL` at any broker's or MetaQuotes' own. The compiler inside is the same either way.
- **The standard library:** the installers don't actually put it on disk. A terminal unpacks its `MQL4`/`MQL5` folder, standard headers included, the first time it starts. So setup starts each terminal once, headless, waits for `Trade/Trade.mqh` (MT5) and `stdlib.mqh` (MT4) to show up, and kills it. A few seconds each, once.
- **The cache:** Wine itself is in the image; the Wine prefix with MT4 and MT5 in it is about 2 GB. Once a terminal is installed and has unpacked its standard library, it gets moved out of `Program Files` into a plain portable folder (`drive_c/terminals/mt4`, `drive_c/terminals/mt5`), so the cached terminals are the exact same kind of thing as one you [bring yourself](#bring-your-own-terminal). A cache from an older version gets that move on its next run, no re-download. The prefix lives in the Docker volume `mql-compiler-cache`, one folder per user ID, so everybody on a box shares a single volume. `docker volume rm mql-compiler-cache` nukes it and the next run installs again. The container runs as your UID, so the compiled files are yours.
- **The mounts:** the command turns every path into an absolute one and mounts the folder whose `Include` it needs at the **same path** inside the container: the nearest `MQL4` above a `.mq4`, the nearest `MQL5` above a `.mq5`, the nearest of either above a folder, or the folder itself or the file's folder when there's no such parent. Nested ones collapse into one mount. A `--mt4-terminal`/`--mt5-terminal` folder is mounted read-only on top. It won't mount `/`, so a bare `mql-compiler` from `/` is refused. The container starts in your current folder, so the paths in the output are your real paths. On SELinux hosts, the mounts carry no `:z` label, so expect permission errors there.
- **Compiling:** every file goes through MetaEditor's command-line compiler with `/inc` pointed at the merged folder from [how includes get resolved](#how-includes-get-resolved). MetaEditor's exit code is a lying piece of shit (it usually returns 1 when everything went fine), so the script ignores it, reads the `Result:` line of the compile log instead, and turns the Windows paths in there back into yours.

## Environment variables

The `mql-compiler` command reads these:

| Variable | Default | What it does |
|---|---|---|
| `MQL_COMPILER_IMAGE` | the pinned release | Runs some other image |
| `MQL_COMPILER_VOLUME` | `mql-compiler-cache` | Docker volume that holds the toolchain |
| `MQL_COMPILER_MT4_URL` | RoboForex's MT4 installer | MT4 installer for the first run |
| `MQL_COMPILER_MT5_URL` | RoboForex's MT5 installer | MT5 installer for the first run |

The installer URLs only matter while the toolchain is being installed. To use another broker's installers, point `MQL_COMPILER_VOLUME` at a new volume name for that first run and keep using it. `docker volume rm mql-compiler-cache` works too, but it throws away every user's toolchain on the box.

## GitHub Action

Compile on every push, fail the job on errors, and get each error marked on its source line in the PR:

```yaml
- uses: actions/checkout@v6
- uses: psyb0t/docker-mql-compiler@v0.3.0
  with:
    paths: |
      MQL5/Experts
      MQL4/Indicators/Bands.mq4
```

| Input | Default | What it does |
|---|---|---|
| `paths` | `.` | Files or folders to compile, one per line |
| `include` | none | Extra `-I` folders, one per line |
| `werror` | `false` | Fail on warnings |
| `image` | the release matching the action's ref | Image to run; a branch ref like `@master` runs `:latest` |
| `cache` | `true` | Keep the 2 GB toolchain in the Actions cache, so only the first run pays the 90-second install |
| `cache-dir` | under `RUNNER_TEMP` | Where the toolchain lives on the runner |

Outputs: `results` (the path of the JSON Lines file), `total`, `compiled`, `failed`. The job summary gets a table of every file. Paths in annotations are relative to the repository root, so run it from there (the default).

## Running the image by hand

The command is just a thin `docker run`. Doing it yourself:

```bash
# run from the folder that holds MQL5/
docker run --rm --init \
  --user "$(id -u):$(id -g)" \
  -v "$PWD":/src \
  -v mql-compiler-cache:/cache \
  psyb0t/mql-compiler:v0.3.0 MQL5/Experts
```

Mount your sources at `/src` (the image's working folder, so relative paths start there) and keep `/cache` on a volume. Skip the volume and every single run reinstalls the whole toolchain, which gets old fast. The image only sees what you mount, so mount the `MQL4`/`MQL5` folder or its parent, never just `Experts`, or your `Include` stays outside. Add `-e MQL_COMPILER_MT4_URL=...` and `-e MQL_COMPILER_MT5_URL=...` for other installers. An `-I` folder has to be mounted too. `--init` lets Ctrl-C reach the compiler, which `--watch` needs. The command does the same thing with each folder mounted at its own host path and `-w "$PWD"`, which is why its output shows your real paths.

## Agent integrations

[`.agents/skills/mql-compiler`](.agents/skills/mql-compiler/SKILL.md) teaches a coding agent (Claude Code, Codex, OpenClaw, [peen](https://github.com/psyb0t/peen)) to install the command, compile, and read the JSON results without making shit up. Every release publishes it to [ClawHub](https://clawhub.ai).

## Development

```bash
make build      # build psyb0t/mql-compiler:dev, :v<VERSION> and :latest
make test       # compile tests/fixtures with the built image and check the results
make test-all   # make test plus a real release install from Docker Hub (what CI runs)
make lint       # shellcheck and shfmt on the scripts, hadolint on the Dockerfile
make format     # rewrite the scripts with shfmt
make sec        # gitleaks secrets scan, hadolint, grype vulnerability scan of the image
make install    # build :dev and install the command from this checkout
make uninstall  # remove the installed command
make version    # print the version; V=X.Y.Z sets it
make help       # every target
```

Every tool runs from a digest-pinned image, so the host needs Docker and Make and nothing else. `make test` installs the toolchain into `.testing/cache` the first time and reuses it after. `make test` also runs a real `--update`, so it reinstalls the toolchain once per run, and covers the installer, the GitHub Action's script and the failure paths. CI runs `make lint` and `make test-all`, runs the GitHub Action against the freshly built image, builds and pushes the image with a Grype scan on every push, and ships the skill to ClawHub on release tags.

## Recommended brokers

- [RoboForex](https://my.roboforex.com/en/?a=zswg)
- [TeleTrade](https://my.teletrade-dj.com/agent_pp.html?agent_pp=26834897)

## License

[WTFPL](LICENSE). Do what the fuck you want.

MetaTrader, MetaEditor and their installers are MetaQuotes software and none of it lives in this repo or the image. The first run downloads it from the broker, and MetaQuotes' license covers it. See [THIRD_PARTY.md](THIRD_PARTY.md).
