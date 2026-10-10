#!/bin/bash
# mql-compiler: compile MQL4 (.mq4) and MQL5 (.mq5) sources with MetaEditor
# under Wine.
#
#   mql-compiler [OPTIONS] [FILE or FOLDER ...]
#
# Every argument is a file to compile or a folder to search (recursively) for
# .mq4 and .mq5 files; no argument means the current folder. Relative paths
# start from the current folder. Arguments keep their order, each folder's
# files are sorted, and a file named twice compiles once. Each file goes to
# the compiler for its extension (.mq4 to MT4's MetaEditor, .mq5 to MT5's),
# one at a time, and its .ex4/.ex5 lands next to it.
#
# Includes: MetaEditor reads `#include <...>` from exactly one folder,
# <root>/Include. For each compile the root is a merged folder: the
# terminal's standard library (Trade/Trade.mqh, stdlib.mqh, ...), then every
# -I folder, then the Include folder of the nearest enclosing MQL4/MQL5
# folder, each laid over the one before, so all are found and the later one
# wins on a clash. The merged root also links that MQL4/MQL5 folder's other
# subfolders, so #resource paths such as "\\Indicators\\X.ex5" resolve. A
# source outside any MQL4/MQL5 folder gets the standard library and the -I
# folders. `#include "..."` resolves next to the source as usual.
#
# The MetaQuotes toolchain is not in the image. The first run downloads the
# RoboForex MT4 and MT5 installers (or MQL_COMPILER_MT4_URL / _MT5_URL),
# checks their MetaQuotes code signature, installs them, and starts each
# terminal once so it unpacks its standard library. All of it lands in
# /cache/uid-<UID>; keep /cache on a volume and later runs skip straight to
# compiling. A compile installs only the platforms its sources need, and
# --mt4-terminal / --mt5-terminal hand a platform a portable terminal folder
# instead (its MetaEditor and standard library), which is then never
# downloaded.
#
# Output: by default one JSON object per line on stdout (a "file" record per
# source, then a "summary"; an "error" record for a usage or setup failure).
# --text prints the human OK/FAIL lines instead, --format gnu prints
# path:line:column: messages for editors. JSON log lines go to stderr. Both
# streams are also written to /cache/uid-<UID>/logs/last-run.log.
#
# Exit status: 0 every file compiled, 1 at least one failed (compile errors,
# or warnings with --werror), 2 bad usage or a toolchain that could not be
# set up.
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
# Held for a whole run: two runs share one Wine prefix and one log file, so a
# second run waits for the first instead of tripping over it.
readonly RUN_LOCK_FILE="$CACHE_ROOT/.run.lock"
export HOME="$CACHE_ROOT/home"
export WINEPREFIX="$CACHE_ROOT/wine"
readonly DRIVE_C="$WINEPREFIX/drive_c"
# Where setup moves each installed terminal, as a portable folder per platform
# (terminals/mt4, terminals/mt5). Inside the prefix, so --update's rollback
# moves it along, and free of spaces, unlike "Program Files".
readonly CACHED_TERMINALS_DIR="$DRIVE_C/terminals"
# --update moves the old prefix here and puts it back if the reinstall fails.
readonly PREVIOUS_WINEPREFIX="$CACHE_ROOT/wine.previous"
readonly IMAGE_VERSION_FILE="/usr/local/share/mql-compiler-version"
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
# The signing certificate's common name must start with this. Only the signer
# counts, not the chain or timestamp certificates in the same report.
readonly SIGNER_PATTERN="MetaQuotes"
readonly SIGNATURE_ATTEMPTS=3
# osslsigncode's words when it could not get a CRL (its own typo included).
readonly CRL_FETCH_FAILURE="Fai(le)?d to (decode|download|get|fetch) CRL"
readonly CA_BUNDLE="/etc/ssl/certs/ca-certificates.crt"
readonly XVFB_DISPLAY="${DISPLAY:-:99}"
readonly DOWNLOAD_RETRIES=3
readonly DOWNLOAD_RETRY_DELAY_SECONDS=5
# The source files whose changes start another pass in --watch mode.
readonly WATCHED_FILES='\.(mq4|mq5|mqh)$'
readonly FORMAT_JSON="json"
readonly FORMAT_TEXT="text"
readonly FORMAT_GNU="gnu"
readonly STATUS_OK="ok"
readonly STATUS_FAILED="failed"
readonly NO_RESULT="MetaEditor wrote no result"
readonly EXIT_OK=0
readonly EXIT_COMPILE_ERRORS=1
readonly EXIT_USAGE=2
# The exit status of a run stopped by SIGINT or SIGTERM, as a shell reports it.
readonly EXIT_INTERRUPTED=130

