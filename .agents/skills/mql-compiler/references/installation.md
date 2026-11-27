# Installing mql-compiler

`mql-compiler` is one file on `PATH` that runs the `psyb0t/mql-compiler` Docker image. The prerequisites are an x86-64 (amd64) machine, since there is no ARM image, and a running Docker daemon the user can talk to (`docker info` works without sudo).

## Install

Download the installer, read it, then run it. Per user, into `~/.local/bin`:

```bash
curl -fsSL https://raw.githubusercontent.com/psyb0t/docker-mql-compiler/master/install.sh \
  -o /tmp/mql-compiler-install.sh
less /tmp/mql-compiler-install.sh
bash /tmp/mql-compiler-install.sh
```

Optional, only when the user asks for a system-wide install into `/usr/local/bin` (needs root, after the same download and read):

```bash
sudo bash /tmp/mql-compiler-install.sh --system
```

| Option | Effect |
|---|---|
| `--user` | Install to `~/.local/bin` (the default when not root) |
| `--system` | Install to `/usr/local/bin` (the default as root; needs root) |
| `--rolling` | Pin the moving `latest` tag of the image instead of the newest release tag |
| `--uninstall` | Remove the command and the image it was pinned to; the toolchain volume stays |

The installer pins the newest GitHub release tag, pulls it, and writes the pin into the command file. There is no config directory. It refuses to overwrite a file at the target path that it did not install. A per-user install warns when `~/.local/bin` is not on `PATH` and prints the line to add to `~/.bashrc` or `~/.zshrc`. It only prints that line: the installer edits no shell file.

## Upgrade

Download and run the installer again, as above. It pins the newest release and removes the image it replaced.

The MT4 and MT5 toolchain in the cache does not change with the image: it stays on the MetaEditor builds installed on the first run. `mql-compiler --version` shows them, and `mql-compiler --update` reinstalls both from the newest installers (about a minute and a half). If the reinstall fails, the previous toolchain is put back.

## First run

The first compile downloads the MT4 and MT5 installers, checks their signatures (valid digest, a trusted certificate chain, a signing certificate whose common name starts with `MetaQuotes`), and installs both into the `mql-compiler-cache` Docker volume. The installers leave the standard library packed, so setup then starts each terminal once, headless, until it has unpacked its `MQL4`/`MQL5` directory, stops it, and moves the terminal to a portable directory in the volume (`terminals/mt4`, `terminals/mt5`). A cache made by an older version gets that move on its next run, without downloading anything. All of it takes about a minute and a half and about 2 GB of disk. `mql-compiler --setup` does only this, which is handy before a timed job. Later runs reuse the volume and take seconds.

A compile installs only the platforms its sources need: a run of only `.mq5` files installs MT5 alone, and MT4 follows the first time a `.mq4` shows up. A platform given a portable terminal with `--mt4-terminal`/`--mt5-terminal` is never downloaded; the run uses that terminal's MetaEditor and standard library, mounted read-only, and only creates the Wine prefix.

To use another broker's installers, set `MQL_COMPILER_MT4_URL` and `MQL_COMPILER_MT5_URL` together with a new `MQL_COMPILER_VOLUME` name, and keep that volume name for later runs. Removing `mql-compiler-cache` instead works too, but it deletes every user's toolchain on the machine.

## Uninstall

Only when the user asks. With the installer already downloaded as above:

```bash
bash /tmp/mql-compiler-install.sh --uninstall
```

Use `sudo bash /tmp/mql-compiler-install.sh --system --uninstall` for a system-wide install. The uninstaller removes the command, its seccomp profile and the image it was pinned to (it warns and keeps the image if a container still uses it). The toolchain volume stays. Removing it frees about 2 GB, but it holds the toolchain of every user on the machine and the next compile downloads it again, so do it only when the user asks for that specific step:

```bash
docker volume rm mql-compiler-cache
```

## Checks

```bash
command -v mql-compiler        # installed and on PATH
mql-compiler --version         # the image runs; shows its version and the MetaEditor builds (null before the first run)
docker volume ls | grep mql-compiler-cache   # toolchain cached (after the first run)
docker run --rm -v mql-compiler-cache:/c:ro busybox:1.37.0 cat /c/uid-$(id -u)/logs/last-run.log   # the last run's full output
```

## Troubleshooting

- **`docker is not installed`**: Docker's CLI is not on `PATH`.
- **`cannot talk to Docker`** (installer) or an exit status of `125`: the daemon is down, the user is not in the `docker` group, or the image could not be pulled. On an ARM machine the pull fails with "no matching manifest".
- **`toolchain setup failed`**: the installer download or its signature check failed, the install did not finish in time or finished without a MetaEditor, or the terminal did not unpack its standard library. The stderr log lines just before it say which. Retry; a custom installer URL must point at a MetaQuotes-signed setup file.
- **`toolchain update failed`**: `--update` could not reinstall; the previous toolchain is back in place. The log lines before it say why.
- **`wine: socket : Function not implemented`**, or `creating the Wine prefix did not finish`, on Linux 7.0 (Ubuntu 26.04): Docker's default seccomp filter refuses a call Wine needs. The command passes its own profile, so this means it runs without one: an old install (run the installer again), or a `docker run` by hand without `--security-opt seccomp=` pointing at `seccomp/wine.json`.
- **`no such seccomp profile`**: `MQL_COMPILER_SECCOMP`, or the profile the installer wrote, points at a file that is gone. Run the installer again.
- **`installer did not finish`** (log line): a platform's installer ran longer than `MQL_COMPILER_INSTALL_TIMEOUT` seconds (600 by default) and was stopped. The installer downloads the terminal itself and then starts it, so this is a slow connection or a terminal waiting on a dialog. Run `mql-compiler --setup` again, with a larger `MQL_COMPILER_INSTALL_TIMEOUT` on a slow link.
- **`the terminal did not unpack its standard library`** (log line): the terminal started but never wrote its headers within two minutes. Run `mql-compiler --setup` again; if it keeps failing, run `mql-compiler --update`.
- **`... belongs to UID N, not M: the cache was written by another UID`**: that cache directory was created by a different user ID inside the same volume. Run as the original user, or use your own `MQL_COMPILER_VOLUME`.
- **`no such file or folder`**: the path does not exist (relative paths start at the current directory).
- **`refusing to mount / into the container`**: `mql-compiler` ran with no path from `/`, or a loose file sits directly in `/`. Name the directories or files to compile.
- **`another mql-compiler run is using this cache, waiting for it to finish`**: not an error. Another run for the same user is going; this one starts when it ends.
- **`not an .mq4 or .mq5 file`**: a header or other file was named directly; name the `.mq4`/`.mq5` that includes it.
- **`no .mq4 or .mq5 files found`**: the directories given hold no sources (symlinked sources inside a directory are skipped).
- **`MetaEditor wrote no result`** (a `failed` record with `errors: null` and a `log` field): MetaEditor crashed or never ran for that file. `log` holds whatever it wrote; run again, and run `mql-compiler --update` if it repeats.
- **`no such include folder`** / **`-I needs a folder`**: an `-I` path is missing or does not exist.
- **`file '...' not found` for a custom header**: the source is not under the `MQL4`/`MQL5` directory whose `Include` holds that header, or the include climbs out of the mounted directory.
- **Permission errors on every file on an SELinux host**: the mounts carry no `:z` label; relabel the source directories or run the image by hand with `:z` mounts.
