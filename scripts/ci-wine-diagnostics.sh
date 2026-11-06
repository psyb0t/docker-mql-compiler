#!/bin/bash
# Prints what CI needs to see when Wine cannot start in the image on a runner:
# the kernel, whether 32-bit programs run at all, and how far wineboot gets
# with Wine's error channel on. Every check reports and moves on.
set -euo pipefail

readonly IMAGE="psyb0t/mql-compiler:dev"
readonly I386_IMAGE="i386/debian:trixie-slim@sha256:48a6ec1047c40f162d2766a088014f59009e8a35d0dfdb5e966573f7eb7b980f"
# A healthy wineboot --init takes a few seconds.
readonly WINEBOOT_TIMEOUT_SECONDS=120
readonly LOG_TAIL_LINES=80

echo "== kernel"
uname -a
echo "== kernel command line"
cat /proc/cmdline
echo "== 32-bit programs"
if docker run --rm --platform linux/386 "$I386_IMAGE" true; then
    echo "a 32-bit container ran"
else
    echo "a 32-bit container did not run"
fi
echo "== wineboot --init with WINEDEBUG=err+all"
# The image's entrypoint is bypassed so only wineboot and Xvfb run.
docker run --rm --entrypoint bash -e WINEDEBUG=err+all "$IMAGE" -c "
    export WINEPREFIX=/tmp/prefix
    mkdir -p \"\$WINEPREFIX\"
    Xvfb :99 -screen 0 1024x768x24 -nolisten tcp >/dev/null 2>&1 &
    sleep 2
    timeout $WINEBOOT_TIMEOUT_SECONDS wineboot --init >/tmp/wineboot.log 2>&1
    echo \"wineboot exit=\$?\"
    tail -n $LOG_TAIL_LINES /tmp/wineboot.log
    echo '== processes left'
    ps -eo pid,etime,args | grep -v ' ps ' || true
" || echo "the diagnostic container failed exit=$?"
