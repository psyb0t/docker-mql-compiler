#!/bin/bash
# Prints what CI needs to see when Wine cannot start in the image on a runner:
# the kernel, Docker and its security options, whether 32-bit programs run,
# how far wineboot gets with Wine's error channel on, which system calls fail
# with ENOSYS under strace, and whether wineboot works with Docker's seccomp
# filter off. Every check reports and moves on.
set -euo pipefail

readonly IMAGE="psyb0t/mql-compiler:dev"
readonly I386_IMAGE="i386/debian:trixie-slim@sha256:48a6ec1047c40f162d2766a088014f59009e8a35d0dfdb5e966573f7eb7b980f"
# A healthy wineboot --init takes a few seconds.
readonly WINEBOOT_TIMEOUT_SECONDS=120
readonly LOG_TAIL_LINES=40
readonly ENOSYS_LINES=30
# The strace run installs strace first; the whole container gets this long.
readonly STRACE_CONTAINER_TIMEOUT_SECONDS=300

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

echo "== system calls that failed with ENOSYS during wineboot (strace, default seccomp)"
# Root inside this throwaway container only, to install strace.
timeout "$STRACE_CONTAINER_TIMEOUT_SECONDS" docker run --rm --init --user 0 --entrypoint bash -e WINEDEBUG=-all "$IMAGE" -c "
    apt-get update -qq >/dev/null 2>&1
    apt-get install -y -qq strace >/dev/null 2>&1 || { echo 'strace did not install'; exit 0; }
    export WINEPREFIX=/root/prefix
    Xvfb :99 -screen 0 1024x768x24 -nolisten tcp >/dev/null 2>&1 &
    sleep 2
    timeout $WINEBOOT_TIMEOUT_SECONDS strace -f -o /tmp/trace.txt wineboot --init >/dev/null 2>&1
    echo \"wineboot exit=\$?\"
    grep ENOSYS /tmp/trace.txt | sed -E 's/^[0-9]+ +//; s/\\(.*= -1 ENOSYS/(...) = -1 ENOSYS/' | sort | uniq -c | sort -rn | head -n $ENOSYS_LINES
" || echo "the strace container failed or ran out of time exit=$?"
