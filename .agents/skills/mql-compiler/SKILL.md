---
name: mql-compiler
description: "Compile MQL4 (.mq4) and MQL5 (.mq5) sources to .ex4/.ex5 on Linux with the mql-compiler command, and read its compile errors."
homepage: https://github.com/psyb0t/docker-mql-compiler
user-invocable: true
metadata:
  { "openclaw": { "emoji": "🛠️", "requires": { "bins": ["docker"] } } }
---

# mql-compiler

`mql-compiler` compiles MetaTrader sources with MetaQuotes' own MetaEditor, running under Wine in the `psyb0t/mql-compiler` Docker image. It needs Docker and nothing else: no Windows, no MetaTrader terminal, no trading account.

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

- Arguments are files or folders, relative or absolute, anywhere on the machine. No argument means the current folder. No `cd` is needed.
- Files compile one after another in path order: `.mq4` with MT4's MetaEditor, `.mq5` with MT5's. Experts, indicators, scripts and libraries all compile the same way. A file named twice compiles once.
- Each `.ex4`/`.ex5` is written next to its source, owned by the caller.
- The first run downloads and installs MT4 and MT5 into the `mql-compiler-cache` Docker volume and unpacks their standard libraries, about a minute and a half. Allow for it in timeouts; later runs take seconds. `mql-compiler --setup` does only this.

## How includes resolve

- `#include <...>` searches one merged folder built for the run: the MetaQuotes standard library (`<Trade/Trade.mqh>`, `<Arrays/ArrayObj.mqh>`, `<stdlib.mqh>`, ...) with the `Include` folder of the nearest enclosing `MQL4`/`MQL5` folder laid over it. When both have the same path, the user's file wins.
- `#resource "\\Files\\x.txt"` and other `\\`-rooted paths start at that same `MQL4`/`MQL5` folder.
- `#include "..."` resolves next to the source.
- A source outside any `MQL4`/`MQL5` folder gets the standard library only.
- Nothing is written into the user's folders or the toolchain; the merged folder is temporary.

So keep a terminal-style tree: sources under `MQL5/Experts`, `MQL5/Indicators`, ..., headers under `MQL5/Include` (same for `MQL4`). When copying a source elsewhere to compile it, copy its `MQL4`/`MQL5` folder with it, or its custom includes go missing.

## Read the result

Results go to stdout, one line per file, followed by that file's compiler messages:

```text
OK   MQL5/Experts/Foo.mq5 -> MQL5/Experts/Foo.ex5 (0 warnings)
FAIL MQL5/Experts/Bar.mq5 (1 errors, 0 warnings)
     MQL5/Experts/Bar.mq5(41,7) : error 256: undeclared identifier 'lots'
```

Errors read `path(line,column) : error <code>: <message>`. Paths are relative to the current folder when inside it, absolute otherwise. Fix the source at that line and compile again. Progress and diagnostics go to stderr as JSON lines; `2>/dev/null` hides them.

| Exit | Meaning |
|---|---|
| `0` | Every file compiled |
| `1` | At least one file has compile errors (see the `FAIL` lines) |
| `2` | Bad path or option, or the toolchain could not be installed (see stderr) |

## Rules for agents

- Use the `mql-compiler` command. Do not build your own `docker run` unless the user asks.
- Report compile errors with their file, line and message. Do not claim a build succeeded unless the exit status was `0` and the file's line says `OK`.
- `file '...' not found` on an `#include <...>` means the header is in neither the user's `Include` nor the standard library. Check the source sits under the right `MQL4`/`MQL5` folder before editing code.
- `MQL_COMPILER_MT4_URL` and `MQL_COMPILER_MT5_URL` choose other installers, which only matters on a first run or after `docker volume rm mql-compiler-cache`. Remove the volume only when the user asks: it costs another full download.
