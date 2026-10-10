#!/bin/bash
# End-to-end tests: run the built image the way a user does, both by hand
# (`docker run` with the folder at /src) and through wrapper.sh, against
# copies of tests/fixtures, and check what comes out and how it exits.
#
#   IMAGE=psyb0t/mql-compiler:dev TEST_CACHE=/abs/cache bash tests/test.sh
#
# The first run downloads and installs the MetaQuotes toolchain into
# TEST_CACHE (about a minute and a half); later runs reuse it. The --update
# test reinstalls it once more. Needs jq on the host.
set -euo pipefail
trap 'echo "[test] ERROR ${BASH_SOURCE[0]}:${LINENO}: command failed (exit $?)" >&2' ERR

readonly IMAGE="${IMAGE:?IMAGE must name the image under test}"
readonly TEST_CACHE="${TEST_CACHE:?TEST_CACHE must be an absolute path}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
readonly REPO_ROOT
readonly WORK_ROOT="$REPO_ROOT/.testing/work"
readonly WORK_FROM_REPO=".testing/work"
readonly WRAPPER="$REPO_ROOT/wrapper.sh"
readonly EXIT_OK=0
readonly EXIT_COMPILE_ERRORS=1
readonly EXIT_USAGE=2
# How long the --watch test waits for each pass before giving up.
readonly WATCH_TIMEOUT_SECONDS=120
readonly WATCH_POLL_SECONDS=2

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

# Runs the image by hand on the work copy; sets OUT (stdout), ERR (stderr)
# and STATUS.
compile() {
    local err_file
    err_file="$(mktemp)"
    STATUS=0
    OUT="$(docker run --rm --user "$(id -u):$(id -g)" \
        -v "$WORK_ROOT":/src -v "$TEST_CACHE":/cache \
        "$IMAGE" "$@" 2>"$err_file")" || STATUS=$?
    ERR="$(cat "$err_file")"
    rm -f "$err_file"
}

# Runs wrapper.sh from folder $1 with the rest as arguments; sets OUT, ERR
# and STATUS.
wrapped() {
    local from="$1" err_file
    shift
    err_file="$(mktemp)"
    STATUS=0
    OUT="$(cd "$from" && MQL_COMPILER_IMAGE="$IMAGE" MQL_COMPILER_VOLUME="$TEST_CACHE" \
        bash "$WRAPPER" "$@" 2>"$err_file")" || STATUS=$?
    ERR="$(cat "$err_file")"
    rm -f "$err_file"
}

expect_status() {
    local name="$1" want="$2"
    if [[ "$STATUS" == "$want" ]]; then
        pass "$name exits $want"
        return
    fi
    fail "$name" "exit $STATUS, want $want"
    printf '%s\n%s\n' "$OUT" "$ERR" | sed 's/^/     /'
}

# Passes when stdout matches the extended regex.
expect_output() {
    local name="$1" pattern="$2"
    if grep -qE -- "$pattern" <<<"$OUT"; then
        pass "$name"
        return
    fi
    fail "$name" "stdout lacks /$pattern/"
}

# Passes when stderr (the log lines) matches the extended regex.
expect_log() {
    local name="$1" pattern="$2"
    if grep -qE -- "$pattern" <<<"$ERR"; then
        pass "$name"
        return
    fi
    fail "$name" "stderr lacks /$pattern/"
}

# Passes when stdout is JSON Lines and at least one record makes the jq
# expression true.
expect_record() {
    local name="$1" condition="$2"
    if jq -e -n "[inputs | select($condition)] | length > 0" <<<"$OUT" >/dev/null 2>&1; then
        pass "$name"
        return
    fi
    fail "$name" "no stdout record where $condition"
}

# The "file" record condition for one source with the given status.
file_is() {
    printf '.type == "file" and .source == "%s" and .status == "%s"' "$1" "$2"
}

expect_file_mine() {
    local name="$1" path="$WORK_ROOT/$2"
    if [[ -s "$path" && "$(stat -c %u "$path")" == "$(id -u)" ]]; then
        pass "$name"
        return
    fi
    fail "$name" "$2 missing, empty or not owned by UID $(id -u)"
}