# fd 7 is the real stdout (through the log tee once logging starts). die
# writes its error record there, so it reaches the caller even from inside a
# command substitution.
exec 7>&1

OUTPUT_FORMAT="$FORMAT_JSON"
WERROR=false
EXTRA_INCLUDES=()
# Portable terminal folders from --mt4-terminal / --mt5-terminal. A platform
# with one compiles with that folder's MetaEditor and standard library and is
# never downloaded or installed into the cache.
TERMINAL_MT4=""
TERMINAL_MT5=""

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
    if [[ "$OUTPUT_FORMAT" == "$FORMAT_JSON" ]]; then
        jq -nc --arg message "$*" '{type: "error", message: $message}' >&7
    fi
    exit "$EXIT_USAGE"
}

usage() {
    cat <<'EOF'
Usage: mql-compiler [OPTIONS] [FILE or FOLDER ...]

  (no arguments)  compile every .mq4 and .mq5 under the current folder
  a file          compile that file (expert, indicator, script or library)
  a folder        compile every .mq4 and .mq5 inside it, recursively

Options:
  -I, --include DIR  lay DIR over the standard Include folder, so
                     #include <X/y.mqh> also finds DIR/X/y.mqh (repeatable)
  --mt4-terminal DIR compile .mq4 files with the MetaEditor and standard
                     library of the portable MT4 terminal in DIR, instead
                     of the cached install (which is then never installed)
  --mt5-terminal DIR the same for .mq5 files and a portable MT5 terminal
  --werror           count a file with warnings as failed
  --watch            compile, then compile again whenever a .mq4, .mq5 or
                     .mqh under the given paths changes, until stopped
  --text             print OK/FAIL lines for people instead of JSON
  --format FORMAT    json (the default), text, or gnu (path:line:column:
                     lines that editors parse)
  --setup            only install the MetaQuotes toolchain and unpack its
                     standard library
  --update           reinstall the toolchain with the newest MT4 and MT5
                     builds (keeps the old one if the reinstall fails)
  --version          print the image version and the MetaEditor builds
  -h, --help         show this help

Paths may be relative or absolute. Arguments are taken in the order given,
each folder's files sorted by path, a file named twice only once. Files
compile one at a time, never in parallel, and a failure does not stop the
run. A second run started meanwhile waits for this one.

The extension picks the compiler: .mq4 goes to MT4's MetaEditor, .mq5 to
MT5's. Each .ex4/.ex5 lands next to its source; the old one is deleted
before the file compiles, so an output after the run is from this run.

#include <...> finds the MetaQuotes standard library, the -I folders, and
the Include folder of the nearest folder above the source named MQL4 (for
a .mq4) or MQL5 (for a .mq5), each overriding the one before. #resource
"\\Files\\..." starts at that MQL4/MQL5 folder. #include "..." resolves next
to the source. A source outside any MQL4/MQL5 folder gets the standard
library and the -I folders only.

stdout carries the results: by default one JSON object per line, a "file"
record per source and a "summary" at the end, or an "error" record when the
run cannot start. stderr carries JSON log lines. Both also go to
/cache/uid-<UID>/logs/last-run.log in the cache volume.

Exit status: 0 all compiled, 1 at least one failed, 2 bad path or option,
nothing to compile, or setup failure.
EOF
}

# ---------------------------------------------------------------- display ---

XVFB_PID=""
STAGING_DIR=""
TEE_STDOUT_PID=""
TEE_STDERR_PID=""
WATCHER_PID=""

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
    # Best effort on the way out: a watcher, wineserver or Xvfb that is
    # already gone must not turn a finished run into a failure.
    if [[ -n "$WATCHER_PID" ]]; then
        kill "$WATCHER_PID" >/dev/null 2>&1 || true
    fi
    wineserver -k >/dev/null 2>&1 || true
    if [[ -n "$XVFB_PID" ]]; then
        kill "$XVFB_PID" >/dev/null 2>&1 || true
    fi
    if [[ -n "$STAGING_DIR" ]]; then
        rm -rf "$STAGING_DIR"
    fi
}

# The EXIT trap once output is going to the log. Docker kills every process
# in the container when this script ends, so the tee processes would lose
# whatever they had not written yet: close their input and wait for them.
finish() {
    cleanup
    exec >&- 2>&- 7>&-
    # Nothing is left to report a failure to; the exit status is the script's.
    wait "$TEE_STDOUT_PID" "$TEE_STDERR_PID" || true
}

