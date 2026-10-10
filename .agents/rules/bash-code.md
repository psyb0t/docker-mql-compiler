# Bash code rules

Prefix: SH.

Every script is Bash. `make lint` runs shellcheck, shfmt (`-i 4 -ci`) and hadolint; `make format` applies shfmt.

## Structure

- **SH1:** Every script starts with `#!/bin/bash` and `set -euo pipefail`. `entrypoint.sh` and `tests/test.sh` also set an `ERR` trap that reports the file, line and exit code.
- **SH2:** `make lint` passes with no new `# shellcheck disable`. If one is unavoidable, the comment next to it says why.
- **SH3:** No magic numbers or strings in logic. Name them as `readonly` constants at the top of the file with a comment saying why the value is what it is (`STDLIB_UNPACK_TIMEOUT_SECONDS`, `SIGNATURE_ATTEMPTS`, `CRL_FETCH_FAILURE` in `entrypoint.sh`). Exit codes are the `EXIT_*` constants.
- **SH4:** Use guard clauses and `continue` to keep the happy path unindented, as `collect_sources` and `build_merged_root` do.
- **SH5:** Comments explain why, including the constraint or incident behind a choice (the `/inc` space limit, MetaEditor's backwards exit code, the CRL retry). Do not restate the code.
- **SH6:** `wrapper.sh` runs on users' machines, so it sticks to Bash 3.2 and coreutils that macOS also has: no associative arrays, no `${x,,}`, and empty arrays expanded as `${arr[@]+"${arr[@]}"}`. `entrypoint.sh` runs on Debian trixie and may use Bash 5 and GNU tools.

## Output and logging

- **SH7:** In `entrypoint.sh`, stdout carries only results (the ARC17 records, or their `--text`/`gnu` renderings) and `--help`. Build every JSON record with `jq -n --arg`/`--argjson`, never by string interpolation. Every diagnostic goes through `log LEVEL "msg key=value"`, which writes one JSON line (time, level, file, line, func, msg) to stderr through `jq`. `die` also writes an `error` record to fd 7 (the real stdout) in JSON mode.
- **SH8:** Decisions that retry, fall back or skip log at `WARN` with a `reason=` value (`reason=crl_unreachable`); failures that end the run log at `ERROR` before exiting.
- **SH9:** `install.sh` is a user-facing CLI: it prints plain one-line messages, not JSON. `wrapper.sh` prints its errors as a plain line on stderr and, in JSON mode, also as an `error` record on stdout (escaped by `json_string`, since the host may lack `jq`). `action/run.sh` talks to GitHub through workflow commands (`::error`, `::warning`) and `$GITHUB_OUTPUT`/`$GITHUB_STEP_SUMMARY`.
- **SH10:** Never silence a command (`2>/dev/null`, `>/dev/null`, `|| true`) without a comment on that line or the one above saying why the output or the failure does not matter (Wine and Xvfb noise, MetaEditor's exit code, best-effort cleanup).
- **SH11:** A failure inside `$(...)` must still stop the run: collect into a variable with a command substitution, not a process substitution, where `die` has to end the script (see `main`).
