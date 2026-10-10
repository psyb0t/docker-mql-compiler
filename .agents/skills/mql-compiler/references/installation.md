# Installing mql-compiler

`mql-compiler` is one file on `PATH` that runs the `psyb0t/mql-compiler` Docker image. The only prerequisite is a running Docker daemon the user can talk to (`docker info` works without sudo).

## Install

Per user, into `~/.local/bin`:

```bash
curl -fsSL https://raw.githubusercontent.com/psyb0t/docker-mql-compiler/master/install.sh | bash
```

System wide, into `/usr/local/bin`:

```bash
curl -fsSL https://raw.githubusercontent.com/psyb0t/docker-mql-compiler/master/install.sh | sudo bash -s -- --system
```

| Option | Effect |
|---|---|
| `--user` | Install to `~/.local/bin` (the default when not root) |
| `--system` | Install to `/usr/local/bin` (the default as root; needs root) |
| `--rolling` | Pin `psyb0t/mql-compiler:latest` instead of the newest release tag |
| `--uninstall` | Remove the command; the toolchain volume stays |

The installer pins the newest GitHub release (for example `psyb0t/mql-compiler:v0.1.1`), pulls it, and writes the pin into the command file. There is no config folder. It refuses to overwrite a file at the target path that it did not install. A per-user install warns when `~/.local/bin` is not on `PATH` and prints the line to add to `~/.bashrc` or `~/.zshrc`.

## Upgrade

Run the same install command again. It pins the newest release and removes the image it replaced.

## First run

The first compile downloads the MT4 and MT5 installers, checks their MetaQuotes signatures, and installs both into the `mql-compiler-cache` Docker volume. It takes about a minute and a half and about 2 GB of disk. `mql-compiler --setup` does only this, which is handy before a timed job. Later runs reuse the volume and take seconds.

To use another broker's installers, set `MQL_COMPILER_MT4_URL` and `MQL_COMPILER_MT5_URL` before the first run. For an existing cache, remove the volume first.

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/psyb0t/docker-mql-compiler/master/install.sh | bash -s -- --uninstall
docker volume rm mql-compiler-cache   # also frees the toolchain
```

Use `sudo ... --system --uninstall` for a system-wide install.

## Checks

```bash
command -v mql-compiler        # installed and on PATH
mql-compiler --help            # the image runs
docker volume ls | grep mql-compiler-cache   # toolchain cached (after the first run)
```

## Troubleshooting

- **`cannot talk to Docker`**: the daemon is down, or the user is not in the `docker` group.
- **`MT5 setup failed` / `MT4 setup failed`**: the installer download or its signature check failed; stderr has the reason. Retry; a custom installer URL must point at a MetaQuotes-signed setup file.
- **`no such file or folder`**: the path is outside the current directory, which is the only folder the container sees.
