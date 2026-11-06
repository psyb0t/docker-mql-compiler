#!/bin/bash
# Writes the seccomp profile the command and the Action pass to docker run:
# Docker's default profile, fetched from URL and checked against SHA256, plus
# userfaultfd. Wine 11 calls userfaultfd while it starts; under Linux 7.0
# Docker's default filter refuses it and Wine stops with "wine: socket :
# Function not implemented" before wineboot finishes. The kernel's own
# vm.unprivileged_userfaultfd rule still applies inside the container.
#
#   make-seccomp.sh URL SHA256 OUTPUT
set -euo pipefail

readonly USERFAULTFD_RULE='{"names":["userfaultfd"],"action":"SCMP_ACT_ALLOW","comment":"Wine 11 needs it to start under Linux 7.0; added by docker-mql-compiler"}'

main() {
    [[ $# -eq 3 ]] || {
        printf 'usage: %s URL SHA256 OUTPUT\n' "${0##*/}" >&2
        exit 2
    }
    local url="$1" sha256="$2" output="$3" base
    base="$(mktemp)"
    curl -fsSL -o "$base" "$url"
    echo "$sha256  $base" | sha256sum -c - >/dev/null
    jq --argjson rule "$USERFAULTFD_RULE" '.syscalls += [$rule]' "$base" >"$output"
    rm -f "$base"
    printf 'wrote %s from %s\n' "$output" "$url"
}

main "$@"