test_whole_tree() {
    log "whole tree by hand: both platforms, every program type, the standard library (first run installs the toolchain)"
    fresh_workdir
    compile
    expect_status "whole tree with a broken file" "$EXIT_COMPILE_ERRORS"
    if jq -e -n '[inputs] | all(.type == "file" or .type == "summary")' <<<"$OUT" >/dev/null; then
        pass "stdout is JSON Lines with file and summary records only"
    else
        fail "stdout is JSON Lines with file and summary records only" "got: $OUT"
    fi
    expect_record "the summary counts every file" '.type == "summary" and .total == 13 and .compiled == 12 and .failed == 1 and .werror == false'
    expect_record "MQL4 expert finds MQL4/Include" "$(file_is MQL4/Experts/Hello.mq4 ok) and .output == \"MQL4/Experts/Hello.ex4\" and .platform == \"mt4\""
    expect_record "MQL5 expert finds MQL5/Include" "$(file_is MQL5/Experts/Hello.mq5 ok) and .output == \"MQL5/Experts/Hello.ex5\" and .platform == \"mt5\""
    expect_record "MQL4 expert finds the standard <stdlib.mqh>" "$(file_is MQL4/Experts/StdLib.mq4 ok)"
    expect_record "MQL5 expert finds the standard <Trade/Trade.mqh>" "$(file_is MQL5/Experts/StdLib.mq5 ok)"
    expect_record "a user header replaces the MQL4 standard one" "$(file_is MQL4/Experts/Override.mq4 ok)"
    expect_record "a user header replaces the MQL5 standard one" "$(file_is MQL5/Experts/Override.mq5 ok)"
    expect_record "#resource reaches MQL5/Files" "$(file_is MQL5/Experts/Resource.mq5 ok)"
    expect_record "MQL4 indicator compiles" "$(file_is MQL4/Indicators/Line.mq4 ok)"
    expect_record "MQL5 indicator compiles" "$(file_is MQL5/Indicators/Line.mq5 ok)"
    expect_record "MQL4 script compiles" "$(file_is MQL4/Scripts/Say.mq4 ok)"
    expect_record "MQL5 script compiles" "$(file_is MQL5/Scripts/Say.mq5 ok)"
    expect_record "a file outside MQL4/MQL5 gets the standard library" "$(file_is loose/Loose.mq5 ok) and .output == \"loose/Loose.ex5\""
    expect_record "broken file is reported with its counts" "$(file_is MQL5/Experts/Broken.mq5 failed) and .errors == 2 and .output == null"
    expect_record "an error carries file, line, column, code and text" \
        "$(file_is MQL5/Experts/Broken.mq5 failed) and (.messages | any(.severity == \"error\" and .file == \"MQL5/Experts/Broken.mq5\" and .line == 5 and .column == 4 and .code == 256 and .text == \"undeclared identifier 'undeclared_function'\"))"
    expect_log "stderr carries the JSON log lines" '"level":"INFO".*"msg":"run complete total=13 compiled=12 failed=1"'
    expect_file_mine ".ex4 lands next to its source, owned by the caller" MQL4/Experts/Hello.ex4
    expect_file_mine ".ex5 lands next to its source, owned by the caller" MQL5/Experts/Hello.ex5
}

test_output_formats() {
    log "--text and --format gnu"
    fresh_workdir
    compile --text MQL5/Experts/Hello.mq5 MQL5/Experts/Broken.mq5
    expect_status "--text" "$EXIT_COMPILE_ERRORS"
    expect_output "--text prints OK lines" '^OK   MQL5/Experts/Hello\.mq5 -> MQL5/Experts/Hello\.ex5 \(0 warnings\)$'
    expect_output "--text prints FAIL lines" '^FAIL MQL5/Experts/Broken\.mq5 \(2 errors, 0 warnings\)$'
    expect_output "--text prints MetaEditor's message lines" "^     MQL5/Experts/Broken\\.mq5\\(5,4\\) : error 256: undeclared identifier 'undeclared_function'$"
    compile --format gnu MQL5/Experts/Broken.mq5
    expect_status "--format gnu" "$EXIT_COMPILE_ERRORS"
    expect_output "--format gnu prints path:line:column lines" "^MQL5/Experts/Broken\\.mq5:5:4: error: undeclared identifier 'undeclared_function' \\[256\\]$"
    compile --format=gnu MQL5/Experts/Hello.mq5
    expect_status "--format=gnu on a clean file" "$EXIT_OK"
    if [[ -z "$OUT" ]]; then
        pass "--format gnu prints nothing for a clean file"
    else
        fail "--format gnu prints nothing for a clean file" "got: $OUT"
    fi
    compile --format xml MQL5/Experts/Hello.mq5
    expect_status "an unknown format" "$EXIT_USAGE"
}