# Two runs share one Wine prefix and one log file, so they take turns. The
# lock lives on fd 8 until the container exits; --watch lets go of it while
# it waits for changes.
acquire_run_lock() {
    exec 8>"$RUN_LOCK_FILE"
    if flock -n 8; then
        return
    fi
    log INFO "another mql-compiler run is using this cache, waiting for it to finish"
    flock 8
}

start_logging() {
    exec > >(tee "$LOG_FILE")
    TEE_STDOUT_PID=$!
    exec 2> >(tee -a "$LOG_FILE" >&2)
    TEE_STDERR_PID=$!
    exec 7>&1
    trap finish EXIT
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

# The --mtN-terminal folder for a platform, or nothing.
mounted_terminal() {
    case "$1" in
        mt4) printf '%s\n' "$TERMINAL_MT4" ;;
        mt5) printf '%s\n' "$TERMINAL_MT5" ;;
    esac
}

# The portable terminal folder a platform compiles with: the mounted one when
# given, else the cached one (which may not exist yet).
terminal_dir() {
    local mounted
    mounted="$(mounted_terminal "$1")"
    if [[ -n "$mounted" ]]; then
        printf '%s\n' "$mounted"
        return
    fi
    printf '%s/%s\n' "$CACHED_TERMINALS_DIR" "$1"
}

# The platform's MetaEditor in its terminal folder, or nothing.
find_metaeditor() {
    local terminal
    terminal="$(terminal_dir "$1")"
    [[ -d "$terminal" ]] || return 0
    find "$terminal" -maxdepth 1 -type f -iname "$(metaeditor_name "$1")" -print -quit
}

# A MetaEditor the installer put somewhere in the prefix (under Program
# Files), outside the cached terminals folder, or nothing. Only a fresh
# install or a cache from before v0.5.0 has one.
find_installed_metaeditor() {
    [[ -d "$DRIVE_C" ]] || return 0
    # Unreadable corners of a Wine prefix are irrelevant to the search.
    find "$DRIVE_C" \( -path "$DRIVE_C/windows" -o -path "$CACHED_TERMINALS_DIR" \) -prune \
        -o -type f -iname "$(metaeditor_name "$1")" -print -quit 2>/dev/null
}

# The terminal's own MQL4/MQL5 folder, which holds its standard library. A
# mounted terminal may spell it mql5 or Mql4; Windows does not care.
stdlib_root() {
    local terminal found
    terminal="$(terminal_dir "$1")"
    # A cached terminal not installed yet has no folder to search; the
    # default path below is then the answer.
    found="$(find "$terminal" -maxdepth 1 -type d -iname "$(mql_folder "$1")" -print -quit 2>/dev/null)" || true
    printf '%s\n' "${found:-$terminal/$(mql_folder "$1")}"
}

# A MetaEditor's FileVersion (such as 5.0.0.6249), read from the UTF-16
# version resource in the executable; nothing when it is not installed.
metaeditor_build() {
    local editor
    editor="$(find_metaeditor "$1")"
    [[ -n "$editor" ]] || return 0
    # grep finds nothing in a damaged executable; the build is then unknown.
    LC_ALL=C grep -aoP 'F\x00i\x00l\x00e\x00V\x00e\x00r\x00s\x00i\x00o\x00n\x00(\x00)+\K([0-9.]\x00)+' "$editor" |
        head -n 1 | tr -d '\000' || true
}

image_version() {
    cat "$IMAGE_VERSION_FILE"
}

print_version() {
    local version mt4_build mt5_build
    version="$(image_version)"
    mt4_build="$(metaeditor_build mt4)"
    mt5_build="$(metaeditor_build mt5)"
    if [[ "$OUTPUT_FORMAT" == "$FORMAT_JSON" ]]; then
        jq -nc \
            --arg version "$version" \
            --arg mt4 "$mt4_build" \
            --arg mt5 "$mt5_build" \
            '{type: "version", version: $version,
              mt4_metaeditor: ($mt4 | if . == "" then null else . end),
              mt5_metaeditor: ($mt5 | if . == "" then null else . end)}'
        return
    fi
    printf 'mql-compiler %s\n' "$version"
    printf 'MT4 MetaEditor %s\n' "${mt4_build:-not installed}"
    printf 'MT5 MetaEditor %s\n' "${mt5_build:-not installed}"
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

# osslsigncode lists the signer first, as the first Subject line under
# "Signer's certificate:"; the chain and timestamp certificates follow.
require_signer() {
    local name="$1" report="$2" subject
    subject="$(awk '/^Signer.s certificate:/ { found = 1 } found && /Subject:/ { print; exit }' <<<"$report")"
    if [[ "$subject" != *"/CN=$SIGNER_PATTERN"* ]]; then
        log ERROR "installer is validly signed but not by $SIGNER_PATTERN file=$name signer=${subject#*Subject: }"
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
    if [[ -z "$(find_installed_metaeditor "$platform")" ]]; then
        log ERROR "install finished without a MetaEditor platform=$platform"
        return 1
    fi
    log INFO "installed platform=$platform path=$(dirname "$(find_installed_metaeditor "$platform")")"
}

