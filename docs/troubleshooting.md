---
title: "Troubleshooting"
description: "What each mql-compiler error message means and how to fix it: Docker problems, failed toolchain setup, seccomp, missing paths, includes and MetaEditor crashes."
nav_order: 6
---

# Troubleshooting

The messages below are quoted as the command prints them, so you can search this page for the line you got. In the default JSON mode a message that stops the run arrives as an `error` record on stdout. Progress and log lines go to stderr as JSON.

The full output of the last run, setup and failed runs included, is kept in the cache volume and replaced on every run:

```bash
docker run --rm \
  -v mql-compiler-cache:/c \
  busybox cat "/c/uid-$(id -u)/logs/last-run.log"
```

## Docker

- **`docker is not installed`**: Docker's CLI isn't on your `PATH`.
- **`cannot talk to Docker`** from the installer, or exit status `125` from the command: the daemon is down, your account isn't in the `docker` group, or the image couldn't be pulled. On an ARM machine the pull fails because there's no ARM image.
- **Permission errors on every file on an SELinux host**: the mounts carry no `:z` label. Relabel the source directories, or [run the image by hand](ci-and-docker.md#running-the-image-by-hand) with `:z` on the mounts.

## Setup and the toolchain

- **`toolchain setup failed`**: the installer download or its signature check failed, the install didn't finish in time or finished without a MetaEditor, or the terminal didn't unpack its standard library. The stderr log lines right before it say which. Retry. A custom installer URL must point at a MetaQuotes-signed setup file.
- **`installer did not finish`** (log line): a platform's installer ran longer than `MQL_COMPILER_INSTALL_TIMEOUT` seconds (600 by default) and got stopped. The installer downloads the terminal itself and then starts it, so this is a slow connection or a terminal stuck on a dialog. Run `mql-compiler --setup` again, with a bigger `MQL_COMPILER_INSTALL_TIMEOUT` on a slow link.
- **`the terminal did not unpack its standard library`** (log line): the terminal started but never wrote its headers within two minutes. Run `mql-compiler --setup` again. If it keeps failing, run `mql-compiler --update`.
- **`toolchain update failed`**: `--update` couldn't reinstall, and the previous toolchain is back in place. The log lines before it say why.
- **`... belongs to UID N, not M: the cache was written by another UID`**: that cache directory inside the volume was created by a different user ID. Run as the original user, or give yourself your own `MQL_COMPILER_VOLUME`.
- **`another mql-compiler run is using this cache, waiting for it to finish`**: not an error. Another run for the same user is going, and this one starts when it ends.

## Seccomp and Linux 7.0

- **`wine: socket : Function not implemented`**, or **`creating the Wine prefix did not finish`**, on Linux 7.0 (Ubuntu 26.04): Docker's default seccomp filter refuses the `userfaultfd` call Wine needs. The command passes its own profile, so this means it ran without one: an old install (run the installer again), or a `docker run` by hand without `--security-opt seccomp=` pointing at a copy of [`seccomp/wine.json`](https://github.com/psyb0t/docker-mql-compiler/blob/master/seccomp/wine.json).
- **`no such seccomp profile`**: `MQL_COMPILER_SECCOMP`, or the profile the installer wrote, points at a file that's gone. Run the installer again.

## Paths and options

- **`no such file or folder`**: the path doesn't exist. Relative paths start at the current directory.
- **`refusing to mount / into the container`**: `mql-compiler` ran with no path from `/`, a loose file sits directly in `/`, or a terminal option points at `/`. Name the directories or files to compile.
- **`not an .mq4 or .mq5 file`**: you named a header or some other file directly. Name the `.mq4` or `.mq5` that includes it.
- **`no .mq4 or .mq5 files found`**: the directories you gave hold no sources. Symlinked sources inside a directory are skipped.
- **`no such include folder`** or **`-I needs a folder`**: an `-I` path is missing or doesn't exist.
- **`no such terminal folder`**, **`no metaeditor64.exe in the --mt5-terminal folder`** (or `metaeditor.exe` for MT4), or **`no unpacked standard library`**: the `--mt4-terminal`/`--mt5-terminal` directory is wrong, or the terminal was never started, so it never unpacked its headers. Start the terminal once, then run again. See [bring your own terminal](usage.md#bring-your-own-terminal).
- **`unknown option`** or **`unknown format`**: check `mql-compiler --help`. `--format` takes `json`, `text` or `gnu`.

## Compile results

- **`file '...' not found` on a custom header**: the source isn't under the `MQL4`/`MQL5` directory whose `Include` holds that header, or the include climbs out of the mounted directory. See [how your tree should look](usage.md#how-your-tree-should-look).
- **An error inside a standard header**: it's reported at the header's path in the toolchain (`/cache/uid-<UID>/wine/drive_c/...`, inside the cache volume). It usually means your code broke something the header relies on, such as a macro named like a standard class. Fix your code, not the toolchain.
- **`MetaEditor wrote no result`** (a `failed` record with `errors: null` and a `log` field): MetaEditor crashed or never ran for that file. `log` holds whatever it wrote. Run again, and run `mql-compiler --update` if it keeps happening.