test_warnings() {
    log "warnings and --werror"
    fresh_workdir
    # Assigning a double to an int is warning 43 on both platforms.
    printf '%s\n' 'void OnStart()' '{' '   double d = 1.5;' '   int i = d;' '   Print(i);' '}' >"$WORK_ROOT/MQL5/Scripts/Warn.mq5"
    compile MQL5/Scripts/Warn.mq5
    expect_status "a file with a warning" "$EXIT_OK"
    expect_record "a warning is reported and the file still compiles" \
        "$(file_is MQL5/Scripts/Warn.mq5 ok) and .warnings == 1 and (.messages | any(.severity == \"warning\" and .code == 43 and .line == 4))"
    compile --werror MQL5/Scripts/Warn.mq5 MQL5/Scripts/Say.mq5
    expect_status "--werror with a warning" "$EXIT_COMPILE_ERRORS"
    expect_record "--werror fails the file with a warning" "$(file_is MQL5/Scripts/Warn.mq5 failed) and .errors == 0 and .warnings == 1"
    expect_record "--werror leaves a clean file alone" "$(file_is MQL5/Scripts/Say.mq5 ok)"
    expect_record "--werror shows in the summary" '.type == "summary" and .werror == true and .failed == 1'
}

test_extra_includes() {
    log "-I folders"
    fresh_workdir
    mkdir -p "$WORK_ROOT/shared/Shared" "$WORK_ROOT/override/Fixture"
    printf '%s\n' 'string SharedHello() { return "shared"; }' >"$WORK_ROOT/shared/Shared/Lib.mqh"
    printf '%s\n' '#include <Shared/Lib.mqh>' 'void OnStart() { Print(SharedHello()); }' >"$WORK_ROOT/MQL5/Scripts/UsesShared.mq5"
    compile MQL5/Scripts/UsesShared.mq5
    expect_status "a shared header without -I" "$EXIT_COMPILE_ERRORS"
    compile -I shared MQL5/Scripts/UsesShared.mq5
    expect_status "-I by hand" "$EXIT_OK"
    expect_record "-I adds a folder to <...> includes" "$(file_is MQL5/Scripts/UsesShared.mq5 ok)"
    # The user's Include beats an -I folder: this copy would break Hello.mq5.
    printf '%s\n' 'this is not MQL' >"$WORK_ROOT/override/Fixture/Greeting.mqh"
    wrapped "$WORK_ROOT" --include "$WORK_ROOT/override" --include=shared MQL5/Experts/Hello.mq5 MQL5/Scripts/UsesShared.mq5
    expect_status "--include through the wrapper" "$EXIT_OK"
    expect_record "the user's Include wins over an -I folder" "$(file_is MQL5/Experts/Hello.mq5 ok)"
    compile -I does/not/exist MQL5/Experts/Hello.mq5
    expect_status "a missing -I folder" "$EXIT_USAGE"
}

test_selection() {
    log "one file, one folder"
    fresh_workdir
    compile MQL5/Experts/Hello.mq5
    expect_status "one good file" "$EXIT_OK"
    expect_record "only that file is compiled" '.type == "summary" and .total == 1 and .compiled == 1'
    compile MQL4
    expect_status "the MQL4 folder" "$EXIT_OK"
    expect_record "only MQL4 sources are compiled" '.type == "summary" and .total == 5 and .compiled == 5'
    compile MQL5/Scripts/Say.mq5 MQL5/Scripts
    expect_status "a file named twice" "$EXIT_OK"
    expect_record "a file named twice compiles once" '.type == "summary" and .total == 1'
}

