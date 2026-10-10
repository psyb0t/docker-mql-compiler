#!/bin/bash
# mql-compiler-managed-command
#
# The `mql-compiler` command install.sh puts on your PATH. It compiles .mq4
# and .mq5 files under the current directory with the psyb0t/mql-compiler
# image and exits with the image's status.
#
#   mql-compiler                  compile everything under the current directory
#   mql-compiler MQL5/Experts     compile one folder
#   mql-compiler Foo.mq5 Bar.mq4  compile these files
#   mql-compiler --setup          only install the MetaQuotes toolchain
#   mql-compiler --help           the compiler's own help
#
# The current directory is mounted at /src, so PATHs must sit inside it. The
# toolchain (Wine plus MT4 and MT5, about 2 GB) lives in the Docker volume
# mql-compiler-cache, not in your home folder; `docker volume rm
# mql-compiler-cache` frees it and the next run downloads it again. The
# container runs as your UID, so compiled files belong to you.
#
# Exit status: 0 all compiled, 1 compile errors, 2 usage or setup failure.
#
# Environment:
#   MQL_COMPILER_IMAGE    run this image instead of the pinned one
#   MQL_COMPILER_VOLUME   toolchain volume name (default mql-compiler-cache)
#   MQL_COMPILER_MT4_URL  MT4 installer to use instead of RoboForex's
#   MQL_COMPILER_MT5_URL  MT5 installer to use instead of RoboForex's
set -euo pipefail

# install.sh writes the image this command is pinned to.
readonly PINNED_IMAGE="psyb0t/mql-compiler:latest"
readonly DEFAULT_VOLUME="mql-compiler-cache"
readonly EXIT_USAGE=2
readonly FORWARDED_VARS=(MQL_COMPILER_MT4_URL MQL_COMPILER_MT5_URL)

fail() {
    printf 'mql-compiler: %s\n' "$*" >&2
    exit "$EXIT_USAGE"
}

command -v docker >/dev/null 2>&1 || fail "docker is not installed"

image="${MQL_COMPILER_IMAGE:-$PINNED_IMAGE}"
volume="${MQL_COMPILER_VOLUME:-$DEFAULT_VOLUME}"

docker_args=(
    --rm
    --user "$(id -u):$(id -g)"
    -v "$PWD":/src
    -v "$volume":/cache
)
# Forward installer overrides only when set, so the image keeps its defaults.
for var in "${FORWARDED_VARS[@]}"; do
    if [[ -n "${!var:-}" ]]; then
        docker_args+=(-e "$var=${!var}")
    fi
done

exec docker run "${docker_args[@]}" "$image" "$@"