# The installer leaves the standard library packed inside the terminal; the
# terminal unpacks it into its MQL4/MQL5 folder the first time it starts.
# Start the terminal in folder $2 once in portable mode, wait for the
# headers, then stop it.
unpack_stdlib() {
    local platform="$1" terminal="$2" root marker waited=0
    root="$terminal/$(mql_folder "$platform")"
    marker="$root/$(stdlib_marker "$platform")"
    [[ -f "$marker" ]] && return 0
    log INFO "unpacking the standard library platform=$platform (starts the terminal once)"
    # The terminal never exits on its own; it is stopped below once the
    # headers are there, and its output is a GUI log nobody reads.
    (cd "$terminal" && wine "$(terminal_name "$platform")" /portable >/dev/null 2>&1 &)
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

installer_url() {
    case "$1" in
        mt4) printf '%s\n' "$MT4_INSTALLER_URL" ;;
        mt5) printf '%s\n' "$MT5_INSTALLER_URL" ;;
    esac
}

# Installs whatever is missing for the given platforms (mt5 and mt4 by
# default). A platform with a --mtN-terminal folder is skipped: it brings its
# own MetaEditor, and the cached install is neither created nor touched.
# Returns non-zero instead of exiting, so --update can put the previous
# toolchain back.
install_toolchain() {
    local platform platforms=("$@")
    ((${#platforms[@]})) || platforms=(mt5 mt4)
    mkdir -p "$HOME" "$INSTALLER_DIR"
    # Every MetaEditor runs under Wine, a mounted one too, so the prefix is
    # always needed.
    if [[ ! -f "$WINEPREFIX/system.reg" ]]; then
        log INFO "creating the Wine prefix path=$WINEPREFIX"
        # wineboot prints first-run noise about missing Mono/Gecko, which a
        # compiler does not need.
        wineboot --init >/dev/null 2>&1
        wineserver -w
    fi
    for platform in "${platforms[@]}"; do
        if [[ -n "$(mounted_terminal "$platform")" ]]; then
            log INFO "using a mounted terminal platform=$platform path=$(terminal_dir "$platform") build=$(metaeditor_build "$platform")"
            continue
        fi
        if [[ -z "$(find_metaeditor "$platform")" ]]; then
            [[ -n "$(find_installed_metaeditor "$platform")" ]] ||
                install_platform "$platform" "$(installer_url "$platform")" || return 1
            make_portable "$platform" || return 1
        fi
        unpack_stdlib "$platform" "$(terminal_dir "$platform")" || return 1
    done
}

# Turns the installer's terminal into the cached portable one: unpacks its
# standard library where the installer put it, then moves the whole folder
# from Program Files to terminals/<platform>. The cached terminal is then a
# folder like any --mtN-terminal one, and every compile goes through the same
# path. A cache from before v0.5.0 takes this step once, with no download.
# The installer's registry and Start menu entries stay in the prefix; nothing
# reads them.
make_portable() {
    local platform="$1" installed target
    installed="$(dirname "$(find_installed_metaeditor "$platform")")"
    target="$(terminal_dir "$platform")"
    unpack_stdlib "$platform" "$installed" || return 1
    mkdir -p "$CACHED_TERMINALS_DIR"
    mv "$installed" "$target"
    log INFO "moved the terminal to a portable folder platform=$platform from=$installed to=$target build=$(metaeditor_build "$platform")"
}

ensure_toolchain() {
    install_toolchain "$@" || die "toolchain setup failed (see the log lines above)"
}

# The platforms a list of sources needs, mt5 before mt4, one per line.
needed_platforms() {
    local listing="$1"
    if grep -qi '\.mq5$' <<<"$listing"; then
        printf 'mt5\n'
    fi
    if grep -qi '\.mq4$' <<<"$listing"; then
        printf 'mt4\n'
    fi
}

# Checks a --mtN-terminal folder and returns it as an absolute path: it must
# hold that platform's MetaEditor and an MQL4/MQL5 folder whose standard
# library the terminal has already unpacked (it does that on its first start).
terminal_folder() {
    local platform="$1" dir="$2" option="--$1-terminal" mql_dir
    [[ "$dir" == /* ]] || dir="$PWD/$dir"
    dir="$(realpath -ms "$dir")"
    [[ -d "$dir" ]] || die "no such terminal folder for $option: $(shown "$dir")"
    [[ -n "$(find "$dir" -maxdepth 1 -type f -iname "$(metaeditor_name "$platform")" -print -quit)" ]] ||
        die "no $(metaeditor_name "$platform") in the $option folder: $(shown "$dir")"
    mql_dir="$(find "$dir" -maxdepth 1 -type d -iname "$(mql_folder "$platform")" -print -quit)"
    [[ -n "$mql_dir" && -f "$mql_dir/$(stdlib_marker "$platform")" ]] ||
        die "no unpacked standard library ($(mql_folder "$platform")/$(stdlib_marker "$platform")) in the $option folder: $(shown "$dir"); start the terminal once so it unpacks it"
    printf '%s\n' "$dir"
}

# A fresh install with the newest installers. The old prefix stays aside
# until the new one works, and comes back if it does not.
update_toolchain() {
    rm -rf "$PREVIOUS_WINEPREFIX"
    if [[ -d "$WINEPREFIX" ]]; then
        mv "$WINEPREFIX" "$PREVIOUS_WINEPREFIX"
    fi
    rm -f "$INSTALLER_DIR"/*.exe
    log INFO "reinstalling the toolchain with the newest installers"
    if install_toolchain; then
        rm -rf "$PREVIOUS_WINEPREFIX"
        log INFO "toolchain updated mt4_build=$(metaeditor_build mt4) mt5_build=$(metaeditor_build mt5)"
        return
    fi
    # The half-built prefix may still have a wineserver; stop it first.
    wineserver -k >/dev/null 2>&1 || true
    rm -rf "$WINEPREFIX"
    if [[ -d "$PREVIOUS_WINEPREFIX" ]]; then
        mv "$PREVIOUS_WINEPREFIX" "$WINEPREFIX"
        log WARN "update failed, kept the previous toolchain reason=update_failed"
    fi
    die "toolchain update failed (see the log lines above)"
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
# them all: links to the terminal's standard Include, then the -I folders,
# then the user's Include, each laid over the one before (the later file wins
# on a clash), plus links to the user's other subfolders for #resource paths.
# It lives in the staging folder because MetaEditor's /inc cannot take a path
# with spaces, and a mounted terminal's folder often has some. Built once per
# platform and user folder per pass.
# -g keeps these global when tests/unit sources the script inside a function.
declare -gA MERGED_ROOTS=()
MERGED_ROOT=""

build_merged_root() {
    local platform="$1" user_root="$2" key entry name include_dir
    key="$platform:$user_root"
    if [[ -n "${MERGED_ROOTS[$key]:-}" ]]; then
        MERGED_ROOT="${MERGED_ROOTS[$key]}"
        return
    fi
    MERGED_ROOT="$STAGING_DIR/roots/${#MERGED_ROOTS[@]}/$(mql_folder "$platform")"
    mkdir -p "$MERGED_ROOT"
    cp -rs "$(stdlib_root "$platform")/Include" "$MERGED_ROOT/Include"
    for include_dir in ${EXTRA_INCLUDES[@]+"${EXTRA_INCLUDES[@]}"}; do
        cp -rs --remove-destination "$include_dir/." "$MERGED_ROOT/Include/"
    done
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

# MetaEditor's /compile, like /inc, cannot take a path with spaces. Such a
# source is compiled through a link in the staging folder to its MQL4/MQL5
# folder (or, for a loose file, its own folder), so the path MetaEditor sees
# has none, and "../" includes inside that folder still resolve. Sets
# STAGED_SOURCE; one link per folder per pass.
declare -gA SOURCE_LINKS=()
STAGED_SOURCE=""

stage_source() {
    local source="$1" root="$2" link
    STAGED_SOURCE="$source"
    [[ "$source" =~ [[:space:]] ]] || return 0
    link="${SOURCE_LINKS[$root]:-}"
    if [[ -z "$link" ]]; then
        link="$STAGING_DIR/sources/${#SOURCE_LINKS[@]}"
        mkdir -p "$STAGING_DIR/sources"
        ln -s "$root" "$link"
        SOURCE_LINKS[$root]="$link"
    fi
    STAGED_SOURCE="$link${source#"$root"}"
}

# A path inside the staging folder, turned into the real file behind it: the
# user's file for a user header or a staged source, the toolchain's for a
# standard header. A missing include in the merged include root reads as if
# under $shown_root, the user's MQL4/MQL5 folder or, for a loose file, the
# terminal's.
real_path() {
    local path="$1" merged="$2" shown_root="$3" target
    if target="$(readlink -e -- "$path")"; then
        printf '%s\n' "$target"
        return
    fi
    if [[ "$path" == "$merged/"* ]]; then
        printf '%s\n' "$shown_root${path#"$merged"}"
        return
    fi
    readlink -m -- "$path"
}

# MetaEditor writes its log as UTF-16 with Windows paths. This prints plain
# UTF-8 lines with those paths turned back into real ones: Z:\ is /, a path
# in the staging folder becomes the file behind it (real_path), and the
# current folder is dropped from the front. Plain string replacement rather
# than sed, so no character in a path can break it.
read_log() {
    local log_file="$1" merged="$2" shown_root="$3" line path rest quote
    iconv -f UTF-16 -t UTF-8 "$log_file" | tr -d '\r' | while IFS= read -r line; do
        line="${line//\\//}"
        line="${line//[Zz]:\//\/}"
        rest="$line"
        while [[ "$rest" == *"$STAGING_DIR/"* ]]; do
            rest="$STAGING_DIR/${rest#*"$STAGING_DIR/"}"
            # A path in a MetaEditor line ends at its "(line,column)" or at
            # the closing quote of a "file '...' not found" message.
            path="${rest%%[\'\(]*}"
            line="${line//"$path"/"$(real_path "$path" "$merged" "$shown_root")"}"
            rest="${rest#"$path"}"
        done
        # Paths start a line or follow a quote; only there is the current
        # folder a prefix to drop.
        for quote in "'" '"'; do
            line="${line//"$quote$PWD/"/$quote}"
        done
        if [[ "$line" == "$PWD/"* ]]; then
            line="${line#"$PWD"/}"
        fi
        printf '%s\n' "$line"
    done
}

# MetaEditor's error and warning lines, "path(line,column) : error 256:
# text", as a JSON array of message objects. Other log lines are dropped.
parse_messages() {
    jq -Rnc '[inputs
        | capture("^(?<file>.*)\\((?<line>[0-9]+),(?<column>[0-9]+)\\) : (?<severity>error|warning) (?<code>[0-9]+): (?<text>.*)$")?
        | {severity, file: (if .file == "" then null else .file end),
           line: (.line | tonumber), column: (.column | tonumber),
           code: (.code | tonumber), text}]'
}

# Prints one file's result in the chosen format. $record is the JSON "file"
# record; text and gnu are rendered from it so all formats say the same.
print_file_result() {
    local record="$1"
    case "$OUTPUT_FORMAT" in
        "$FORMAT_JSON")
            printf '%s\n' "$record"
            ;;
        "$FORMAT_TEXT")
            jq -r '
                def where: if .file == null then "" else .file end
                    + (if .line == null then "" else "(\(.line),\(.column))" end);
                (if .status == "ok" then "OK   \(.source) -> \(.output) (\(.warnings) warnings)"
                 elif .errors == null then "FAIL \(.source): \(.messages[0].text)"
                 else "FAIL \(.source) (\(.errors) errors, \(.warnings) warnings)" end),
                (.messages[] | select(.code != null) | "     \(where) : \(.severity) \(.code): \(.text)"),
                (.log // [] | .[] | "     \(.)")' <<<"$record"
            ;;
        "$FORMAT_GNU")
            jq -r '.source as $source | .messages[]
                | "\(.file // $source):\(.line // 0):\(.column // 0): \(.severity): \(.text)"
                  + (if .code == null then "" else " [\(.code)]" end)' <<<"$record"
            ;;
    esac
}

print_summary() {
    local total="$1" failed="$2"
    log INFO "run complete total=$total compiled=$((total - failed)) failed=$failed"
    [[ "$OUTPUT_FORMAT" == "$FORMAT_JSON" ]] || return 0
    jq -nc \
        --argjson total "$total" \
        --argjson failed "$failed" \
        --argjson werror "$WERROR" \
        '{type: "summary", total: $total, compiled: ($total - $failed), failed: $failed, werror: $werror}'
}

# Compiles one source and prints its result. Returns non-zero when it failed.
compile_one() {
    local source="$1" platform user_root shown_root output editor log_file
    local result errors warnings messages status record
    case "${source,,}" in
        *.mq4) platform=mt4 output="${source%.*}.ex4" ;;
        *.mq5) platform=mt5 output="${source%.*}.ex5" ;;
    esac
    user_root="$(user_mql_root "$source" "$(mql_folder "$platform")")"
    build_merged_root "$platform" "$user_root"
    stage_source "$source" "${user_root:-$(dirname "$source")}"
    shown_root="${user_root:-$(stdlib_root "$platform")}"
    editor="$(find_metaeditor "$platform")"
    log_file="$(mktemp --suffix=.log)"
    # An old .ex4/.ex5 must never outlive a compile that did not produce a new
    # one. MetaEditor removes it on compile errors, but not when it crashes or
    # writes no result.
    rm -f "$output"

    # MetaEditor's exit code is backwards (1 usually means success); the log's
    # Result line is the verdict, and its stderr is Wine noise.
    wine "$editor" \
        "/compile:$(winepath -w "$STAGED_SOURCE")" \
        "/log:$(winepath -w "$log_file")" \
        "/inc:$(winepath -w "$MERGED_ROOT")" >/dev/null 2>&1 || true

    local lines
    lines="$(read_log "$log_file" "$MERGED_ROOT" "$shown_root")"
    rm -f "$log_file"
    result="$(grep -E '^Result: ' <<<"$lines" | tail -n 1)" || result=""
    if [[ -z "$result" ]]; then
        record="$(jq -nc \
            --arg source "$(shown "$source")" \
            --arg platform "$platform" \
            --arg text "$NO_RESULT" \
            --arg lines "$lines" \
            '{type: "file", source: $source, platform: $platform, status: "failed",
              output: null, errors: null, warnings: null,
              messages: [{severity: "error", file: $source, line: null, column: null, code: null, text: $text}],
              log: ($lines | split("\n") | map(select(. != "")))}')"
        print_file_result "$record"
        return 1
    fi
    errors="$(sed -nE 's/^Result: ([0-9]+) error.*/\1/p' <<<"$result")"
    warnings="$(sed -nE 's/.* ([0-9]+) warning.*/\1/p' <<<"$result")"
    messages="$(parse_messages <<<"$lines")"

    status="$STATUS_OK"
    if [[ "${errors:-1}" != "0" ]] || { [[ "$WERROR" == true ]] && [[ "${warnings:-0}" != "0" ]]; }; then
        status="$STATUS_FAILED"
    fi
    record="$(jq -nc \
        --arg source "$(shown "$source")" \
        --arg platform "$platform" \
        --arg status "$status" \
        --arg output "$(shown "$output")" \
        --argjson errors "${errors:-0}" \
        --argjson warnings "${warnings:-0}" \
        --argjson messages "$messages" \
        '{type: "file", source: $source, platform: $platform, status: $status,
          output: (if $errors == 0 then $output else null end),
          errors: $errors, warnings: $warnings, messages: $messages}')"
    print_file_result "$record"
    [[ "$status" == "$STATUS_OK" ]]
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

# Compiles everything the targets name, once. Returns the number of failed
# files through FAILED_COUNT.
FAILED_COUNT=0

compile_pass() {
    local listing source sources=()
    # A command substitution, not <(...), so a bad path ends the run here.
    # A file named twice (directly and through its folder) compiles once.
    listing="$(collect_sources "$@" | awk '!seen[$0]++')"
    [[ -n "$listing" ]] || die "no .mq4 or .mq5 files found in: $*"
    mapfile -t sources <<<"$listing"
    MERGED_ROOTS=()
    SOURCE_LINKS=()
    rm -rf "${STAGING_DIR:?}/roots" "$STAGING_DIR/sources"
    FAILED_COUNT=0
    for source in "${sources[@]}"; do
        compile_one "$source" || FAILED_COUNT=$((FAILED_COUNT + 1))
    done
    print_summary "${#sources[@]}" "$FAILED_COUNT"
}

# The folders --watch listens to: each target folder, each target file's
# folder, and the -I folders.
watch_paths() {
    local target
    for target in "$@" ${EXTRA_INCLUDES[@]+"${EXTRA_INCLUDES[@]}"}; do
        [[ "$target" == /* ]] || target="$PWD/$target"
        if [[ -d "$target" ]]; then
            printf '%s\n' "$target"
            continue
        fi
        dirname "$target"
    done | sort -u
}

# Compiles, then again after every change, until SIGINT or SIGTERM. The run
# lock is released while waiting, so other runs can use the cache meanwhile.
watch_loop() {
    local paths=()
    mapfile -t paths < <(watch_paths "$@")
    while true; do
        flock -u 8
        log INFO "watching for changes paths=${paths[*]}"
        # Runs in the background so the INT/TERM trap fires at once; the wait
        # returns when a matching file is written, created, moved or deleted.
        inotifywait -qq -r -e close_write,create,delete,move --include "$WATCHED_FILES" "${paths[@]}" &
        WATCHER_PID=$!
        # inotifywait exits non-zero when a watched folder disappears; the
        # next pass reports a missing path itself.
        wait "$WATCHER_PID" || true
        WATCHER_PID=""
        acquire_run_lock
        log INFO "change detected, compiling again"
        compile_pass "$@"
    done
}

# ------------------------------------------------------------------- main ---

# Checks a -I folder and returns it as an absolute path.
include_folder() {
    local dir="$1"
    [[ "$dir" == /* ]] || dir="$PWD/$dir"
    dir="$(realpath -ms "$dir")"
    [[ -d "$dir" ]] || die "no such include folder: $(shown "$dir")"
    printf '%s\n' "$dir"
}

# A command substitution, not an assignment inside terminal_folder, so its die
# ends the run.
set_terminal() {
    local platform="$1" dir
    dir="$(terminal_folder "$platform" "$2")"
    case "$platform" in
        mt4) TERMINAL_MT4="$dir" ;;
        mt5) TERMINAL_MT5="$dir" ;;
    esac
}

main() {
    local mode="compile" targets=() watch=false listing platforms=()
    while (($#)); do
        case "$1" in
            -h | --help)
                usage
                exit "$EXIT_OK"
                ;;
            --setup) mode="setup" ;;
            --update) mode="update" ;;
            --version) mode="version" ;;
            --watch) watch=true ;;
            --werror) WERROR=true ;;
            --text) OUTPUT_FORMAT="$FORMAT_TEXT" ;;
            --format | --format=*)
                local format="${1#--format}"
                format="${format#=}"
                if [[ -z "$format" ]]; then
                    (($# >= 2)) || die "--format needs a value: json, text or gnu"
                    shift
                    format="$1"
                fi
                case "$format" in
                    "$FORMAT_JSON" | "$FORMAT_TEXT" | "$FORMAT_GNU") OUTPUT_FORMAT="$format" ;;
                    *) die "unknown format: $format (json, text or gnu)" ;;
                esac
                ;;
            -I | --include)
                (($# >= 2)) || die "$1 needs a folder"
                shift
                EXTRA_INCLUDES+=("$(include_folder "$1")")
                ;;
            -I* | --include=*)
                local value="${1#--include=}"
                EXTRA_INCLUDES+=("$(include_folder "${value#-I}")")
                ;;
            --mt4-terminal | --mt5-terminal)
                (($# >= 2)) || die "$1 needs a folder"
                local option="$1"
                shift
                set_terminal "${option:2:3}" "$1"
                ;;
            --mt4-terminal=* | --mt5-terminal=*)
                set_terminal "${1:2:3}" "${1#*=}"
                ;;
            -*) die "unknown option: $1 (see --help)" ;;
            *) targets+=("$1") ;;
        esac
        shift
    done
    ((${#targets[@]})) || targets=(".")

    if [[ "$mode" == "version" ]]; then
        print_version
        exit "$EXIT_OK"
    fi

    # Wine refuses a prefix owned by another UID, so say so before trying.
    if [[ -e "$CACHE_ROOT" && ! -O "$CACHE_ROOT" ]]; then
        die "$CACHE_ROOT belongs to UID $(stat -c %u "$CACHE_ROOT"), not $CALLER_UID: the cache was written by another UID"
    fi
    mkdir -p "$LOG_DIR"
    acquire_run_lock
    start_logging
    log INFO "mql-compiler version=$(image_version) mode=$mode format=$OUTPUT_FORMAT"

    # Stopping the run (docker stop, Ctrl-C through docker run --init) still
    # goes through finish, so the log is complete and the staging folder gone.
    trap 'exit "$EXIT_INTERRUPTED"' INT TERM

    if [[ "$mode" == "compile" ]]; then
        # Bad paths and empty folders fail now, before a first-run install.
        listing="$(collect_sources "${targets[@]}")"
        [[ -n "$listing" ]] || die "no .mq4 or .mq5 files found in: ${targets[*]}"
        # Only the platforms these sources need get installed, so a first
        # run of .mq5 files with --mt5-terminal downloads nothing at all.
        mapfile -t platforms < <(needed_platforms "$listing")
        # --watch may meet the other extension later, so it gets both.
        [[ "$watch" == false ]] || platforms=(mt5 mt4)
    fi

    STAGING_DIR="$(mktemp -d /tmp/mql-compiler.XXXXXX)"
    start_display
    case "$mode" in
        setup)
            ensure_toolchain
            log INFO "toolchain ready path=$CACHE_ROOT"
            print_version
            exit "$EXIT_OK"
            ;;
        update)
            update_toolchain
            print_version
            exit "$EXIT_OK"
            ;;
    esac

    ensure_toolchain "${platforms[@]}"
    keep_wineserver
    compile_pass "${targets[@]}"
    if [[ "$watch" == true ]]; then
        watch_loop "${targets[@]}"
    fi
    ((FAILED_COUNT == 0)) || exit "$EXIT_COMPILE_ERRORS"
}

# Sourcing the script (tests/unit) loads the functions without running a compile.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