test_include_errors() {
    log "a missing include, a missing resource"
    fresh_workdir
    printf '%s\n' '#include <Fixture/Missing.mqh>' 'void OnTick() {}' >"$WORK_ROOT/MQL5/Experts/NoInclude.mq5"
    compile MQL5/Experts/NoInclude.mq5
    expect_status "a missing include" "$EXIT_COMPILE_ERRORS"
    expect_record "the missing include is named" '.type == "file" and (.messages | any(.text | test("Fixture/Missing\\.mqh")))'
    rm -r "$WORK_ROOT/MQL5/Files"
    compile MQL5/Experts/Resource.mq5
    expect_status "a missing resource" "$EXIT_COMPILE_ERRORS"
    expect_record "the missing resource is named" '.type == "file" and (.messages | any(.text | test("greeting\\.txt. not found")))'
}

test_reported_paths() {
    log "paths in compiler messages, stale outputs"
    fresh_workdir
    printf '%s\n' '#include <Fixture/Missing.mqh>' 'void OnStart() {}' >"$WORK_ROOT/MQL5/Scripts/NoInclude.mq5"
    # Redefining a class name breaks the standard header that declares it.
    printf '%s\n' '#define CObject 1' '#include <Object.mqh>' 'void OnStart() {}' >"$WORK_ROOT/MQL5/Scripts/BreakStd.mq5"
    compile MQL5/Scripts/NoInclude.mq5 MQL5/Scripts/BreakStd.mq5
    expect_status "include errors" "$EXIT_COMPILE_ERRORS"
    expect_record "a missing include reads as under the user's Include" \
        ".type == \"file\" and (.messages | any(.text == \"file 'MQL5/Include/Fixture/Missing.mqh' not found\"))"
    expect_record "an error in a standard header shows the header's real path" \
        '.type == "file" and (.messages | any(.file != null and (.file | test("^/cache/uid-[0-9]+/wine/drive_c/.*/MQL5/Include/Object\\.mqh$")) and .severity == "error"))'

    # MetaEditor cannot delete a read-only .ex5; the compiler must.
    cp "$WORK_ROOT/MQL5/Experts/Broken.mq5" "$WORK_ROOT/MQL5/Scripts/Broken.mq5"
    printf 'stale\n' >"$WORK_ROOT/MQL5/Scripts/Broken.ex5"
    chmod a-w "$WORK_ROOT/MQL5/Scripts/Broken.ex5"
    compile MQL5/Scripts/Broken.mq5
    expect_status "a failing file with an old output" "$EXIT_COMPILE_ERRORS"
    if [[ -e "$WORK_ROOT/MQL5/Scripts/Broken.ex5" ]]; then
        fail "a failed compile leaves no old .ex5 behind" "MQL5/Scripts/Broken.ex5 still exists"
    else
        pass "a failed compile leaves no old .ex5 behind"
    fi

    local odd="$WORK_ROOT/odd & spaced"
    mkdir -p "$odd"
    cp -r "$REPO_ROOT/tests/fixtures/MQL5" "$odd/"
    wrapped "$WORK_ROOT" "odd & spaced/MQL5/Experts/Broken.mq5" "odd & spaced/MQL5/Experts/Hello.mq5"
    expect_status "a folder with & and spaces" "$EXIT_COMPILE_ERRORS"
    expect_record "& and spaces survive in error paths" \
        '.type == "file" and (.messages | any(.file == "odd & spaced/MQL5/Experts/Broken.mq5" and .line == 5 and .column == 4))'
    expect_record "& and spaces survive in output paths" \
        "$(file_is "odd & spaced/MQL5/Experts/Hello.mq5" ok) and .output == \"odd & spaced/MQL5/Experts/Hello.ex5\""
}

test_nested_platform_folders() {
    log "a .mq4 inside an MQL5 folder inside an MQL4 folder"
    fresh_workdir
    local nest="$WORK_ROOT/nest/MQL4"
    mkdir -p "$nest/Projects/MQL5"
    cp -r "$REPO_ROOT/tests/fixtures/MQL4/Include" "$nest/"
    cp "$REPO_ROOT/tests/fixtures/MQL4/Experts/Hello.mq4" "$nest/Projects/MQL5/"
    wrapped "$WORK_ROOT" nest/MQL4/Projects/MQL5/Hello.mq4
    expect_status "the wrapper mounts the MQL4 folder a .mq4 includes from" "$EXIT_OK"
}

