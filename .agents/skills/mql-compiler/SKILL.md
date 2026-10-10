---
name: mql-compiler
description: "Compile MQL4 (.mq4) and MQL5 (.mq5) sources to .ex4/.ex5 on Linux with the mql-compiler command, and read its compile errors."
homepage: https://github.com/psyb0t/docker-mql-compiler
user-invocable: true
metadata:
  { "openclaw": { "emoji": "🛠️", "requires": { "bins": ["docker"] } } }
---

# mql-compiler

`mql-compiler` compiles MetaTrader sources with MetaQuotes' own MetaEditor, running under Wine in the `psyb0t/mql-compiler` Docker image. It needs Docker on an x86-64 (amd64) machine and nothing else: no Windows, no MetaTrader terminal, no trading account. There is no ARM image.

## Install

If `mql-compiler` is not on `PATH`, install it for the current user:

```bash
curl -fsSL https://raw.githubusercontent.com/psyb0t/docker-mql-compiler/master/install.sh | bash
```

It lands in `~/.local/bin`; if that is not on `PATH`, the installer prints the line to add. For system-wide installs, upgrades, uninstalling, custom installers and troubleshooting, see [references/installation.md](references/installation.md).

## Compile

```bash
mql-compiler [FILE or FOLDER ...]

mql-compiler                                # every .mq4 and .mq5 under the current folder
mql-compiler /abs/path/MQL5/Experts/Foo.mq5 # one file, from any folder
mql-compiler MQL5/Indicators MQL4           # folders, searched recursively
```

- Arguments are files or folders, relative or absolute, anywhere on the machine. No argument means the current folder. No `cd` is needed. A path that does not exist stops the run with exit `2` before anything compiles.
- A folder is searched recursively for `.mq4` and `.mq5` (any case), sorted by path; symlinked files inside it are skipped. Arguments are handled in the order given; a file named twice compiles once, in its first position. `.mqh` and other files are skipped in folders and rejected (exit `2`) when named directly. A run that finds no sources exits `2`.
- One container runs the whole list, one file at a time, never in parallel. A failing file does not stop the run. Pass everything to one call: two runs at the same time take turns (the second logs that it is waiting), so splitting a job only makes it slower.
- Paths with spaces work; the messages still show the real paths.
- The extension alone picks the compiler: `.mq4` goes to MT4's MetaEditor, `.mq5` to MT5's. The folder only decides the includes: a `.mq4` uses the nearest folder named `MQL4` (any case) above it, a `.mq5` the nearest `MQL5`. Experts, indicators, scripts and libraries all compile the same way.
- Each `.ex4`/`.ex5` is written next to its source with the same base name, owned by the caller. The old one is deleted right before the file compiles, so after a run an `.ex4`/`.ex5` exists only if this run produced it. Still report success from the file's `OK` line.
- The container sees only the mounted folders (each source's `MQL4`/`MQL5` folder, or a loose file's own folder). Includes, resources and symlinks that point outside them are missing files inside the container.
- The first run downloads and installs MT4 and MT5 into the `mql-compiler-cache` Docker volume and unpacks their standard libraries, about a minute and a half. Allow for it in timeouts; later runs take seconds. `mql-compiler --setup` does only this.

## How includes resolve

- `#include <...>` searches one merged folder built for the run: the matching platform's MetaQuotes standard library (`<Trade/Trade.mqh>`, `<Arrays/ArrayObj.mqh>`, `<stdlib.mqh>`, ...) with the `Include` folder of the nearest enclosing `MQL4` (for `.mq4`) or `MQL5` (for `.mq5`) folder laid over it. When both have the same path, the user's file wins.
- `#resource "\\Files\\x.txt"` and other `\\`-rooted paths start at that same `MQL4`/`MQL5` folder.
- `#include "..."` resolves next to the source.
- A source outside any `MQL4`/`MQL5` folder gets the standard library only, and no `\\`-rooted resources.
- An error inside a standard header is reported at the header's path in the toolchain (`/cache/uid-<UID>/wine/drive_c/...`, inside the cache volume, not on the host). It usually means the user's code broke something the header relies on, such as a macro with the same name as a standard class; fix the user's code, never the toolchain.
- Nothing is written into the user's folders or the toolchain; the merged folder is temporary.

So keep a terminal-style tree: sources under `MQL5/Experts`, `MQL5/Indicators`, ..., headers under `MQL5/Include` (same for `MQL4`). When copying a source elsewhere to compile it, copy its `MQL4`/`MQL5` folder with it, or its custom includes go missing.

## Read the result

Results go to stdout, one line per file, followed by that file's compiler messages:

```text
OK   MQL5/Experts/Foo.mq5 -> MQL5/Experts/Foo.ex5 (0 warnings)
FAIL MQL5/Experts/Bar.mq5 (1 errors, 0 warnings)
     MQL5/Experts/Bar.mq5(41,7) : error 256: undeclared identifier 'lots'
```

Errors read `path(line,column) : error <code>: <message>`. Paths are relative to the current folder when inside it, absolute otherwise. Fix the source at that line and compile again. Progress and diagnostics go to stderr as JSON lines; `2>/dev/null` hides them. A copy of the last run (stdout and stderr) is in the cache volume: `docker run --rm -v mql-compiler-cache:/c busybox cat /c/uid-$(id -u)/logs/last-run.log`.

| Exit | Meaning |
|---|---|
| `0` | Every file compiled |
| `1` | At least one file has compile errors, or MetaEditor wrote no result for it (see the `FAIL` lines) |
| `2` | Bad path or option, no sources found, or the toolchain could not be set up (see stderr) |
| `125` and other Docker codes | Docker itself failed: daemon down, image not pullable, a bad mount |

## Rules for agents

- Use the `mql-compiler` command. Do not build your own `docker run` unless the user asks.
- Report compile errors with their file, line and message. A file compiled when its line says `OK`, even if the run exits `1` because of another file. Claim the whole build succeeded only when the exit status is `0`.
- `file '...' not found` on an `#include <...>` means the header is in neither the user's `Include` nor the standard library. Check the source sits under the right `MQL4`/`MQL5` folder before editing code.
- `MQL_COMPILER_MT4_URL` and `MQL_COMPILER_MT5_URL` choose other installers, which only matters on a first run, so pair them with a fresh `MQL_COMPILER_VOLUME`. Remove a volume only when the user asks: it costs another full download, and `mql-compiler-cache` holds every user's toolchain on the machine.
