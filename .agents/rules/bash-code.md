# Bash code rules

Prefix: SH.

Every script is Bash. `make lint` runs shellcheck, shfmt (`-i 4 -ci`) and hadolint; `make format` applies shfmt.

## Structure

- **SH1:** `entrypoint.sh` and `tests/test.sh` set an `ERR` trap that reports the file, line and exit code.
- **SH3:** Exit codes are the `EXIT_*` constants in `entrypoint.sh`.
- **SH6:** `wrapper.sh` runs on users' machines, so it sticks to Bash 3.2 and coreutils that macOS also has: no associative arrays, no `${x,,}`, and empty arrays expanded as `${arr[@]+"${arr[@]}"}`. `entrypoint.sh` runs on Debian trixie and may use Bash 5 and GNU tools.

## Output and logging

- **SH7:** In `entrypoint.sh`, stdout carries only results (the ARC17 records, or their `--text`/`gnu` renderings) and `--help`. Build every JSON record with `jq -n --arg`/`--argjson`, never by string interpolation. Every diagnostic goes through `log LEVEL "msg key=value"`, which writes one JSON line (time, level, file, line, func, msg) to stderr through `jq`. `die` also writes an `error` record to fd 7 (the real stdout) in JSON mode.
- **SH8:** Decisions that retry, fall back or skip log at `WARN` with a `reason=` value (`reason=crl_unreachable`); failures that end the run log at `ERROR` before exiting.
- **SH9:** `install.sh` is a user-facing CLI: it prints plain one-line messages, not JSON. `wrapper.sh` prints its errors as a plain line on stderr and, in JSON mode, also as an `error` record on stdout (escaped by `json_string`, since the host may lack `jq`). `action/run.sh` talks to GitHub through workflow commands (`::error`, `::warning`) and `$GITHUB_OUTPUT`/`$GITHUB_STEP_SUMMARY`.