test_wrapper() {
    log "the wrapper, from other folders"
    fresh_workdir
    wrapped "$REPO_ROOT" "$WORK_FROM_REPO/MQL5/Experts/StdLib.mq5" "$WORK_FROM_REPO/MQL4/Experts/StdLib.mq4"
    expect_status "relative paths below the current folder" "$EXIT_OK"
    expect_record "paths print relative to the current folder" \
        "$(file_is "$WORK_FROM_REPO/MQL4/Experts/StdLib.mq4" ok) and .output == \"$WORK_FROM_REPO/MQL4/Experts/StdLib.ex4\""
    wrapped / "$WORK_ROOT/MQL5/Experts/Resource.mq5"
    expect_status "an absolute path from /" "$EXIT_OK"
    expect_record "paths outside the current folder print absolute" \
        "$(file_is "$WORK_ROOT/MQL5/Experts/Resource.mq5" ok) and .output == \"$WORK_ROOT/MQL5/Experts/Resource.ex5\""
    wrapped "$WORK_ROOT/MQL5/Experts"
    expect_status "no path inside MQL5/Experts" "$EXIT_COMPILE_ERRORS"
    expect_record "no path compiles the current folder, includes found" "$(file_is Hello.mq5 ok) and .output == \"Hello.ex5\""
    wrapped "$WORK_ROOT/loose" Loose.mq5
    expect_status "a loose file through the wrapper" "$EXIT_OK"
    wrapped "$REPO_ROOT" does/not/exist.mq5
    expect_status "a path that does not exist, through the wrapper" "$EXIT_USAGE"
    expect_record "the wrapper reports a bad path as a JSON error record" '.type == "error" and .message == "no such file or folder: does/not/exist.mq5"'
    wrapped "$REPO_ROOT" --text does/not/exist.mq5
    if [[ -z "$OUT" ]]; then
        pass "with --text the wrapper keeps errors off stdout"
    else
        fail "with --text the wrapper keeps errors off stdout" "got: $OUT"
    fi
    wrapped /
    expect_status "no path from /" "$EXIT_USAGE"
    expect_record "the wrapper refuses to mount /" '.type == "error" and (.message | startswith("refusing to mount /"))'
    wrapped / --version
    expect_status "--version from / mounts nothing" "$EXIT_OK"
}

test_version() {
    log "--version"
    local version
    version="$(cat "$REPO_ROOT/VERSION")"
    compile --version
    expect_status "--version" "$EXIT_OK"
    expect_record "--version reports the image and both MetaEditor builds" \
        ".type == \"version\" and .version == \"$version\" and (.mt4_metaeditor | test(\"^[0-9]+(\\\\.[0-9]+)+$\")) and (.mt5_metaeditor | test(\"^[0-9]+(\\\\.[0-9]+)+$\"))"
    compile --version --text
    expect_output "--version --text prints the image version" "^mql-compiler $version$"
}

test_run_log() {
    log "the run log"
    local run_log
    run_log="$TEST_CACHE/uid-$(id -u)/logs/last-run.log"
    fresh_workdir
    compile MQL5/Scripts/Say.mq5
    expect_status "a short run" "$EXIT_OK"
    if grep -q 'run complete total=1' "$run_log" && grep -q '"source":"MQL5/Scripts/Say.mq5"' "$run_log"; then
        pass "the run log holds the results and the logs"
    else
        fail "the run log holds the results and the logs" "$run_log lacks them"
    fi
    compile does/not/exist.mq5
    expect_status "a path that does not exist" "$EXIT_USAGE"
    expect_record "a bad path is a JSON error record on stdout" '.type == "error" and (.message | startswith("no such file or folder"))'
    if grep -q 'no such file or folder' "$run_log"; then
        pass "the run log keeps the last line of a run that fails at once"
    else
        fail "the run log keeps the last line of a run that fails at once" "$run_log lacks the error"
    fi
}

