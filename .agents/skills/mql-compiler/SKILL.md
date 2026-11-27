---
name: mql-compiler
description: "Compile MQL4 (.mq4) and MQL5 (.mq5) sources to .ex4/.ex5 on Linux with the mql-compiler command, which runs MetaQuotes' MetaEditor under Wine, and read its compile errors. Use when the user wants to compile MetaTrader expert advisors, indicators, scripts or libraries without Windows."
homepage: https://github.com/psyb0t/docker-mql-compiler
user-invocable: true
metadata:
  { "openclaw": { "emoji": "🛠️", "requires": { "bins": ["mql-compiler"] } } }
permissions:
  network: "The first compile downloads the MT4 and MT5 installers from MetaQuotes' download hosts and checks their MetaQuotes signature. No source code is sent anywhere."
  shell: "The mql-compiler command."
  filesystem: "Reads the .mq4/.mq5 sources and include directories you name. Writes the .ex4/.ex5 next to each source."
---

# mql-compiler

`mql-compiler` compiles MetaTrader sources with MetaQuotes' own MetaEditor, running under Wine. It needs no Windows, no MetaTrader terminal and no trading account, and runs on x86-64 (amd64) machines only.

## Setup

The `mql-compiler` command must already be installed and Docker must be running. Installation and upgrade instructions are in the docs at https://psyb0t.github.io/docker-mql-compiler/. The command needs no URL or token: it reads the paths you pass it. If it is missing or fails to start, see [troubleshooting](references/troubleshooting.md) and tell the user.

## Safety

- The command runs as the caller's user and group IDs, mounts only the directories you name (and each source's `MQL4`/`MQL5` directory), and writes nothing into your tree except the `.ex4`/`.ex5` next to each source. Terminal directories passed with `--mt4-terminal`/`--mt5-terminal` are mounted read-only.
- The first compile downloads the MT4 and MT5 setup programs and installs them into the command's toolchain cache, after checking that they are signed by MetaQuotes.
- Do not delete the toolchain cache or uninstall the command unless the user asks. The cache is shared by every user on the machine and rebuilding it is a full download.

## Compile

```bash
mql-compiler [OPTIONS] [FILE or DIRECTORY ...]

mql-compiler 2>/dev/null                               # every .mq4 and .mq5 under the current directory
mql-compiler /abs/path/MQL5/Experts/Foo.mq5 2>/dev/null # one file, from any directory
mql-compiler MQL5/Indicators MQL4 2>/dev/null           # directories, searched recursively
mql-compiler -I /path/to/shared/lib MQL5 2>/dev/null    # a shared include directory outside the tree
mql-compiler --werror MQL5 2>/dev/null                  # warnings count as failures
```

