#!/bin/bash
# mql-compiler-managed-command
#
# The `mql-compiler` command install.sh puts on your PATH. It compiles .mq4
# and .mq5 files with the psyb0t/mql-compiler image and exits with the
# image's status.
#
#   mql-compiler                         compile everything under the current folder
#   mql-compiler ~/mt/MQL5/Experts       compile one folder, from anywhere
#   mql-compiler Foo.mq5 /abs/Bar.mq4    compile these files
#   mql-compiler --setup                 only install the MetaQuotes toolchain
#   mql-compiler --help                  the compiler's own help
#
# Paths may be relative or absolute and sit anywhere. For each one this
# mounts its nearest enclosing MQL4/MQL5 folder (so its Include and other
# folders come along), or, outside any MQL4/MQL5 folder, the folder itself or
# the file's folder. Mounts go to the same absolute path in the container and
# the container starts in the current folder, so every path in the output is
# one you can open. The toolchain (Wine plus MT4 and MT5, about 2 GB) lives
# in the Docker volume mql-compiler-cache, not in your home folder; `docker
# volume rm mql-compiler-cache` frees it and the next run downloads it again.
# The container runs as your UID, so compiled files belong to you.
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
readonly MQL_FOLDERS=(MQL4 MQL5)

fail() {
    printf 'mql-compiler: %s\n' "$*" >&2
    exit "$EXIT_USAGE"
}

# The nearest folder named MQL4 or MQL5 (any case) at or above $1, or nothing.
mql_ancestor() {
    local dir="$1" name folder
    while [[ "$dir" != "/" ]]; do
        name="$(basename "$dir" | tr '[:lower:]' '[:upper:]')"
        for folder in "${MQL_FOLDERS[@]}"; do
            if [[ "$name" == "$folder" ]]; then
                printf '%s\n' "$dir"
                return 0
            fi
        done
        dir="$(dirname "$dir")"
    done
}

# The folder to mount so the compiler sees $1 and everything it includes.
mount_root() {
    local path="$1" dir root
    dir="$path"
    [[ -d "$path" ]] || dir="$(dirname "$path")"
    root="$(mql_ancestor "$dir")"
    printf '%s\n' "${root:-$dir}"
}

command -v docker >/dev/null 2>&1 || fail "docker is not installed"

image="${MQL_COMPILER_IMAGE:-$PINNED_IMAGE}"
volume="${MQL_COMPILER_VOLUME:-$DEFAULT_VOLUME}"
workdir="$(pwd -P)"

# Paths become absolute and symlink-free: the container holds only the
# mounted folders, at their real host paths.
args=()
roots=()
for arg in "$@"; do
    if [[ "$arg" == -* ]]; then
        args+=("$arg")
        continue
    fi
    [[ -e "$arg" ]] || fail "no such file or folder: $arg"
    path="$(realpath "$arg")"
    args+=("$path")
    roots+=("$(mount_root "$path")")
done
# No path means the current folder, which still needs its MQL4/MQL5 parent.
if ((${#roots[@]} == 0)); then
    args+=("$workdir")
    roots+=("$(mount_root "$workdir")")
fi

docker_args=(
    --rm
    --user "$(id -u):$(id -g)"
    -w "$workdir"
    -v "$volume":/cache
)
# One mount per folder; a folder inside one already mounted comes along with
# it. Sorted, a parent always comes before its children.
kept=()
while IFS= read -r root; do
    for parent in ${kept[@]+"${kept[@]}"}; do
        [[ "$parent" == "/" || "$root" == "$parent" || "$root" == "$parent/"* ]] && continue 2
    done
    kept+=("$root")
    docker_args+=(-v "$root:$root")
done < <(printf '%s\n' "${roots[@]}" | sort -u)

# Forward installer overrides only when set, so the image keeps its defaults.
for var in "${FORWARDED_VARS[@]}"; do
    if [[ -n "${!var:-}" ]]; then
        docker_args+=(-e "$var=${!var}")
    fi
done

# The ${x[@]+...} form keeps an empty array safe under set -u on bash 3.2.
exec docker run "${docker_args[@]}" "$image" ${args[@]+"${args[@]}"}
