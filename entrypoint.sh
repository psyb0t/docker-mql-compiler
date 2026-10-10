#!/bin/bash
# mql-compiler: compile MQL4 (.mq4) and MQL5 (.mq5) sources with MetaEditor
# under Wine.
#
#   mql-compiler [--setup] [--help] [FILE or FOLDER ...]
#
# Every argument is a file to compile or a folder to search (recursively) for
# .mq4 and .mq5 files; no argument means the current folder. Relative paths
# start from the current folder. Each file goes to the compiler for its
# extension (.mq4 to MT4's MetaEditor, .mq5 to MT5's), one after another in
# path order, and its .ex4/.ex5 lands next to it.
#
# Includes: MetaEditor reads `#include <...>` from exactly one folder,
# <root>/Include. For each compile the root is a merged folder: the
# terminal's standard library (Trade/Trade.mqh, stdlib.mqh, ...) with the
# Include folder of the nearest enclosing MQL4/MQL5 folder laid over it, so
# both are found and a file of yours replaces the standard one of the same
# name. The merged root also links that folder's other subfolders, so
# #resource paths such as "\\Indicators\\X.ex5" resolve. A source outside any
# MQL4/MQL5 folder gets the standard library alone. `#include "..."` resolves
# next to the source as usual.
#
# The MetaQuotes toolchain is not in the image. The first run downloads the
# RoboForex MT4 and MT5 installers (or MQL_COMPILER_MT4_URL / _MT5_URL),
# checks their MetaQuotes code signature, installs them, and starts each
# terminal once so it unpacks its standard library. All of it lands in
# /cache/uid-<UID>; keep /cache on a volume and later runs skip straight to
# compiling.
#
# Exit status: 0 every file compiled, 1 at least one has compile errors,
# 2 bad usage or a toolchain that could not be set up.
#
# Compile results go to stdout; JSON log lines go to stderr. Both are also
# written to /cache/uid-<UID>/logs/last-run.log.
set -euo pipefail
trap 'printf "{\"level\":\"ERROR\",\"file\":\"%s\",\"line\":%d,\"msg\":\"command failed exit=%d\"}\n" "${BASH_SOURCE[0]##*/}" "$LINENO" "$?" >&2' ERR

CALLER_UID="$(id -u)"
readonly CALLER_UID
# Each UID gets its own toolchain folder, so one shared volume serves every
# user and Wine always finds a prefix it owns.
readonly CACHE_ROOT="/cache/uid-$CALLER_UID"
readonly INSTALLER_DIR="$CACHE_ROOT/installers"
readonly LOG_DIR="$CACHE_ROOT/logs"
readonly LOG_FILE="$LOG_DIR/last-run.log"
readonly LOCK_FILE="$CACHE_ROOT/.setup.lock"
export HOME="$CACHE_ROOT/home"
export WINEPREFIX="$CACHE_ROOT/wine"
readonly DRIVE_C="$WINEPREFIX/drive_c"
readonly MT4_INSTALLER_URL="${MQL_COMPILER_MT4_URL:-https://download.mql5.com/cdn/web/22607/mt4/roboforexltd4setup.exe}"
readonly MT5_INSTALLER_URL="${MQL_COMPILER_MT5_URL:-https://download.mql5.com/cdn/web/22607/mt5/roboforexltd5setup.exe}"
readonly MT4_METAEDITOR="metaeditor.exe"
readonly MT5_METAEDITOR="metaeditor64.exe"
readonly MT4_TERMINAL="terminal.exe"
readonly MT5_TERMINAL="terminal64.exe"
readonly MT4_FOLDER="MQL4"
readonly MT5_FOLDER="MQL5"
# A header each terminal unpacks into its standard library on first start.
readonly MT4_STDLIB_MARKER="Include/stdlib.mqh"
readonly MT5_STDLIB_MARKER="Include/Trade/Trade.mqh"
readonly INCLUDE_FOLDER="include"
readonly STDLIB_UNPACK_TIMEOUT_SECONDS=120
readonly POLL_SECONDS=2
readonly SIGNER_PATTERN="MetaQuotes"
readonly SIGNATURE_ATTEMPTS=3
# osslsigncode's words when it could not get a CRL (its own typo included).
readonly CRL_FETCH_FAILURE="Fai(le)?d to (decode|download|get|fetch) CRL"
readonly CA_BUNDLE="/etc/ssl/certs/ca-certificates.crt"
readonly XVFB_DISPLAY="${DISPLAY:-:99}"
readonly DOWNLOAD_RETRIES=3
readonly DOWNLOAD_RETRY_DELAY_SECONDS=5
readonly EXIT_OK=0
readonly EXIT_COMPILE_ERRORS=1
readonly EXIT_USAGE=2

