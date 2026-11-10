---
title: "Installation and configuration"
description: "Install, upgrade and uninstall the mql-compiler command, pick per-user or system-wide installs, and set its MQL_COMPILER_* environment variables."
nav_order: 2
---

# Installation and configuration

All you need is Docker, installed and running, on an x86-64 (amd64) box. MT4's MetaEditor is 32-bit Windows code and needs Wine's i386 half, so there's no ARM image: Apple Silicon and other ARM machines are out unless Docker emulates amd64 for you.

```bash
# per user: drops the command into ~/.local/bin
curl -fsSL https://raw.githubusercontent.com/psyb0t/docker-mql-compiler/master/install.sh | bash

# system wide: /usr/local/bin, for the whole box
curl -fsSL https://raw.githubusercontent.com/psyb0t/docker-mql-compiler/master/install.sh \
  | sudo bash -s -- --system
```

[`install.sh`](https://github.com/psyb0t/docker-mql-compiler/blob/master/install.sh) pins the newest release image and writes the `mql-compiler` command, plus the seccomp profile the command hands to `docker run` (`~/.local/share/mql-compiler/seccomp.json`, or `/usr/local/share/mql-compiler/seccomp.json` system wide): Docker's default profile plus the `userfaultfd` call Wine needs to start under Linux 7.0. Those two files are the entire install. There is no config directory. A per-user install warns when `~/.local/bin` isn't on your `PATH` and prints the line to add to your shell's rc file. The installer refuses to overwrite a file at the target path that it didn't write itself.

| Option | What it does |
|---|---|
| `--user` | Installs to `~/.local/bin`, the default when not root |
| `--system` | Installs to `/usr/local/bin`, the default as root (needs root) |
| `--rolling` | Pins `psyb0t/mql-compiler:latest` instead of the newest release tag |
| `--uninstall` | Removes the command, its seccomp profile and the image it was pinned to |

Then go to a directory full of MQL sources and run `mql-compiler`. The first run spends about a minute and a half downloading and installing the platforms its sources need into a Docker volume. Every run after that takes seconds. `mql-compiler --setup` does only the install, which is handy before a timed job.

## Upgrade

Run the installer again. It pins the newest release and throws away the image it replaced.

The MT4 and MT5 toolchain in the cache doesn't change with the image: it stays on whatever MetaEditor builds the first run installed. `mql-compiler --version` shows them and `mql-compiler --update` reinstalls both from the newest installers. See [keeping MetaEditor current](usage.md#keeping-metaeditor-current).

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/psyb0t/docker-mql-compiler/master/install.sh \
  | bash -s -- --uninstall

# also frees the toolchain, for every user on the box
docker volume rm mql-compiler-cache
```

The uninstaller keeps the image, with a warning, while a container still uses it. For a system-wide install, run it with `sudo` and `--system --uninstall`. The cache volume stays unless you remove it, since every user on the box shares it.

## Environment variables

The `mql-compiler` command reads these:

| Variable | Default | What it does |
|---|---|---|
| `MQL_COMPILER_IMAGE` | the pinned release | Runs some other image |
| `MQL_COMPILER_VOLUME` | `mql-compiler-cache` | Docker volume that holds the toolchain |
| `MQL_COMPILER_MT4_URL` | RoboForex's MT4 installer | MT4 installer for the first run |
| `MQL_COMPILER_MT5_URL` | RoboForex's MT5 installer | MT5 installer for the first run |
| `MQL_COMPILER_INSTALL_TIMEOUT` | `600` | Seconds one platform's installer may run before setup gives up |
| `MQL_COMPILER_SECCOMP` | the installed `seccomp.json` | Seccomp profile passed to `docker run`; a path that doesn't exist is exit `2` |

The installer URLs and the install timeout only matter while the toolchain is being installed. A normal install takes about a minute per platform; raise the timeout on a slow connection. Any installer still has to pass the MetaQuotes signature check described in [the architecture page](architecture.md#how-the-sausage-gets-made).

To use another broker's installers, point `MQL_COMPILER_VOLUME` at a new volume name for that first run and keep using it. `docker volume rm mql-compiler-cache` works too, but it throws away every user's toolchain on the box.

## Check the install

```bash
# installed and on PATH
command -v mql-compiler

# the image runs; the MetaEditor builds are null before the first run
mql-compiler --version

# the toolchain is cached (after the first run)
docker volume ls | grep mql-compiler-cache
```

When something goes wrong, [troubleshooting](troubleshooting.md) lists every error message with its cause and fix.
