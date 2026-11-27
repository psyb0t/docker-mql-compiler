# Troubleshooting mql-compiler

Messages you may see on stderr or in an `error` record, what they mean, and what to do. Installing or reinstalling the command is the user's job: report the problem and point them to https://psyb0t.github.io/docker-mql-compiler/.

- **`docker is not installed`**: Docker's CLI is not on `PATH`.
- **`cannot talk to Docker`**, or an exit status of `125`: the daemon is down, the user is not allowed to use Docker, or the image is not available. On an ARM machine the image has no matching manifest, because it is amd64 only.
- **`toolchain setup failed`**: the installer download or its signature check failed, the install did not finish in time or finished without a MetaEditor, or the terminal did not unpack its standard library. The stderr log lines just before it say which. Retry once; if it repeats, report those lines to the user.
- **`toolchain update failed`**: `--update` could not refresh the toolchain; the previous toolchain is back in place. The log lines before it say why.
- **`wine: socket : Function not implemented`**, or `creating the Wine prefix did not finish`: Docker's default seccomp filter refuses a call Wine needs. The installed command is out of date or is being run without its seccomp profile; tell the user to reinstall it.
- **`no such seccomp profile`**: the profile the command points at is gone; tell the user to reinstall it.
- **`installer did not finish`**: a platform's installer ran past its time limit and was stopped, usually a slow connection. Run `mql-compiler --setup` again.
- **`the terminal did not unpack its standard library`**: run `mql-compiler --setup` again; if it keeps failing, run `mql-compiler --update`.
- **`... belongs to UID N, not M: the cache was written by another UID`**: that cache directory was created by a different user ID. Run as the original user and tell the user about it.
- **A "no such file" message**: the path does not exist (relative paths start at the current directory).
- **`refusing to mount / into the container`**: `mql-compiler` ran with no path from `/`, or a loose file sits directly in `/`. Name the directories or files to compile.
- **`another mql-compiler run is using this cache, waiting for it to finish`**: not an error. Another run for the same user is going; this one starts when it ends.
- **`not an .mq4 or .mq5 file`**: a header or other file was named directly; name the `.mq4`/`.mq5` that includes it.
- **`no .mq4 or .mq5 files found`**: the directories given hold no sources (symlinked sources inside a directory are skipped).
- **`MetaEditor wrote no result`** (a `failed` record with `errors: null` and a `log` field): MetaEditor crashed or never ran for that file. `log` holds whatever it wrote; run again, and run `mql-compiler --update` if it repeats.
- **A "no such include" or "-I needs" message**: an `-I` path is missing or does not exist.
- **`file '...' not found` for a custom header**: the source is not under the `MQL4`/`MQL5` directory whose `Include` holds that header, or the include climbs out of the mounted directory.
- **Permission errors on every file on an SELinux host**: the mounts carry no relabel option; tell the user.