log() {
    local level="$1"
    shift
    jq -nc \
        --arg time "$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)" \
        --arg level "$level" \
        --arg file "${BASH_SOURCE[1]##*/}" \
        --argjson line "${BASH_LINENO[0]}" \
        --arg func "${FUNCNAME[1]:-main}" \
        --arg msg "$*" \
        '{time: $time, level: $level, file: $file, line: $line, func: $func, msg: $msg}' >&2
}

die() {
    log ERROR "$*"
    exit "$EXIT_USAGE"
}

usage() {
    cat <<'EOF'
Usage: mql-compiler [FILE or FOLDER ...]

  (no arguments)  compile every .mq4 and .mq5 under the current folder
  a file          compile that file (expert, indicator, script or library)
  a folder        compile every .mq4 and .mq5 inside it, recursively

Paths may be relative or absolute. .mq4 files go to MT4's MetaEditor and
.mq5 files to MT5's, one after another in path order. Each .ex4/.ex5 lands
next to its source.

#include <...> finds both the MetaQuotes standard library and the Include
folder of the nearest MQL4/ or MQL5/ folder above the source; a file of yours
replaces the standard one with the same name. #resource "\\Files\\..." starts
at that MQL4/MQL5 folder. #include "..." resolves next to the source. A
source outside any MQL4/MQL5 folder gets the standard library only.

  --setup   only download and install the MetaQuotes toolchain and unpack
            its standard library
  --help    show this help

Exit status: 0 all compiled, 1 compile errors, 2 usage or setup failure.
EOF
}

# ---------------------------------------------------------------- display ---

XVFB_PID=""
STAGING_DIR=""

start_display() {
    # Xvfb's own chatter is noise in a compile log; failures surface when
    # MetaEditor cannot start.
    Xvfb "$XVFB_DISPLAY" -screen 0 1024x768x24 -nolisten tcp >/dev/null 2>&1 &
    XVFB_PID=$!
}

# One persistent wineserver for the compile loop, so each MetaEditor call
# skips Wine's start-up. Needs the prefix, so it starts after setup.
keep_wineserver() {
    wineserver -p >/dev/null 2>&1
}

cleanup() {
    # Best effort on the way out: a wineserver or Xvfb that is already gone
    # must not turn a finished run into a failure.
    wineserver -k >/dev/null 2>&1 || true
    if [[ -n "$XVFB_PID" ]]; then
        kill "$XVFB_PID" >/dev/null 2>&1 || true
    fi
    if [[ -n "$STAGING_DIR" ]]; then
        rm -rf "$STAGING_DIR"
    fi
}

# -------------------------------------------------------------- toolchain ---

metaeditor_name() {
    case "$1" in
        mt4) printf '%s\n' "$MT4_METAEDITOR" ;;
        mt5) printf '%s\n' "$MT5_METAEDITOR" ;;
    esac
}

terminal_name() {
    case "$1" in
        mt4) printf '%s\n' "$MT4_TERMINAL" ;;
        mt5) printf '%s\n' "$MT5_TERMINAL" ;;
    esac
}

mql_folder() {
    case "$1" in
        mt4) printf '%s\n' "$MT4_FOLDER" ;;
        mt5) printf '%s\n' "$MT5_FOLDER" ;;
    esac
}

stdlib_marker() {
    case "$1" in
        mt4) printf '%s\n' "$MT4_STDLIB_MARKER" ;;
        mt5) printf '%s\n' "$MT5_STDLIB_MARKER" ;;
    esac
}

find_metaeditor() {
    [[ -d "$DRIVE_C" ]] || return 0
    # Unreadable corners of a Wine prefix are irrelevant to the search.
    find "$DRIVE_C" -path "$DRIVE_C/windows" -prune -o -iname "$(metaeditor_name "$1")" -print -quit 2>/dev/null
}

# The terminal's own MQL4/MQL5 folder, which holds its standard library.
stdlib_root() {
    local editor
    editor="$(find_metaeditor "$1")"
    printf '%s/%s\n' "$(dirname "$editor")" "$(mql_folder "$1")"
}

# The full check, revocation lists included. Prints osslsigncode's report.
signature_report() {
    osslsigncode verify -CAfile "$CA_BUNDLE" "$@" 2>&1
}

