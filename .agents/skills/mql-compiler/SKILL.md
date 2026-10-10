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

It lands in `~/.local/bin`; if that is not on `PATH`, the installer prints the line to add. `--system` (with sudo) installs to `/usr/local/bin` instead.

## Compile

Run it from the folder that holds the sources. That folder is the only one the container sees, so every path must sit inside it.

```bash
mql-compiler                       # everything under the current directory
mql-compiler MQL5/Experts/Foo.mq5  # one file
mql-compiler MQL5/Indicators       # one folder
```

- Each `.ex4`/`.ex5` is written next to its source.
- `#include <...>` resolves against the nearest folder above the source named `MQL4` or `MQL5`. Compile a terminal-style tree (`MQL5/Experts`, `MQL5/Include`, ...) from inside the `MQL5` folder or one level above it, never from a copy that drops `Include`.
- The first run downloads and installs MT4 and MT5 into the `mql-compiler-cache` Docker volume, about a minute and a half. Allow for it in timeouts; later runs take seconds.

## Read the result

Results go to stdout, one line per file, followed by that file's compiler messages:

```text
OK   MQL5/Experts/Foo.mq5 -> MQL5/Experts/Foo.ex5 (0 warnings)
FAIL MQL5/Experts/Bar.mq5 (1 errors, 0 warnings)
     MQL5/Experts/Bar.mq5(41,7) : error 256: undeclared identifier 'lots'
```

Errors read `path(line,column) : error <code>: <message>`, with paths relative to the current directory. Fix the source at that line and compile again. Progress and diagnostics go to stderr as JSON lines; `2>/dev/null` hides them.

| Exit | Meaning |
|---|---|
| `0` | Every file compiled |
| `1` | At least one file has compile errors (see the `FAIL` lines) |
| `2` | Bad path or option, or the toolchain could not be installed (see stderr) |

## Rules for agents

- Use the `mql-compiler` command. Do not build your own `docker run` unless the user asks.
- Report compile errors with their file, line and message. Do not claim a build succeeded unless the exit status was `0` and the file's line says `OK`.
- `MQL_COMPILER_MT4_URL` and `MQL_COMPILER_MT5_URL` choose other installers, which only matters on a first run or after `docker volume rm mql-compiler-cache`. Remove the volume only when the user asks: it costs another full download.
