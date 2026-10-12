# GitHub Action

Compile on every push, fail the job on errors, and get each error marked on its source line in the PR:

```yaml
- uses: actions/checkout@v6
- uses: psyb0t/docker-mql-compiler@v0.5.0
  with:
    paths: |
      MQL5/Experts
      MQL4/Indicators/Bands.mq4
```

| Input | Default | What it does |
|---|---|---|
| `paths` | `.` | Files or folders to compile, one per line |
| `include` | none | Extra `-I` folders, one per line |
| `werror` | `false` | Fail on warnings |
| `image` | the release matching the action's ref | Image to run; a branch ref like `@master` runs `:latest` |
| `cache` | `true` | Keep the 2 GB toolchain in the Actions cache, so only the first run pays the 90-second install |
| `cache-dir` | under `RUNNER_TEMP` | Where the toolchain lives on the runner |

Outputs: `results` (the path of the JSON Lines file), `total`, `compiled`, `failed`. The job summary gets a table of every file. Paths in annotations are relative to the repository root, so run it from there (the default).

## Running the image by hand

The command is just a thin `docker run`. Doing it yourself:

```bash
# run from the folder that holds MQL5/
docker run --rm --init \
  --user "$(id -u):$(id -g)" \
  -v "$PWD":/src \
  -v mql-compiler-cache:/cache \
  psyb0t/mql-compiler:v0.5.0 MQL5/Experts
```

Mount your sources at `/src` (the image's working folder, so relative paths start there) and keep `/cache` on a volume. Skip the volume and every single run reinstalls the whole toolchain, which gets old fast. The image only sees what you mount, so mount the `MQL4`/`MQL5` folder or its parent, never just `Experts`, or your `Include` stays outside. Add `-e MQL_COMPILER_MT4_URL=...` and `-e MQL_COMPILER_MT5_URL=...` for other installers. An `-I` folder has to be mounted too. `--init` lets Ctrl-C reach the compiler, which `--watch` needs. The command does the same thing with each folder mounted at its own host path and `-w "$PWD"`, which is why its output shows your real paths.

[Back to the README](../README.md).
