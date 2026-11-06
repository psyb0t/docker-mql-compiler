#!/bin/bash
# install_platform when the installer never finishes: the wait for it gives
# up after MQL_COMPILER_INSTALL_TIMEOUT seconds and setup fails, instead of
# hanging until something outside kills the run. A value that is not a whole
# number of seconds is refused before anything is installed. curl, the
# signature check and wine are stubbed; wineserver is a fake on PATH, because
# timeout runs it as a program.

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
readonly SLOWEST_ACCEPTABLE_SECONDS=20

# The fake waits far longer than the timeout on -w and exits at once on -k.
cat >"$FAKE_BIN/wineserver" <<'FAKE'
#!/bin/bash
if [[ "${1:-}" == "-w" ]]; then
    sleep 300
fi
exit 0
FAKE
chmod +x "$FAKE_BIN/wineserver"
export PATH="$FAKE_BIN:$PATH"

curl() {
    # The last argument is the URL; -o names the file to write.
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

wine() {
    # The setup launcher returns at once and leaves its child running.
    :
}

INSTALLER_DIR="$(mktemp -d)"

started=$SECONDS
output="$(install_platform mt5 "https://example.invalid/mt5setup.exe" 2>&1)"
status=$?
elapsed=$((SECONDS - started))

expect_equal "an installer that never finishes fails the install" "$status" 1
expect_match "the log says the installer did not finish" "$output" 'installer did not finish platform=mt5 waited=2s'
if ((elapsed < SLOWEST_ACCEPTABLE_SECONDS)); then
    pass "the install gives up after the timeout"
else
    fail "the install gives up after the timeout" "took ${elapsed}s"
fi

refused="$(MQL_COMPILER_INSTALL_TIMEOUT=soon bash -c '
    source /unit/lib.sh
    load_entrypoint
    INSTALLER_DIR="$(mktemp -d)"
    curl() { :; }
    verify_installer() { return 0; }
    wine() { echo "WINE RAN"; }
    install_platform mt5 "https://example.invalid/mt5setup.exe" 2>&1
    echo "status=$?"
')"
expect_match "a timeout that is not a number is refused" "$refused" 'MQL_COMPILER_INSTALL_TIMEOUT must be a whole number of seconds value=soon'
expect_match "a refused timeout fails the install" "$refused" 'status=1'
if grep -q 'WINE RAN' <<<"$refused"; then
    fail "a refused timeout starts no installer" "wine ran"
else
    pass "a refused timeout starts no installer"
fi
