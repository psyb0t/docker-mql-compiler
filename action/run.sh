#!/bin/bash
# The work behind action.yml, in two steps:
#
#   run.sh prepare   pick the image and the toolchain cache folder
#   run.sh compile   run the mql-compiler command, annotate the results,
#                    write the job summary and the step outputs
#
# Reads the action's inputs from INPUT_* variables and GitHub's own
# GITHUB_* and RUNNER_* variables. The compile step exits with the command's
# status, so a failed compile fails the step.
set -euo pipefail
trap 'echo "::error::mql-compiler action failed at ${BASH_SOURCE[0]##*/}:${LINENO} (exit $?)" >&2' ERR

ACTION_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly ACTION_ROOT
readonly IMAGE_REPO="psyb0t/mql-compiler"
readonly LATEST_IMAGE="$IMAGE_REPO:latest"
readonly RESULTS_NAME="mql-compiler-results.jsonl"
readonly DEFAULT_CACHE_NAME="mql-compiler-cache"
readonly RELEASE_REF='^v[0-9]+\.[0-9]+\.[0-9]+$'

log() {
    printf '[mql-compiler] %s\n' "$*" >&2
}

# The release image matching the action's ref (uses: ...@v0.3.0 runs
# psyb0t/mql-compiler:v0.3.0), :latest for a branch, or the image input.
prepare() {
    local image="${INPUT_IMAGE:-}" cache_dir="${INPUT_CACHE_DIR:-}"
    if [[ -z "$image" ]]; then
        image="$LATEST_IMAGE"
        if [[ "${ACTION_REF:-}" =~ $RELEASE_REF ]]; then
            image="$IMAGE_REPO:$ACTION_REF"
        fi
    fi
    cache_dir="${cache_dir:-$RUNNER_TEMP/$DEFAULT_CACHE_NAME}"
    mkdir -p "$cache_dir"
    log "image=$image cache_dir=$cache_dir"
    {
        printf 'image=%s\n' "$image"
        printf 'cache-dir=%s\n' "$cache_dir"
        printf 'cache-key=%s\n' "mql-compiler-$RUNNER_OS-${image//[^A-Za-z0-9._-]/-}"
    } >>"$GITHUB_OUTPUT"
}

# One workflow command per compiler message, so GitHub marks the source
# line. Paths outside the repository (a standard header in the toolchain)
# get a message without a file.
annotate() {
    jq -r '
        def data: gsub("%"; "%25") | gsub("\r"; "%0D") | gsub("\n"; "%0A");
        def property: data | gsub(":"; "%3A") | gsub(","; "%2C");
        if .type == "error" then "::error title=mql-compiler::\(.message | data)"
        elif .type == "file" then
            .source as $source | .messages[]
            | ([(if (.file // $source) | startswith("/") then empty else "file=\((.file // $source) | property)" end),
                (if .line == null then empty else "line=\(.line)" end),
                (if .column == null then empty else "col=\(.column)" end),
                "title=\((if .code == null then "MetaEditor" else "MQL \(.severity) \(.code)" end) | property)"]
               | join(",")) as $props
            | "::\(.severity) \($props)::\(.text | data)"
        else empty end' "$1"
}

summarize() {
    local results="$1"
    {
        printf '### mql-compiler\n\n'
        printf '| Source | Platform | Status | Errors | Warnings |\n|---|---|---|---|---|\n'
        jq -r 'select(.type == "file")
            | "| `\(.source)` | \(.platform) | \(.status) | \(.errors // "-") | \(.warnings // "-") |"' "$results"
        jq -r 'select(.type == "summary")
            | "\n\(.compiled) of \(.total) compiled, \(.failed) failed."' "$results"
        jq -r 'select(.type == "error") | "\n**Error:** \(.message)"' "$results"
    } >>"$GITHUB_STEP_SUMMARY"
}

compile() {
    local args=() line status=0 results="$RUNNER_TEMP/$RESULTS_NAME"
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        args+=(-I "$line")
    done <<<"${INPUT_INCLUDE:-}"
    if [[ "${INPUT_WERROR:-false}" == "true" ]]; then
        args+=(--werror)
    fi
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        args+=("$line")
    done <<<"${INPUT_PATHS:-.}"

    log "compiling: ${args[*]}"
    MQL_COMPILER_IMAGE="${ACTION_IMAGE:?}" MQL_COMPILER_VOLUME="${ACTION_CACHE_DIR:?}" \
        bash "$ACTION_ROOT/wrapper.sh" "${args[@]}" >"$results" || status=$?
    cat "$results"
    annotate "$results"
    summarize "$results"
    {
        printf 'results=%s\n' "$results"
        jq -r 'select(.type == "summary") | "total=\(.total)\ncompiled=\(.compiled)\nfailed=\(.failed)"' "$results"
    } >>"$GITHUB_OUTPUT"
    return "$status"
}

case "${1:-}" in
    prepare) prepare ;;
    compile) compile ;;
    *)
        log "usage: run.sh prepare|compile"
        exit 2
        ;;
esac
