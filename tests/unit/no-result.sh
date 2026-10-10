#!/bin/bash
# compile_one when MetaEditor writes no result at all (it crashed or never
# ran): the file fails, its stale output is removed, and every format says so.
# Needs the installed toolchain in /cache; wine itself is stubbed out.

# STAGING_DIR and OUTPUT_FORMAT are read by the sourced entrypoint's functions.
# shellcheck disable=SC2034
set -uo pipefail

# shellcheck source=tests/unit/lib.sh
source /unit/lib.sh
load_entrypoint

wine() {
    # MetaEditor "runs" and writes nothing.
    :
}

readonly SOURCE_DIR="/tmp/src"
readonly SOURCE="$SOURCE_DIR/MQL5/Scripts/Empty.mq5"
readonly OUTPUT="$SOURCE_DIR/MQL5/Scripts/Empty.ex5"

mkdir -p "$(dirname "$SOURCE")"
printf '%s\n' 'void OnStart() {}' >"$SOURCE"
cd "$SOURCE_DIR" || exit 1

# compile_one runs in a $(...) subshell here, so its include-root cache never
# survives the call; each call gets its own staging folder instead.
compile_without_result() {
    STAGING_DIR="$(mktemp -d)"
    printf 'stale\n' >"$OUTPUT"
    compile_one "$SOURCE"
}

record="$(compile_without_result)"
status=$?
expect_equal "a file with no result counts as failed" "$status" 1
expect_equal "the record says MetaEditor wrote no result" \
    "$(jq -c '[.status, .errors, .warnings, .output, .messages[0].text, (.log | type)]' <<<"$record")" \
    '["failed",null,null,null,"MetaEditor wrote no result","array"]'
if [[ -e "$OUTPUT" ]]; then
    fail "the stale output is removed" "$OUTPUT still exists"
else
    pass "the stale output is removed"
fi

OUTPUT_FORMAT="$FORMAT_TEXT"
text="$(compile_without_result)"
expect_match "--text says MetaEditor wrote no result" "$text" '^FAIL MQL5/Scripts/Empty\.mq5: MetaEditor wrote no result$'

OUTPUT_FORMAT="$FORMAT_GNU"
gnu="$(compile_without_result)"
expect_match "--format gnu points at the file" "$gnu" '^MQL5/Scripts/Empty\.mq5:0:0: error: MetaEditor wrote no result$'