verify_installer() {
    local file="$1" name report attempt
    name="$(basename "$file")"
    for ((attempt = 1; attempt <= SIGNATURE_ATTEMPTS; attempt++)); do
        if report="$(signature_report -in "$file")"; then
            require_signer "$name" "$report"
            return
        fi
        # A revocation list the CA's server failed to deliver is worth another
        # try; anything else (a bad digest, an untrusted chain, a revoked
        # certificate) fails at once.
        grep -qE "$CRL_FETCH_FAILURE" <<<"$report" || break
        log WARN "revocation list fetch failed, retrying file=$name attempt=$attempt"
        sleep "$DOWNLOAD_RETRY_DELAY_SECONDS"
    done
    if ! grep -qE "$CRL_FETCH_FAILURE" <<<"$report"; then
        log ERROR "installer signature check failed file=$name report=$report"
        return 1
    fi
    # The CA's revocation server stayed unreachable. The signature, digest and
    # chain still have to verify; only the online revocation lookup is dropped.
    if ! report="$(signature_report -ignore-crl -in "$file")"; then
        log ERROR "installer signature check failed file=$name report=$report"
        return 1
    fi
    log WARN "installer verified without the revocation check file=$name reason=crl_unreachable"
    require_signer "$name" "$report"
}

require_signer() {
    local name="$1" report="$2"
    if ! grep -qi "Subject:.*$SIGNER_PATTERN" <<<"$report"; then
        log ERROR "installer is validly signed but not by $SIGNER_PATTERN file=$name"
        return 1
    fi
    log INFO "installer signature ok signer=$SIGNER_PATTERN file=$name"
}

install_platform() {
    local platform="$1" url="$2"
    local installer="$INSTALLER_DIR/$platform-setup.exe"
    log INFO "downloading installer platform=$platform url=$url"
    if ! curl -fsSL --retry "$DOWNLOAD_RETRIES" --retry-delay "$DOWNLOAD_RETRY_DELAY_SECONDS" -o "$installer.part" "$url"; then
        log ERROR "installer download failed platform=$platform url=$url"
        return 1
    fi
    mv "$installer.part" "$installer"
    verify_installer "$installer" || return 1
    log INFO "installing platform=$platform (silent web install, about a minute)"
    # The setup launcher hands off to a child and its exit code says nothing;
    # the MetaEditor check below is the verdict.
    wine "$installer" /auto >/dev/null 2>&1 || true
    wineserver -w
    if [[ -z "$(find_metaeditor "$platform")" ]]; then
        log ERROR "install finished without a MetaEditor platform=$platform"
        return 1
    fi
    log INFO "platform ready platform=$platform"
}

# The installer leaves the standard library packed inside the terminal; the
# terminal unpacks it into its MQL4/MQL5 folder the first time it starts.
# Start it once in portable mode, wait for the headers, then stop it.
unpack_stdlib() {
    local platform="$1" root marker terminal_dir waited=0
    root="$(stdlib_root "$platform")"
    marker="$root/$(stdlib_marker "$platform")"
    [[ -f "$marker" ]] && return 0
    terminal_dir="$(dirname "$root")"
    log INFO "unpacking the standard library platform=$platform (starts the terminal once)"
    # The terminal never exits on its own; it is stopped below once the
    # headers are there, and its output is a GUI log nobody reads.
    (cd "$terminal_dir" && wine "$(terminal_name "$platform")" /portable >/dev/null 2>&1 &)
    while [[ ! -f "$marker" ]] && ((waited < STDLIB_UNPACK_TIMEOUT_SECONDS)); do
        sleep "$POLL_SECONDS"
        waited=$((waited + POLL_SECONDS))
    done
    # Give the terminal a moment to finish writing the rest of the tree.
    sleep "$POLL_SECONDS"
    wineserver -k >/dev/null 2>&1 || true # stops the terminal; nothing else runs in this prefix yet
    if [[ ! -f "$marker" ]]; then
        log ERROR "the terminal did not unpack its standard library platform=$platform waited=${waited}s"
        return 1
    fi
    log INFO "standard library ready platform=$platform path=$root"
}