Options: `-I DIR` / `--include DIR` (extra include directory, repeatable), `--mt4-terminal DIR` / `--mt5-terminal DIR` (compile with that portable terminal's MetaEditor and standard library, mounted read-only; the terminal must have been started once so its standard library is unpacked), `--werror`, `--watch` (recompile on change until stopped; do not use it in an agent run, it never exits on its own), `--text` and `--format json|text|gnu` (output format; leave the JSON default), `--setup` (prepare the toolchain only), `--update` (refresh MT4/MT5 to the newest builds), `--version` (image version and MetaEditor builds), `-h`/`--help`.

- Arguments are files or directories, relative or absolute, anywhere on the machine. No argument means the current directory. No `cd` is needed. A path that does not exist stops the run with exit `2` before anything compiles.
- A directory is searched recursively for `.mq4` and `.mq5` (any case), sorted by path; symlinked files inside it are skipped. Arguments are handled in the order given; a file named twice compiles once, in its first position. `.mqh` and other files are skipped in directories and rejected (exit `2`) when named directly. A run that finds no sources exits `2`.
- One container runs the whole list, one file at a time, never in parallel. A failing file does not stop the run. Pass everything to one call: two runs at the same time take turns (the second logs that it is waiting), so splitting a job only makes it slower.
- Paths with spaces work; the messages still show the real paths.
- The extension alone picks the compiler: `.mq4` goes to MT4's MetaEditor, `.mq5` to MT5's. The directory only decides the includes: a `.mq4` uses the nearest directory named `MQL4` (any case) above it, a `.mq5` the nearest `MQL5`. Experts, indicators, scripts and libraries all compile the same way.
- Each `.ex4`/`.ex5` is written next to its source with the same base name, owned by the caller. The old one is deleted right before the file compiles, so after a run an `.ex4`/`.ex5` exists only if this run produced it. Still report success from the file's `"status": "ok"`.
- The container sees only the mounted directories (each source's `MQL4`/`MQL5` directory, or a loose file's own directory). Includes, resources and symlinks that point outside them are missing files inside the container.
- The first run downloads and installs MT4 and MT5 and unpacks their standard libraries, about a minute and a half. A compile installs only the platforms its sources need, and never one given with `--mt4-terminal`/`--mt5-terminal`. Allow for it in timeouts; later runs take seconds. `mql-compiler --setup` does only this.

## How includes resolve

- `#include <...>` searches one merged directory built for the run: the matching platform's MetaQuotes standard library (`<Trade/Trade.mqh>`, `<Arrays/ArrayObj.mqh>`, `<stdlib.mqh>`, ...), then each `-I` directory, then the `Include` directory of the nearest enclosing `MQL4` (for `.mq4`) or `MQL5` (for `.mq5`) directory, each laid over the one before. When two have the same path, the later one wins, so the user's own `Include` always wins.
- An `-I` directory stands in for `Include`: with `-I /libs` and `/libs/MyLib/x.mqh`, `#include <MyLib/x.mqh>` works.
- `#resource "\\Files\\x.txt"` and other `\\`-rooted paths start at that same `MQL4`/`MQL5` directory.
- `#include "..."` resolves next to the source.
- A source outside any `MQL4`/`MQL5` directory gets the standard library only, and no `\\`-rooted resources.
- An error inside a standard header is reported at the header's path in the toolchain (`/cache/uid-<UID>/wine/drive_c/...`, inside the toolchain cache, not on the host). It usually means the user's code broke something the header relies on, such as a macro with the same name as a standard class; fix the user's code, never the toolchain.
- Nothing is written into the user's directories or the toolchain; the merged directory is temporary.

So keep a terminal-style tree: sources under `MQL5/Experts`, `MQL5/Indicators`, ..., headers under `MQL5/Include` (same for `MQL4`). When copying a source elsewhere to compile it, copy its `MQL4`/`MQL5` directory with it, or its custom includes go missing.

## Read the result

stdout is JSON Lines, one object per line with a `type`. Parse it; do not scrape text.

```json
{"type":"file","source":"MQL5/Experts/Foo.mq5","platform":"mt5","status":"ok","output":"MQL5/Experts/Foo.ex5","errors":0,"warnings":0,"messages":[]}
{"type":"file","source":"MQL5/Experts/Bar.mq5","platform":"mt5","status":"failed","output":null,"errors":1,"warnings":0,"messages":[{"severity":"error","file":"MQL5/Experts/Bar.mq5","line":41,"column":7,"code":256,"text":"undeclared identifier 'lots'"}]}
{"type":"summary","total":2,"compiled":1,"failed":1,"werror":false}
```

- `file` (one per source): `source`, `platform` (`mt4`/`mt5`), `status` (`ok`/`failed`), `output` (the `.ex4`/`.ex5`, or `null`), `errors` and `warnings` (counts, `null` when MetaEditor wrote no result), `messages` (each `{severity, file, line, column, code, text}`), and `log` (MetaEditor's raw lines) only when it wrote no result.
- `summary` (last): `total`, `compiled`, `failed`, `werror`.
- `error` (instead of the rest, when the run cannot start): `message`. A bad path, a bad option or a failed setup.
- `version` (from `--version`, `--setup`, `--update`): `version`, `mt4_metaeditor`, `mt5_metaeditor`.

Paths are relative to the current directory when inside it, absolute otherwise. Fix the source at each message's `file`, `line` and `column`, and compile again. Progress and diagnostics go to stderr as JSON log lines; `2>/dev/null` hides them.

| Exit | Meaning |
|---|---|
| `0` | Every file compiled |
| `1` | At least one file failed: compile errors, warnings under `--werror`, or MetaEditor wrote no result (see the `failed` records) |
| `2` | Bad path or option, no sources found, or the toolchain could not be set up (see the `error` record) |
| `125` and other Docker codes | Docker itself failed: daemon down, image not available, a bad mount (stdout may be empty) |

## Rules for agents

- Use the `mql-compiler` command. Do not call the Docker image directly unless the user asks.
- Report compile errors with their file, line, column, code and text from the `messages`. A file compiled when its record says `"status": "ok"`, even if the run exits `1` because of another file. Claim the whole build succeeded only when the exit status is `0` and the summary shows `"failed": 0`.
- Mention warnings to the user even when the build passes; they are in `messages` with `"severity": "warning"`.
- `file '...' not found` on an `#include <...>` means the header is in neither the user's `Include` nor the standard library. Check the source sits under the right `MQL4`/`MQL5` directory before editing code.
