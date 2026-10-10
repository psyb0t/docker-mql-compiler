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
#   mql-compiler -I ~/libs MQL5          add an include folder (mounted too)
#   mql-compiler --watch MQL5            recompile on every change until Ctrl-C
#   mql-compiler --setup                 only install the MetaQuotes toolchain
#   mql-compiler --help                  the compiler's own help, every option
#
# Results come out as JSON Lines on stdout unless --text or --format says
# otherwise; this command's own errors (a missing path, refusing /) follow
# the same format, so a caller parsing stdout always gets a record.
#
# Paths may be relative or absolute and sit anywhere. For each one this
# mounts the folder it includes from (so its Include and other folders come
# along): the nearest MQL4 above a .mq4, MQL5 above a .mq5, either above a
# folder, or, outside any of them, the folder itself or the file's folder.
# It never mounts /. Mounts go to the same absolute path in the container and
# the container starts in the current folder, so every path in the output is
# your real one. The toolchain (a Wine prefix with MT4 and MT5, about 2 GB)
# lives in the Docker volume mql-compiler-cache, not in your home folder; `docker
# volume rm mql-compiler-cache` frees it and the next run downloads it again.
# The container runs as your UID, so compiled files belong to you.
#
# Exit status: 0 all compiled, 1 compile errors, 2 usage or setup failure;
# Docker's own code (usually 125) when Docker itself fails.
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
readonly FORMAT_JSON="json"

# The image's output format, so the command's own errors come out the same
# way: an {"type":"error"} record on stdout for JSON, a plain line otherwise.
output_format="$FORMAT_JSON"
previous=""
for arg in "$@"; do
    case "$arg" in
        --text) output_format="text" ;;
        --format=*) output_format="${arg#--format=}" ;;
    esac
    if [[ "$previous" == "--format" ]]; then
        output_format="$arg"
    fi
    previous="$arg"
done

# A JSON string literal; this runs on the host, where jq may be missing.
json_string() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    value="${value//$'\n'/\\n}"
    value="${value//$'\r'/\\r}"
    value="${value//$'\t'/\\t}"
    printf '"%s"' "$value"
}

fail() {
    printf 'mql-compiler: %s\n' "$*" >&2
    if [[ "$output_format" == "$FORMAT_JSON" ]]; then
        printf '{"type":"error","message":%s}\n' "$(json_string "$*")"
    fi
    exit "$EXIT_USAGE"
}

# The nearest folder at or above $1 whose name (any case) is one of the rest,
# or nothing.
mql_ancestor() {
    local dir="$1" name folder
    shift
    while [[ "$dir" != "/" ]]; do
        name="$(basename "$dir" | tr '[:lower:]' '[:upper:]')"
        for folder in "$@"; do
            if [[ "$name" == "$folder" ]]; then
                printf '%s\n' "$dir"
                return 0
            fi
        done
        dir="$(dirname "$dir")"
    done
}

# The folders whose Include a path can use: MQL4 for a .mq4, MQL5 for a .mq5
# (the same rule the image applies), either for a folder or any other file.
include_folders() {
    case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
        *.mq4) printf '%s\n' MQL4 ;;
        *.mq5) printf '%s\n' MQL5 ;;
        *) printf '%s\n' "${MQL_FOLDERS[@]}" ;;
    esac
}

# The folder to mount so the compiler sees $1 and everything it includes.
mount_root() {
    local path="$1" dir root folders
    dir="$path"
    [[ -d "$path" ]] || dir="$(dirname "$path")"
    folders="$(include_folders "$path")"
    # Word splitting is wanted: folders is a list of plain folder names.
    # shellcheck disable=SC2086
    root="$(mql_ancestor "$dir" $folders)"
    printf '%s\n' "${root:-$dir}"
}

command -v docker >/dev/null 2>&1 || fail "docker is not installed"

image="${MQL_COMPILER_IMAGE:-$PINNED_IMAGE}"
volume="${MQL_COMPILER_VOLUME:-$DEFAULT_VOLUME}"
workdir="$(pwd -P)"

# Paths become absolute and symlink-free: the container holds only the
# mounted folders, at their real host paths. -I folders are mounted as they
# are; sources by mount_root.
args=()
roots=()
compiles=true
targets=0
while (($#)); do
    case "$1" in
        --version | --setup | --update | -h | --help)
            compiles=false
            args+=("$1")
            ;;
        --format)
            args+=("$1")
            if (($# >= 2)); then
                shift
                args+=("$1")
            fi
            ;;
        -I | --include | -I* | --include=*)
            case "$1" in
                -I | --include)
                    (($# >= 2)) || fail "$1 needs a folder"
                    shift
                    folder="$1"
                    ;;
                --include=*) folder="${1#--include=}" ;;
                *) folder="${1#-I}" ;;
            esac
            [[ -d "$folder" ]] || fail "no such include folder: $folder"
            folder="$(realpath "$folder")"
            args+=(-I "$folder")
            roots+=("$folder")
            ;;
        -*) args+=("$1") ;;
        *)
            [[ -e "$1" ]] || fail "no such file or folder: $1"
            path="$(realpath "$1")"
            args+=("$path")
            roots+=("$(mount_root "$path")")
            targets=$((targets + 1))
            ;;
    esac
    shift
done
# No path means the current folder, which still needs its MQL4/MQL5 parent.
if ((targets == 0)) && [[ "$compiles" == true ]]; then
    args+=("$workdir")
    roots+=("$(mount_root "$workdir")")
fi

docker_args=(
    --rm
    # tini as PID 1 passes Ctrl-C and docker stop on to the compiler, which
    # --watch needs to stop, and reaps Wine's leftover processes.
    --init
    --user "$(id -u):$(id -g)"
    -w "$workdir"
    -v "$volume":/cache
)
# One mount per folder; a folder inside one already mounted comes along with
# it. Sorted, a parent always comes before its children.
kept=()
while IFS= read -r root; do
    # Docker refuses to mount / over the container's own root.
    [[ "$root" != "/" ]] || fail "refusing to mount / into the container: name the folders or files to compile"
    for parent in ${kept[@]+"${kept[@]}"}; do
        [[ "$root" == "$parent" || "$root" == "$parent/"* ]] && continue 2
    done
    kept+=("$root")
    docker_args+=(-v "$root:$root")
done < <(printf '%s\n' ${roots[@]+"${roots[@]}"} | sort -u | sed '/^$/d')

# Forward installer overrides only when set, so the image keeps its defaults.
for var in "${FORWARDED_VARS[@]}"; do
    if [[ -n "${!var:-}" ]]; then
        docker_args+=(-e "$var=${!var}")
    fi
done

# The ${x[@]+...} form keeps an empty array safe under set -u on bash 3.2.
exec docker run "${docker_args[@]}" "$image" ${args[@]+"${args[@]}"}
