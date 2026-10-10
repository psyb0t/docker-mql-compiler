#!/bin/bash
# mql-compiler: compile MQL4 (.mq4) and MQL5 (.mq5) sources with MetaEditor
# under Wine.
#
#   mql-compiler [--setup] [--help] [PATH ...]
#
# PATHs are files or directories under the mounted /src, relative or absolute.
# Without any, every .mq4 and .mq5 under /src is compiled. Each .ex4/.ex5 is
# written next to its source, as MetaEditor does.
#
# `#include <...>` resolves against the nearest enclosing folder named MQL4 or
# MQL5 (the layout of a terminal's data folder), so mounting a whole MQL5
# folder compiles its Experts, Indicators and Scripts against its own Include.
#
# The MetaQuotes toolchain is not in the image. The first run downloads the
# RoboForex MT4 and MT5 installers, checks their MetaQuotes code signature,
# and installs them into /cache/uid-<UID>. Keep /cache on a volume and later
# runs skip straight to compiling.
#
# Exit status: 0 every file compiled, 1 at least one has compile errors,
# 2 bad usage or a toolchain that could not be set up.
#
# Compile results go to stdout; JSON log lines go to stderr. Both are also
# written to /cache/uid-<UID>/logs/last-run.log.
set -euo pipefail
trap 'printf "{\"level\":\"ERROR\",\"file\":\"%s\",\"line\":%d,\"msg\":\"command failed exit=%d\"}\n" "${BASH_SOURCE[0]##*/}" "$LINENO" "$?" >&2' ERR

readonly SRC_ROOT="/src"
# Each UID gets its own toolchain folder, so one shared volume serves every
# user and Wine always finds a prefix it owns.
CALLER_UID="$(id -u)"
readonly CALLER_UID
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
Usage: mql-compiler [--setup] [PATH ...]

Compiles .mq4 and .mq5 files with MetaEditor. PATHs are files or folders
under /src; without any, everything under /src is compiled. Outputs land next
to their sources. #include <...> resolves against the nearest MQL4/ or MQL5/
folder above the source.

  --setup   only download and install the MetaQuotes toolchain into /cache
  --help    show this help

Exit status: 0 all compiled, 1 compile errors, 2 usage or setup failure.
EOF
}

# ---------------------------------------------------------------- display ---

XVFB_PID=""

start_display() {
    # Xvfb's and wineserver's own chatter is noise in a compile log; failures
    # surface when MetaEditor cannot start.
    Xvfb "$XVFB_DISPLAY" -screen 0 1024x768x24 -nolisten tcp >/dev/null 2>&1 &
    XVFB_PID=$!
}

# One persistent wineserver for the compile loop, so each MetaEditor call
# skips Wine's start-up. Needs the prefix, so it starts after setup.
keep_wineserver() {
    wineserver -p >/dev/null 2>&1
}

stop_display() {
    # Best effort on the way out: a wineserver or Xvfb that is already gone
    # must not turn a finished run into a failure.
    wineserver -k >/dev/null 2>&1 || true
    if [[ -n "$XVFB_PID" ]]; then
        kill "$XVFB_PID" >/dev/null 2>&1 || true
    fi
}

# -------------------------------------------------------------- toolchain ---

metaeditor_name() {
    case "$1" in
        mt4) printf '%s\n' "$MT4_METAEDITOR" ;;
        mt5) printf '%s\n' "$MT5_METAEDITOR" ;;
    esac
}

find_metaeditor() {
    [[ -d "$DRIVE_C" ]] || return 0
    # Unreadable corners of a Wine prefix are irrelevant to the search.
    find "$DRIVE_C" -path "$DRIVE_C/windows" -prune -o -iname "$(metaeditor_name "$1")" -print -quit 2>/dev/null
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
    flock -u 9
}

# ---------------------------------------------------------------- compile ---

relative() {
    printf '%s\n' "${1#"$SRC_ROOT"/}"
}