test_parallel_runs() {
    log "two runs at once"
    fresh_workdir
    local first_out second_out first_status=0 second_status=0
    first_out="$(mktemp)"
    second_out="$(mktemp)"
    docker run --rm --user "$(id -u):$(id -g)" -v "$WORK_ROOT":/src -v "$TEST_CACHE":/cache \
        "$IMAGE" MQL5 >"$first_out" 2>&1 &
    local first_pid=$!
    docker run --rm --user "$(id -u):$(id -g)" -v "$WORK_ROOT":/src -v "$TEST_CACHE":/cache \
        "$IMAGE" MQL4 >"$second_out" 2>&1 || second_status=$?
    wait "$first_pid" || first_status=$?
    OUT="$(cat "$first_out" "$second_out")"
    ERR=""
    rm -f "$first_out" "$second_out"
    STATUS="$first_status"
    expect_status "the first of two parallel runs" "$EXIT_COMPILE_ERRORS"
    STATUS="$second_status"
    expect_status "the second of two parallel runs" "$EXIT_OK"
    expect_output "one parallel run waits for the other" 'waiting for it to finish'
    expect_output "both parallel runs finish" '"total":5,"compiled":5,"failed":0'
}

# Waits until the file holds at least $2 summary records.
wait_for_summaries() {
    local file="$1" want="$2" waited=0
    while (($(grep -c '"type":"summary"' "$file" || true) < want)); do
        ((waited < WATCH_TIMEOUT_SECONDS)) || return 1
        sleep "$WATCH_POLL_SECONDS"
        waited=$((waited + WATCH_POLL_SECONDS))
    done
}

test_watch() {
    log "--watch"
    fresh_workdir
    local name="mql-compiler-test-watch-$$" out_file
    out_file="$(mktemp)"
    docker run --rm --init --name "$name" --user "$(id -u):$(id -g)" \
        -v "$WORK_ROOT":/src -v "$TEST_CACHE":/cache \
        "$IMAGE" --watch MQL5/Scripts >"$out_file" 2>/dev/null &
    local client_pid=$!
    if wait_for_summaries "$out_file" 1; then
        pass "--watch compiles once at the start"
    else
        fail "--watch compiles once at the start" "no summary within ${WATCH_TIMEOUT_SECONDS}s"
    fi
    printf '%s\n' '// changed' >>"$WORK_ROOT/MQL5/Scripts/Say.mq5"
    if wait_for_summaries "$out_file" 2; then
        pass "--watch compiles again after a change"
    else
        fail "--watch compiles again after a change" "no second summary within ${WATCH_TIMEOUT_SECONDS}s"
    fi
    docker stop "$name" >/dev/null
    local stop_status=0
    wait "$client_pid" || stop_status=$?
    STATUS="$stop_status"
    OUT="$(cat "$out_file")"
    ERR=""
    rm -f "$out_file"
    expect_status "--watch stopped by docker stop" 130
}

test_update() {
    log "--update (reinstalls the toolchain, about a minute and a half)"
    compile --update
    expect_status "--update" "$EXIT_OK"
    expect_record "--update reports the new builds" '.type == "version" and .mt4_metaeditor != null and .mt5_metaeditor != null'
    expect_log "--update logs the reinstall" 'toolchain updated'
    fresh_workdir
    compile MQL5/Experts/StdLib.mq5 MQL4/Experts/StdLib.mq4
    expect_status "compiling after --update" "$EXIT_OK"
}

test_usage() {
    log "usage errors"
    fresh_workdir
    compile does/not/exist.mq5
    expect_status "a path that does not exist" "$EXIT_USAGE"
    compile MQL5/Include/Fixture/Greeting.mqh
    expect_status "a file that is not .mq4 or .mq5" "$EXIT_USAGE"
    compile --no-such-option
    expect_status "an unknown option" "$EXIT_USAGE"
    expect_record "an unknown option is a JSON error record" '.type == "error" and (.message | startswith("unknown option: --no-such-option"))'
    mkdir -p "$WORK_ROOT/empty"
    compile empty
    expect_status "a folder with no sources" "$EXIT_USAGE"
    compile --help
    expect_status "--help" "$EXIT_OK"
}

main() {
    mkdir -p "$TEST_CACHE"
    test_whole_tree
    test_output_formats
    test_warnings
    test_extra_includes
    test_selection
    test_include_errors
    test_reported_paths
    test_nested_platform_folders
    test_wrapper
    test_version
    test_run_log
    test_parallel_runs
    test_watch
    test_update
    test_usage
    rm -rf "$WORK_ROOT"
    printf '\n%d passed, %d failed\n' "$passed" "$failed"
    ((failed == 0))
}

main "$@"
