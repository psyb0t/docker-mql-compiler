# docker-mql-compiler

[![CI](https://github.com/psyb0t/docker-mql-compiler/actions/workflows/pipeline.yml/badge.svg?branch=master)](https://github.com/psyb0t/docker-mql-compiler/actions/workflows/pipeline.yml)
[![version](https://raw.githubusercontent.com/psyb0t/docker-mql-compiler/badges/version.svg)](https://github.com/psyb0t/docker-mql-compiler/releases)
[![license](https://raw.githubusercontent.com/psyb0t/docker-mql-compiler/badges/license.svg)](LICENSE)
[![Docker Pulls](https://img.shields.io/docker/pulls/psyb0t/mql-compiler?style=flat-square)](https://hub.docker.com/r/psyb0t/mql-compiler)

Compile MQL4 and MQL5 on Linux without booting a goddamn Windows box. One command, and MetaQuotes' own MetaEditor wakes up inside a Wine container, chews through your `.mq4` and `.mq5` files, shits out `.ex4` and `.ex5` right next to them, and hands back every error as JSON your agent can actually use. Humans get `--text`.

No Windows. No MetaTrader window to babysit. No broker account. No clicking "Compile" in a GUI that looks like it escaped from 2009.
## Quick start

Docker must be running on an x86-64 (amd64) machine. There is no ARM image.

```bash
curl -fsSL https://raw.githubusercontent.com/psyb0t/docker-mql-compiler/master/install.sh | bash

# Compile the sources under your current folder.
mql-compiler --text .
```

The command lands in `~/.local/bin`. Add that folder to your `PATH` if the installer tells you to. The first compile downloads only the MT4 or MT5 toolchain your sources need, verifies its signature and caches it. Allow about a minute and a half for setup; later runs take seconds.

A successful compile puts `Foo.ex4` or `Foo.ex5` beside `Foo.mq4` or `Foo.mq5`, owned by you. Fix any reported errors and run the command again. Exit `0` means every source compiled, `1` means at least one failed, and `2` means bad arguments or failed setup.

> [!WARNING]
> This compiles your EA. It does not make your EA any good. If the thing compiles clean and then martingales your account into the ground, that one's on you.

## Using the damn thing

```bash
mql-compiler MQL5/Experts/Scalper.mq5   # one source, JSON Lines by default
mql-compiler --text MQL5 MQL4           # folders, both platforms
mql-compiler --watch MQL5/Experts       # recompile on save until Ctrl-C
mql-compiler --werror MQL5              # warnings fail the run
mql-compiler -I ~/libs/mql5 MQL5        # shared headers outside your tree
mql-compiler --mt5-terminal ~/mt5 MQL5  # use a portable terminal already on disk
mql-compiler --version                 # image version and MetaEditor builds
mql-compiler --update                  # reinstall the cached toolchain
```

Keep sources under `MQL4` or `MQL5`, with your headers in that folder's `Include`. Standard headers work too. Your own headers win when they replace a standard one. Files, folders, mixed platforms and paths with spaces all work.

Without `--text`, stdout is JSON Lines: a `file` record for each source and a final `summary`. Progress goes to stderr. Scripts and agents should parse the JSON, not scrape the pretty output.

```json
{"type":"file","source":"MQL5/Experts/Hello.mq5","platform":"mt5","status":"ok","output":"MQL5/Experts/Hello.ex5","errors":0,"warnings":0,"messages":[]}
{"type":"summary","total":1,"compiled":1,"failed":0,"werror":false}
```

## Where the fuck are the details?

| You need | Read this |
| --- | --- |
| Install, upgrade, uninstall, choose installers or change the cache | [Installation and configuration](https://github.com/psyb0t/docker-mql-compiler/blob/master/docs/installation.md) |
| Every option, result field, exit code, include rule and portable-terminal requirement | [Using mql-compiler](https://github.com/psyb0t/docker-mql-compiler/blob/master/docs/usage.md) |
| Wine, signature checks, cache layout, mounts and how MetaEditor runs | [Architecture](https://github.com/psyb0t/docker-mql-compiler/blob/master/docs/architecture.md) |
| GitHub Action inputs, outputs and running Docker by hand | [CI and Docker](https://github.com/psyb0t/docker-mql-compiler/blob/master/docs/ci-and-docker.md) |
| Build, test, lint and contributor commands | [Development](https://github.com/psyb0t/docker-mql-compiler/blob/master/docs/development.md) |

The docs links are absolute so they work on Docker Hub too.

## GitHub Action

```yaml
- uses: actions/checkout@v6
- uses: psyb0t/docker-mql-compiler@v0.5.0
  with:
    paths: MQL5/Experts
```

Compilation errors fail the job and become annotations on the source lines. The [CI guide](https://github.com/psyb0t/docker-mql-compiler/blob/master/docs/ci-and-docker.md#github-action) covers includes, warnings, caching and result outputs.

## Agent integrations

[The mql-compiler skill](https://github.com/psyb0t/docker-mql-compiler/blob/master/.agents/skills/mql-compiler/SKILL.md) teaches Claude Code, Codex, OpenClaw and [peen](https://github.com/psyb0t/peen) to install the command, compile and read the JSON results without making shit up. Every release publishes it to [ClawHub](https://clawhub.ai).

## Recommended brokers and prop firms

- [RoboForex](https://my.roboforex.com/en/?a=zswg)
- [TeleTrade](https://my.teletrade-dj.com/agent_pp.html?agent_pp=26834897)
- [FTMO](https://join.ftmo.com/uYaZPRmKowRZIKtuXdkE): prop firm with MT4 and MT5 support. Trading accounts use simulated capital.

## License

[WTFPL](LICENSE). Do what the fuck you want.

MetaTrader, MetaEditor and their installers are MetaQuotes software and none of it lives in this repo or the image. The first run downloads it from the broker, and MetaQuotes' license covers it. See [THIRD_PARTY.md](THIRD_PARTY.md).
