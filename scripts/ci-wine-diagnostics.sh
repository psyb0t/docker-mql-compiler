#!/bin/bash
# Prints what CI needs to see when Wine cannot start in the image on a runner:
# the kernel, Docker and its security options, whether 32-bit programs run,
# how far wineboot gets with Wine's error channel on, whether it works with
# Docker's seccomp filter off, and which system calls Docker's default filter
# would refuse. Every check reports and moves on.
set -euo pipefail

readonly IMAGE="psyb0t/mql-compiler:dev"
readonly I386_IMAGE="i386/debian:trixie-slim@sha256:48a6ec1047c40f162d2766a088014f59009e8a35d0dfdb5e966573f7eb7b980f"
# A healthy wineboot --init takes a few seconds.
readonly WINEBOOT_TIMEOUT_SECONDS=120
readonly LOG_TAIL_LINES=40
readonly AUDIT_LINES=30
readonly DEFAULT_PROFILE_URL="https://raw.githubusercontent.com/moby/profiles/seccomp/v0.3.0/seccomp/default.json"
readonly DEFAULT_PROFILE_SHA256="6416b47770785a41ac59073cdc77d9fe98517df2799dc83ef207e622de3053f6"

# Runs wineboot --init in a fresh prefix inside the image, with any extra
# docker run options given, and prints its exit status and the end of its log.
wineboot_check() {
    local label="$1"
    shift
    echo "== wineboot --init, $label"
    # The image's entrypoint is bypassed so only wineboot and Xvfb run.
    docker run --rm --entrypoint bash -e WINEDEBUG=err+all "$@" "$IMAGE" -c "
        export WINEPREFIX=/tmp/prefix
        mkdir -p \"\$WINEPREFIX\"
        Xvfb :99 -screen 0 1024x768x24 -nolisten tcp >/dev/null 2>&1 &
        sleep 2
        timeout $WINEBOOT_TIMEOUT_SECONDS wineboot --init >/tmp/wineboot.log 2>&1
        echo \"wineboot exit=\$?\"
        tail -n $LOG_TAIL_LINES /tmp/wineboot.log
    " || echo "the diagnostic container failed exit=$?"
}

echo "== kernel"
uname -a
echo "== Docker"
docker version --format 'server {{.Server.Version}}, client {{.Client.Version}}'
docker info --format 'security options: {{.SecurityOptions}}'
echo "== 32-bit programs"
if docker run --rm --platform linux/386 "$I386_IMAGE" true; then
    echo "a 32-bit container ran"
else
    echo "a 32-bit container did not run"
fi

wineboot_check "default seccomp"
wineboot_check "seccomp=unconfined" --security-opt seccomp=unconfined

echo "== system calls Docker's default seccomp filter refuses during wineboot"
# Docker's default profile (moby/profiles seccomp/v0.3.0, the one Docker 29
# builds in) with its default action switched from refusing to logging, so
# wineboot runs and the kernel logs each call the real filter would refuse.
curl -fsSL -o /tmp/default-seccomp.json "$DEFAULT_PROFILE_URL"
echo "$DEFAULT_PROFILE_SHA256  /tmp/default-seccomp.json" | sha256sum -c -
jq '.defaultAction = "SCMP_ACT_LOG"' /tmp/default-seccomp.json >/tmp/log-seccomp.json
# Best effort: without it the audit lines below also show older entries.
sudo dmesg --clear || true
wineboot_check "default seccomp, logging instead of refusing" --security-opt seccomp=/tmp/log-seccomp.json
echo "== kernel log: seccomp audit lines (arch, syscall number)"
sudo dmesg | grep -o -E 'type=1326.*' | grep -o -E 'arch=[0-9a-f]+ syscall=[0-9]+' | sort | uniq -c | sort -rn | head -n "$AUDIT_LINES" || echo "no seccomp audit lines"
