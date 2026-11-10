# Testing rules

Prefix: TST.

## What every change needs

- **TST1:** `make test` passes before a change is called done. It builds the image and runs `tests/test.sh`. CI runs `make test-ci`: `make test-all` under a 25-minute limit, printing the compiler's `last-run.log` when it fails. `make test-all` adds a real release install from Docker Hub (`MQL_COMPILER_TEST_RELEASE_INSTALL=1`); run it locally before changing `install.sh`. A change to any `.sh` file or the `Dockerfile` also needs `make lint`.
- **TST3:** Tests of the command's and the image's behaviour (options, path rules, include rules, output formats, exit codes) go in `tests/test.sh`.

## How the suite works

- **TST5:** The suite is end to end: it runs the built image, by hand (`compile`, sources at `/src`) and through `wrapper.sh` (`wrapped`, from other directories with relative and absolute paths), and checks stdout, stderr, the exit status and the files written. Keep both paths covered; the wrapper's mounts are where path bugs live. Check JSON results with `expect_record` and a `jq` condition on the fields, not by matching text; keep text matching for `--text` and `--format gnu` tests.
- **TST11:** `make test` exercises every option, including a real `--update` (a second full install) and its rollback, `--watch` (started, changed, a change in an `-I` directory, a run between passes, then stopped with `docker stop`), first runs that fail (an unreachable installer, an unsigned one), `action/run.sh` with GitHub's files faked, and `install.sh` against a throwaway `HOME`. CI additionally runs the GitHub Action against the built image (`uses: ./` in the `action` job of `pipeline.yml`); a change to `action.yml` or `action/run.sh` keeps those steps passing.
- **TST12:** Logic that cannot be reached end to end without a real broken certificate or a crashing MetaEditor is tested in `tests/unit/`: scripts that run inside the image, source the entrypoint (its `main` runs only when executed), stub one function such as `signature_report` or `wine`, and print `PASS`/`FAIL` lines that `run_unit` in `tests/test.sh` counts. State shared with a `$(...)` subshell goes through files, and arrays the entrypoint declares stay global with `declare -g`.
- **TST6:** Each test group starts from `fresh_workdir`, a copy of `tests/fixtures/` in `.testing/work`, so outputs never land in the repository and one test cannot leak into the next.
- **TST7:** Fixtures under `tests/fixtures/` mirror a real tree: `MQL4/` and `MQL5/` with `Experts`, `Indicators`, `Scripts`, `Include` and `Files`, plus `loose/` outside both. A fixture that must fail or must prove an override says so in a comment at its top (`Broken.mq5`, `Override.mq5`, the shadowing `VirtualKeys.mqh` and `WinUser32.mqh`).
- **TST8:** A fixture that proves an include or resource is used must fail to compile when it is missing (`Override.mq5` uses a macro only the user's header defines; the missing-resource test removes `MQL5/Files`). A test that passes either way proves nothing.
- **TST9:** `.testing/cache` holds the installed toolchain between runs (about 2 GB, about 90 seconds to build). To test setup itself, remove only the part under test (for example the unpacked `MQL5`/`MQL4` directories in `wine/drive_c/terminals/mt5` or `mt4`, or a terminal directory moved back under `Program Files` to test the migration), not the whole cache, and list it before deleting. CI always starts from an empty cache, so it covers a full first run.