# The nearest enclosing MQL4/ or MQL5/ folder (matched case-insensitively, as
# Windows would), which MetaEditor's /inc: takes as the root for <...>.
include_root() {
    local dir wanted="$2"
    dir="$(dirname "$1")"
    while [[ "$dir" == "$SRC_ROOT"* ]]; do
        if [[ "$(basename "$dir" | tr '[:lower:]' '[:upper:]')" == "$wanted" ]]; then
            printf '%s\n' "$dir"
            return 0
        fi
        [[ "$dir" == "$SRC_ROOT" ]] && return 0
        dir="$(dirname "$dir")"
    done
}

# MetaEditor writes its log as UTF-16 with Windows paths; this prints plain
# UTF-8 lines with those paths made relative to /src again.
read_log() {
    local windows_root
    windows_root="$(winepath -w "$SRC_ROOT")"
    iconv -f UTF-16 -t UTF-8 "$1" | tr -d '\r' | sed -e "s|${windows_root//\\/\\\\}\\\\||g" -e 's|\\|/|g'
}

compile_one() {
    local source="$1" platform root output editor log_file result errors warnings
    case "${source,,}" in
        *.mq4) platform=mt4 root="$(include_root "$source" MQL4)" output="${source%.*}.ex4" ;;
        *.mq5) platform=mt5 root="$(include_root "$source" MQL5)" output="${source%.*}.ex5" ;;
    esac
    editor="$(find_metaeditor "$platform")"
    log_file="$(mktemp --suffix=.log)"

    local args=("/compile:$(winepath -w "$source")" "/log:$(winepath -w "$log_file")")
    [[ -n "$root" ]] && args+=("/inc:$(winepath -w "$root")")
    # MetaEditor's exit code is backwards (1 usually means success); the log's
    # Result line is the verdict, and its stderr is Wine noise.
    wine "$editor" "${args[@]}" >/dev/null 2>&1 || true

    result="$(read_log "$log_file" | grep -E '^Result: ' | tail -n 1)" || result=""
    if [[ -z "$result" ]]; then
        printf 'FAIL %s: MetaEditor wrote no result\n' "$(relative "$source")"
        read_log "$log_file" | sed 's/^/     /'
        rm -f "$log_file"
        return 1
    fi
    errors="$(sed -nE 's/^Result: ([0-9]+) error.*/\1/p' <<<"$result")"
    warnings="$(sed -nE 's/.* ([0-9]+) warning.*/\1/p' <<<"$result")"

    if [[ "$errors" == "0" ]]; then
        printf 'OK   %s -> %s (%s warnings)\n' "$(relative "$source")" "$(relative "$output")" "${warnings:-0}"
    else
        printf 'FAIL %s (%s errors, %s warnings)\n' "$(relative "$source")" "$errors" "${warnings:-0}"
    fi
    # A clean file has no error or warning lines, which grep reports as 1.
    read_log "$log_file" | grep -E ' : (error|warning) ' | sed 's/^/     /' || true
    rm -f "$log_file"
    [[ "$errors" == "0" ]]
}

collect_sources() {
    local target
    for target in "$@"; do
        [[ "$target" == /* ]] || target="$SRC_ROOT/$target"
        if [[ -d "$target" ]]; then
            find "$target" -type f \( -iname '*.mq4' -o -iname '*.mq5' \) -print | sort
            continue
        fi
        [[ -f "$target" ]] || die "no such file or folder: $(relative "$target")"
        case "${target,,}" in
            *.mq4 | *.mq5) printf '%s\n' "$target" ;;
            *) die "not an .mq4 or .mq5 file: $(relative "$target")" ;;
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
    ((${#targets[@]})) || targets=("$SRC_ROOT")

    mkdir -p "$LOG_DIR"
    exec > >(tee "$LOG_FILE") 2> >(tee -a "$LOG_FILE" >&2)

    local sources=() listing
    if [[ "$setup_only" == false ]]; then
        # A command substitution, not <(...), so a bad PATH ends the run here.
        listing="$(collect_sources "${targets[@]}")"
        [[ -n "$listing" ]] || die "no .mq4 or .mq5 files found under $(relative "${targets[0]}")"
        mapfile -t sources <<<"$listing"
    fi

    start_display
    trap stop_display EXIT
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
