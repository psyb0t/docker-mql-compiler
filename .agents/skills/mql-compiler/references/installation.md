# Installing mql-compiler

`mql-compiler` is one file on `PATH` that runs the `psyb0t/mql-compiler` Docker image. The prerequisites are an x86-64 (amd64) machine, since there is no ARM image, and a running Docker daemon the user can talk to (`docker info` works without sudo).

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
| `--uninstall` | Remove the command and the image it was pinned to; the toolchain volume stays |

The installer pins the newest GitHub release (for example `psyb0t/mql-compiler:v0.2.1`), pulls it, and writes the pin into the command file. There is no config folder. It refuses to overwrite a file at the target path that it did not install. A per-user install warns when `~/.local/bin` is not on `PATH` and prints the line to add to `~/.bashrc` or `~/.zshrc`.

## Upgrade

Run the same install command again. It pins the newest release and removes the image it replaced.

## First run

The first compile downloads the MT4 and MT5 installers, checks their signatures (valid digest, a trusted certificate chain, a signing certificate whose common name starts with `MetaQuotes`), and installs both into the `mql-compiler-cache` Docker volume. The installers leave the standard library packed, so setup then starts each terminal once, headless, until it has unpacked its `MQL4`/`MQL5` folder, and stops it. All of it takes about a minute and a half and about 2 GB of disk. `mql-compiler --setup` does only this, which is handy before a timed job. Later runs reuse the volume and take seconds.

To use another broker's installers, set `MQL_COMPILER_MT4_URL` and `MQL_COMPILER_MT5_URL` together with a new `MQL_COMPILER_VOLUME` name, and keep that volume name for later runs. Removing `mql-compiler-cache` instead works too, but it deletes every user's toolchain on the machine.

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/psyb0t/docker-mql-compiler/master/install.sh | bash -s -- --uninstall
docker volume rm mql-compiler-cache   # also frees the toolchain, for every user on the machine
```

The uninstaller removes the command and the image it was pinned to (it warns and keeps the image if a container still uses it). Use `sudo ... --system --uninstall` for a system-wide install.

## Checks

```bash
command -v mql-compiler        # installed and on PATH
mql-compiler --help            # the image runs
docker volume ls | grep mql-compiler-cache   # toolchain cached (after the first run)
docker run --rm -v mql-compiler-cache:/c busybox cat /c/uid-$(id -u)/logs/last-run.log   # the last run's full output
```

## Troubleshooting

- **`docker is not installed`**: Docker's CLI is not on `PATH`.
- **`cannot talk to Docker`** (installer) or an exit status of `125`: the daemon is down, the user is not in the `docker` group, or the image could not be pulled. On an ARM machine the pull fails with "no matching manifest".
- **`MT5 setup failed` / `MT4 setup failed`**: the installer download or its signature check failed, or the install finished without a MetaEditor. stderr has the reason. Retry; a custom installer URL must point at a MetaQuotes-signed setup file.
- **`the terminal did not unpack its standard library`**: the terminal started but never wrote its headers within two minutes. Run `mql-compiler --setup` again; if it keeps failing, remove the volume to reinstall.
- **`... belongs to UID N, not M: the cache was written by another UID`**: that cache folder was created by a different user ID inside the same volume. Run as the original user, or use your own `MQL_COMPILER_VOLUME`.
- **`no such file or folder`**: the path does not exist (relative paths start at the current folder).
- **`refusing to mount / into the container`**: `mql-compiler` ran with no path from `/`, or a loose file sits directly in `/`. Name the folders or files to compile.
- **`another mql-compiler run is using this cache, waiting for it to finish`**: not an error. Another run for the same user is going; this one starts when it ends.
- **`not an .mq4 or .mq5 file`**: a header or other file was named directly; name the `.mq4`/`.mq5` that includes it.
- **`no .mq4 or .mq5 files found`**: the folders given hold no sources (symlinked sources inside a folder are skipped).
- **`FAIL ...: MetaEditor wrote no result`**: MetaEditor crashed or never ran for that file. The lines below it are whatever it logged; run again, and run `mql-compiler --setup` if it repeats.
- **`file '...' not found` for a custom header**: the source is not under the `MQL4`/`MQL5` folder whose `Include` holds that header, or the include climbs out of the mounted folder.
- **Permission errors on every file on an SELinux host**: the mounts carry no `:z` label; relabel the source folders or run the image by hand with `:z` mounts.
