---
title: "Home"
description: "mql-compiler compiles MQL4 and MQL5 on Linux with MetaQuotes' MetaEditor under Wine in Docker, and reports every compile error as JSON."
nav_order: 1
permalink: /
seo:
  type: WebSite
---

# mql-compiler

Compile MQL4 and MQL5 on Linux without booting a goddamn Windows box. One command starts MetaQuotes' own MetaEditor inside a Wine container, compiles your `.mq4` and `.mq5` files, writes `.ex4` and `.ex5` right next to them, and hands back every error as JSON Lines your scripts and agents can parse. Humans get `--text`.

No Windows, no MetaTrader terminal running, no broker account. The image carries Wine and one Bash script and not a single MetaQuotes byte: the first run downloads the MT4 and MT5 installers, checks their MetaQuotes signature and caches the toolchain in a Docker volume.

## Quick start

Docker must be running on an x86-64 (amd64) machine. There is no ARM image.

```bash
curl -fsSL https://raw.githubusercontent.com/psyb0t/docker-mql-compiler/master/install.sh \
  | bash

# compile the sources under the current directory
mql-compiler --text .
```

The first compile installs only the MT4 or MT5 toolchain your sources need, in about a minute and a half. Later runs take seconds. Exit `0` means every source compiled, `1` means at least one failed, and `2` means bad arguments or a failed setup.

```json
{"type":"file","source":"MQL5/Experts/Hello.mq5","platform":"mt5","status":"ok","output":"MQL5/Experts/Hello.ex5","errors":0,"warnings":0,"messages":[]}
{"type":"summary","total":1,"compiled":1,"failed":0,"werror":false}
```

## Where to go next

| You want to | Read |
| --- | --- |
| Install, upgrade or uninstall the command, or set its environment variables | [Installation and configuration](installation.md) |
| Look up an option, a result field, an exit code or an include rule | [Using mql-compiler](usage.md) |
| Compile in GitHub Actions, or run the image with plain `docker run` | [GitHub Action and Docker](ci-and-docker.md) |
| Understand Wine, the signature check, the cache and the mounts | [Architecture](architecture.md) |
| Fix an error message or a setup that won't finish | [Troubleshooting](troubleshooting.md) |
| Build, test and lint the project itself | [Development](development.md) |

Agents get the same facts from the [mql-compiler skill](https://github.com/psyb0t/docker-mql-compiler/blob/master/.agents/skills/mql-compiler/SKILL.md), published to [ClawHub](https://clawhub.ai) with every release. The source is on [GitHub](https://github.com/psyb0t/docker-mql-compiler), and the image is [psyb0t/mql-compiler](https://hub.docker.com/r/psyb0t/mql-compiler) on Docker Hub.
