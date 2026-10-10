#!/bin/bash
# Helpers for the unit scripts in tests/unit. They run inside the image
# (tests/test.sh mounts this folder at /unit), source the entrypoint to get its
# functions, and print one PASS or FAIL line per check, which test.sh counts.

pass() {
    printf 'PASS %s\n' "$1"
}

fail() {
    printf 'FAIL %s: %s\n' "$1" "$2"
}

# Passes when the two values are equal.
expect_equal() {
    local name="$1" got="$2" want="$3"
    if [[ "$got" == "$want" ]]; then
        pass "$name"
        return
    fi
    fail "$name" "got '$got', want '$want'"
}

# Passes when the text matches the extended regex.
expect_match() {
    local name="$1" text="$2" pattern="$3"
    if grep -qE -- "$pattern" <<<"$text"; then
        pass "$name"
        return
    fi
    fail "$name" "lacks /$pattern/"
}

# Loads the entrypoint's functions. Its strict mode and ERR trap would end or
# clutter the checks, which inspect return codes themselves.
load_entrypoint() {
    # shellcheck source=/dev/null # the image's entrypoint, only present in the container
    source /usr/local/bin/mql-compiler
    set +e
    trap - ERR
}
