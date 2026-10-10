#!/bin/bash
# End-to-end tests: run the built image the way a user does, against copies of
# tests/fixtures, and check what comes out and how it exits.
#
#   IMAGE=psyb0t/mql-compiler:dev TEST_CACHE=/abs/cache bash tests/test.sh
#
# The first run downloads and installs the MetaQuotes toolchain into
# TEST_CACHE (about a minute and a half); later runs reuse it.
set -euo pipefail
trap 'echo "[test] ERROR ${BASH_SOURCE[0]}:${LINENO}: command failed (exit $?)" >&2' ERR

readonly IMAGE="${IMAGE:?IMAGE must name the image under test}"
readonly TEST_CACHE="${TEST_CACHE:?TEST_CACHE must be an absolute path}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_ROOT
readonly WORK_ROOT="$REPO_ROOT/.testing/work"
readonly EXIT_OK=0
readonly EXIT_COMPILE_ERRORS=1
readonly EXIT_USAGE=2

passed=0
failed=0

log() {
    printf '[test] %s\n' "$*" >&2
}

pass() {
    passed=$((passed + 1))
    printf 'PASS %s\n' "$1"
}

fail() {
    failed=$((failed + 1))
    printf 'FAIL %s: %s\n' "$1" "$2"
}

# A fresh copy of the fixtures, so outputs never land in the repository.
fresh_workdir() {
    rm -rf "$WORK_ROOT"
    mkdir -p "$WORK_ROOT"
    cp -r "$REPO_ROOT/tests/fixtures/." "$WORK_ROOT/"
}

# Runs the compiler on the work copy; sets OUT (stdout + stderr) and STATUS.
compile() {
    STATUS=0
    OUT="$(docker run --rm --user "$(id -u):$(id -g)" \
        -v "$WORK_ROOT":/src -v "$TEST_CACHE":/cache \
        "$IMAGE" "$@" 2>&1)" || STATUS=$?
}

expect_status() {
    local name="$1" want="$2"
    if [[ "$STATUS" == "$want" ]]; then
        pass "$name exits $want"
        return
    fi
    fail "$name" "exit $STATUS, want $want"
    printf '%s\n' "$OUT" | sed 's/^/     /'
}

expect_output() {
    local name="$1" pattern="$2"
    if grep -qE -- "$pattern" <<<"$OUT"; then
        pass "$name"
        return
    fi
    fail "$name" "output lacks /$pattern/"
}

expect_file_mine() {
    local name="$1" path="$WORK_ROOT/$2"
    if [[ -s "$path" && "$(stat -c %u "$path")" == "$(id -u)" ]]; then
        pass "$name"
        return
    fi
    fail "$name" "$2 missing, empty or not owned by UID $(id -u)"
}

main() {
    mkdir -p "$TEST_CACHE"

    log "whole tree: both platforms, includes, a broken file (first run installs the toolchain)"
    fresh_workdir
    compile
    expect_status "whole tree with a broken file" "$EXIT_COMPILE_ERRORS"
    expect_output "MQL4 expert compiles against MQL4/Include" '^OK   MQL4/Experts/Hello\.mq4 -> MQL4/Experts/Hello\.ex4'
    expect_output "MQL5 expert compiles against MQL5/Include" '^OK   MQL5/Experts/Hello\.mq5 -> MQL5/Experts/Hello\.ex5'
    expect_output "broken file is reported" '^FAIL MQL5/Experts/Broken\.mq5 \(2 errors'
    expect_output "error carries file, line and column" "MQL5/Experts/Broken\\.mq5\\(5,4\\) : error 256: undeclared identifier 'undeclared_function'"
    expect_file_mine ".ex4 lands next to its source, owned by the caller" MQL4/Experts/Hello.ex4
    expect_file_mine ".ex5 lands next to its source, owned by the caller" MQL5/Experts/Hello.ex5

    log "one file"
    fresh_workdir
    compile MQL5/Experts/Hello.mq5
    expect_status "one good file" "$EXIT_OK"
    expect_output "only that file is compiled" 'run complete total=1 compiled=1 failed=0'

    log "one folder"
    fresh_workdir
    compile MQL4
    expect_status "the MQL4 folder" "$EXIT_OK"
    expect_output "only MQL4 sources are compiled" 'run complete total=1 compiled=1 failed=0'

    log "a missing include"
    fresh_workdir
    printf '%s\n' '#include <Fixture/Missing.mqh>' 'void OnTick() {}' >"$WORK_ROOT/MQL5/Experts/NoInclude.mq5"
    compile MQL5/Experts/NoInclude.mq5
    expect_status "a missing include" "$EXIT_COMPILE_ERRORS"
    expect_output "the missing include is named" "Fixture/Missing\\.mqh"

    log "usage errors"
    fresh_workdir
    compile does/not/exist.mq5
    expect_status "a path that does not exist" "$EXIT_USAGE"
    compile MQL5/Include/Fixture/Greeting.mqh
    expect_status "a file that is not .mq4 or .mq5" "$EXIT_USAGE"
    compile --no-such-option
    expect_status "an unknown option" "$EXIT_USAGE"
    compile --help
    expect_status "--help" "$EXIT_OK"

    rm -rf "$WORK_ROOT"
    printf '\n%d passed, %d failed\n' "$passed" "$failed"
    ((failed == 0))
}

main "$@"
