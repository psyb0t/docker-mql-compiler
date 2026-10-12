# Installation and configuration

All you need is Docker, installed and running, on an x86-64 (amd64) box. MT4's MetaEditor is 32-bit Windows code and needs Wine's i386 half, so there's no ARM image: Apple Silicon and other ARM machines are out unless Docker emulates amd64 for you.

```bash
# per user: drops the command into ~/.local/bin
curl -fsSL https://raw.githubusercontent.com/psyb0t/docker-mql-compiler/master/install.sh | bash

# system wide: /usr/local/bin, for the whole box
curl -fsSL https://raw.githubusercontent.com/psyb0t/docker-mql-compiler/master/install.sh | sudo bash -s -- --system
```

The installer pins the newest release image and writes the `mql-compiler` command. That single file is the entire install. Run the installer again to upgrade; it throws away the image it replaced. `--rolling` pins `:latest` instead of a release, and `--uninstall` gets rid of the command and its image. The cache volume stays, since every user on the box shares it; `docker volume rm mql-compiler-cache` takes it out.

Then go to a folder full of MQL sources and run `mql-compiler`. The first run spends about a minute and a half downloading and installing the platforms its sources need into a Docker volume. Every run after that takes seconds.

## Environment variables

The `mql-compiler` command reads these:

| Variable | Default | What it does |
|---|---|---|
| `MQL_COMPILER_IMAGE` | the pinned release | Runs some other image |
| `MQL_COMPILER_VOLUME` | `mql-compiler-cache` | Docker volume that holds the toolchain |
| `MQL_COMPILER_MT4_URL` | RoboForex's MT4 installer | MT4 installer for the first run |
| `MQL_COMPILER_MT5_URL` | RoboForex's MT5 installer | MT5 installer for the first run |

The installer URLs only matter while the toolchain is being installed. To use another broker's installers, point `MQL_COMPILER_VOLUME` at a new volume name for that first run and keep using it. `docker volume rm mql-compiler-cache` works too, but it throws away every user's toolchain on the box.

[Back to the README](../README.md).
