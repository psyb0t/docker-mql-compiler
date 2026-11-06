#!/bin/bash
# install_platform when the installer never finishes: whether the setup
# launcher itself never returns or the processes it leaves behind keep
# running, the install gives up after MQL_COMPILER_INSTALL_TIMEOUT seconds and
# setup fails, instead of hanging until something outside kills the run. A
# value that is not a whole number of seconds is refused before anything is
# installed. curl and the signature check are stubbed; wine and wineserver are
# fakes on PATH, because timeout runs them as programs.

# INSTALLER_DIR is read by the sourced entrypoint's functions.
# shellcheck disable=SC2034
# Read by the sourced entrypoint when it loads.
export MQL_COMPILER_INSTALL_TIMEOUT=2
set -uo pipefail

# shellcheck source=tests/unit/lib.sh
source /unit/lib.sh
load_entrypoint

FAKE_BIN="$(mktemp -d)"
readonly FAKE_BIN
WINE_RAN="$(mktemp)"
readonly WINE_RAN
readonly SLOWEST_ACCEPTABLE_SECONDS=20

# FAKE_WINE=hang makes the launcher never return; otherwise it returns at once.
cat >"$FAKE_BIN/wine" <<'FAKE'
#!/bin/bash
printf 'ran\n' >>"$WINE_RAN"
if [[ "${FAKE_WINE:-}" == "hang" ]]; then
    exec sleep 300
fi
exit 0
FAKE
# FAKE_WINESERVER=idle makes -w return at once; otherwise -w never returns.
cat >"$FAKE_BIN/wineserver" <<'FAKE'
#!/bin/bash
if [[ "${1:-}" == "-w" && "${FAKE_WINESERVER:-}" != "idle" ]]; then
    exec sleep 300
fi
exit 0
FAKE
chmod +x "$FAKE_BIN/wine" "$FAKE_BIN/wineserver"
export PATH="$FAKE_BIN:$PATH" WINE_RAN

curl() {
    # -o names the file to write.
    local out=""
    while (($#)); do
        if [[ "$1" == "-o" ]]; then
            out="$2"
            shift
        fi
        shift
    done
    printf 'installer\n' >"$out"
}

verify_installer() {
    return 0
}

INSTALLER_DIR="$(mktemp -d)"

# Runs install_platform with the fakes as set in the environment and checks
# that it gives up in time with the right log line.
expect_gives_up() {
    local case="$1" output status started elapsed
    started=$SECONDS
    output="$(install_platform mt5 "https://example.invalid/mt5setup.exe" 2>&1)"
    status=$?
    elapsed=$((SECONDS - started))
    expect_equal "$case: the install fails" "$status" 1
    expect_match "$case: the log says the installer did not finish" "$output" 'installer did not finish platform=mt5 waited=2s'
    if ((elapsed < SLOWEST_ACCEPTABLE_SECONDS)); then
        pass "$case: the install gives up after the timeout"
        return
    fi
    fail "$case: the install gives up after the timeout" "took ${elapsed}s"
}

export FAKE_WINE="" FAKE_WINESERVER=""
expect_gives_up "an installer that never finishes"
export FAKE_WINE="hang" FAKE_WINESERVER="idle"
expect_gives_up "a launcher that never returns"

: >"$WINE_RAN"
export FAKE_WINE="" FAKE_WINESERVER="idle"
refused="$(MQL_COMPILER_INSTALL_TIMEOUT=soon bash -c '
    source /unit/lib.sh
    load_entrypoint
    INSTALLER_DIR="$(mktemp -d)"
    curl() { :; }
    verify_installer() { return 0; }
    install_platform mt5 "https://example.invalid/mt5setup.exe" 2>&1
    echo "status=$?"
')"
expect_match "a timeout that is not a number is refused" "$refused" 'MQL_COMPILER_INSTALL_TIMEOUT must be a whole number of seconds value=soon'
expect_match "a refused timeout fails the install" "$refused" 'status=1'
if [[ -s "$WINE_RAN" ]]; then
    fail "a refused timeout starts no installer" "wine ran"
else
    pass "a refused timeout starts no installer"
fi