ensure_toolchain() {
    mkdir -p "$HOME" "$INSTALLER_DIR"
    if [[ -e "$WINEPREFIX" && ! -O "$WINEPREFIX" ]]; then
        die "$WINEPREFIX belongs to UID $(stat -c %u "$WINEPREFIX"), not $CALLER_UID: the cache was written by another UID"
    fi
    # One setup at a time: parallel first runs share the same cache.
    exec 9>"$LOCK_FILE"
    flock 9
    if [[ ! -f "$WINEPREFIX/system.reg" ]]; then
        log INFO "creating the Wine prefix path=$WINEPREFIX"
        # wineboot prints first-run noise about missing Mono/Gecko, which a
        # compiler does not need.
        wineboot --init >/dev/null 2>&1
        wineserver -w
    fi
    [[ -n "$(find_metaeditor mt5)" ]] || install_platform mt5 "$MT5_INSTALLER_URL" || die "MT5 setup failed"
    [[ -n "$(find_metaeditor mt4)" ]] || install_platform mt4 "$MT4_INSTALLER_URL" || die "MT4 setup failed"
    unpack_stdlib mt5 || die "MT5 standard library setup failed"
    unpack_stdlib mt4 || die "MT4 standard library setup failed"
    flock -u 9
}

# ---------------------------------------------------------------- include ---

# The nearest enclosing folder named MQL4 or MQL5 (matched case-insensitively,
# as Windows would), or nothing.
user_mql_root() {
    local dir wanted="$2"
    dir="$(dirname "$1")"
    while [[ "$dir" != "/" ]]; do
        if [[ "$(basename "$dir" | tr '[:lower:]' '[:upper:]')" == "$wanted" ]]; then
            printf '%s\n' "$dir"
            return 0
        fi
        dir="$(dirname "$dir")"
    done
}

# The /inc root for one compile, left in MERGED_ROOT. MetaEditor reads <...>
# includes from exactly one <root>/Include, so this builds a folder holding
# both: links to the terminal's standard Include with links to the user's
# Include laid over them (the user's file wins on a clash), plus links to the
# user's other subfolders for #resource paths. It lives in the staging folder
# because MetaEditor's /inc cannot take a path with spaces, and the terminal
# sits under "Program Files". Built once per platform and user folder per run.
declare -A MERGED_ROOTS=()
MERGED_ROOT=""

build_merged_root() {
    local platform="$1" user_root="$2" key entry name
    key="$platform:$user_root"
    if [[ -n "${MERGED_ROOTS[$key]:-}" ]]; then
        MERGED_ROOT="${MERGED_ROOTS[$key]}"
        return
    fi
    MERGED_ROOT="$STAGING_DIR/${#MERGED_ROOTS[@]}/$(mql_folder "$platform")"
    mkdir -p "$MERGED_ROOT"
    cp -rs "$(stdlib_root "$platform")/Include" "$MERGED_ROOT/Include"
    MERGED_ROOTS[$key]="$MERGED_ROOT"
    [[ -n "$user_root" ]] || return 0
    for entry in "$user_root"/*; do
        [[ -e "$entry" ]] || continue
        name="$(basename "$entry")"
        if [[ "${name,,}" == "$INCLUDE_FOLDER" && -d "$entry" ]]; then
            cp -rs --remove-destination "$entry/." "$MERGED_ROOT/Include/"
            continue
        fi
        ln -s "$entry" "$MERGED_ROOT/$name"
    done
}

# ---------------------------------------------------------------- compile ---

# A path as the user should read it: relative to the current folder when it
# is inside it, absolute otherwise.
shown() {
    if [[ "$1" == "$PWD/"* ]]; then
        printf '%s\n' "${1#"$PWD"/}"
        return
    fi
    printf '%s\n' "$1"
}

sed_escape() {
    printf '%s' "$1" | sed 's/[][\.*^$|/]/\\&/g'
}

# MetaEditor writes its log as UTF-16 with Windows paths. This prints plain
# UTF-8 lines with those paths turned back into real ones: Z:\ is /, the
# merged include root reads as $3 (the user's MQL4/MQL5 folder, or the
# terminal's for a loose file), and the current folder is dropped from the
# front.
read_log() {
    local log_file="$1" merged="$2" shown_root="$3"
    iconv -f UTF-16 -t UTF-8 "$log_file" | tr -d '\r' | sed \
        -e 's|\\|/|g' \
        -e 's|[Zz]:/|/|g' \
        -e "s|$(sed_escape "$merged")|$(sed_escape "$shown_root")|g" \
        -e "s|$(sed_escape "$PWD/")||g"
}

compile_one() {
    local source="$1" platform user_root shown_root output editor log_file result errors warnings
    case "${source,,}" in
        *.mq4) platform=mt4 output="${source%.*}.ex4" ;;
        *.mq5) platform=mt5 output="${source%.*}.ex5" ;;
    esac
    user_root="$(user_mql_root "$source" "$(mql_folder "$platform")")"
    build_merged_root "$platform" "$user_root"
    shown_root="${user_root:-$(stdlib_root "$platform")}"
    editor="$(find_metaeditor "$platform")"
    log_file="$(mktemp --suffix=.log)"

    # MetaEditor's exit code is backwards (1 usually means success); the log's
    # Result line is the verdict, and its stderr is Wine noise.
    wine "$editor" \
        "/compile:$(winepath -w "$source")" \
        "/log:$(winepath -w "$log_file")" \
        "/inc:$(winepath -w "$MERGED_ROOT")" >/dev/null 2>&1 || true

    result="$(read_log "$log_file" "$MERGED_ROOT" "$shown_root" | grep -E '^Result: ' | tail -n 1)" || result=""
    if [[ -z "$result" ]]; then
        printf 'FAIL %s: MetaEditor wrote no result\n' "$(shown "$source")"
        read_log "$log_file" "$MERGED_ROOT" "$shown_root" | sed 's/^/     /'
        rm -f "$log_file"
        return 1
    fi
    errors="$(sed -nE 's/^Result: ([0-9]+) error.*/\1/p' <<<"$result")"
    warnings="$(sed -nE 's/.* ([0-9]+) warning.*/\1/p' <<<"$result")"

    if [[ "$errors" == "0" ]]; then
        printf 'OK   %s -> %s (%s warnings)\n' "$(shown "$source")" "$(shown "$output")" "${warnings:-0}"
    else
        printf 'FAIL %s (%s errors, %s warnings)\n' "$(shown "$source")" "$errors" "${warnings:-0}"
    fi
    # A clean file has no error or warning lines, which grep reports as 1.
    read_log "$log_file" "$MERGED_ROOT" "$shown_root" | grep -E ' : (error|warning) ' | sed 's/^/     /' || true
    rm -f "$log_file"
    [[ "$errors" == "0" ]]
}

collect_sources() {
    local target
    for target in "$@"; do
        [[ "$target" == /* ]] || target="$PWD/$target"
        target="$(realpath -ms "$target")"
        if [[ -d "$target" ]]; then
            find "$target" -type f \( -iname '*.mq4' -o -iname '*.mq5' \) -print | sort
            continue
        fi
        [[ -f "$target" ]] || die "no such file or folder: $(shown "$target")"
        case "${target,,}" in
            *.mq4 | *.mq5) printf '%s\n' "$target" ;;
            *) die "not an .mq4 or .mq5 file: $(shown "$target")" ;;
        esac
    done
}

# ------------------------------------------------------------------- main ---

main() {
    local setup_only=false targets=()
    while (($#)); do
        case "$1" in
            -h | --help)
                usage
                exit "$EXIT_OK"
                ;;
            --setup) setup_only=true ;;
            -*) die "unknown option: $1 (see --help)" ;;
            *) targets+=("$1") ;;
        esac
        shift
    done
    ((${#targets[@]})) || targets=(".")

    mkdir -p "$LOG_DIR"
    exec > >(tee "$LOG_FILE") 2> >(tee -a "$LOG_FILE" >&2)

    local sources=() listing
    if [[ "$setup_only" == false ]]; then
        # A command substitution, not <(...), so a bad path ends the run here.
        # A file named twice (directly and through its folder) compiles once.
        listing="$(collect_sources "${targets[@]}" | awk '!seen[$0]++')"
        [[ -n "$listing" ]] || die "no .mq4 or .mq5 files found in: ${targets[*]}"
        mapfile -t sources <<<"$listing"
    fi

    STAGING_DIR="$(mktemp -d /tmp/mql-compiler.XXXXXX)"
    start_display
    trap cleanup EXIT
    ensure_toolchain
    if [[ "$setup_only" == true ]]; then
        log INFO "toolchain ready path=$CACHE_ROOT"
        exit "$EXIT_OK"
    fi

    keep_wineserver
    local source failed=0
    for source in "${sources[@]}"; do
        compile_one "$source" || failed=$((failed + 1))
    done
    log INFO "run complete total=${#sources[@]} compiled=$((${#sources[@]} - failed)) failed=$failed"
    ((failed == 0)) || exit "$EXIT_COMPILE_ERRORS"
}

main "$@"
