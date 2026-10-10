#!/bin/bash
# mql-compiler installer: pins a release image and installs the
# `mql-compiler` command. The command is a single file; there is no config
# folder, and the toolchain cache lives in a Docker volume.
#
#   curl -fsSL https://raw.githubusercontent.com/psyb0t/docker-mql-compiler/master/install.sh | bash
#   curl -fsSL .../install.sh | sudo bash -s -- --system
#
# Options:
#   --user       install to ~/.local/bin (the default when not root)
#   --system     install to /usr/local/bin (the default as root)
#   --rolling    pin :latest instead of the newest release tag
#   --uninstall  remove the command and its pinned image (the toolchain
#                volume is kept)
#
# MQL_COMPILER_ENV=dev installs the command from this checkout and pins the
# locally built :dev image (what `make install` does).
set -euo pipefail

readonly INSTALL_LOG_FILE="${TMPDIR:-/tmp}/mql-compiler-install.log"
readonly COMMAND_NAME="mql-compiler"
readonly SYSTEM_INSTALL_DIR="/usr/local/bin"
readonly USER_INSTALL_DIR="$HOME/.local/bin"
readonly WRAPPER_MARKER="mql-compiler-managed-command"
readonly IMAGE_REPO="psyb0t/mql-compiler"
readonly ROLLING_IMAGE="$IMAGE_REPO:latest"
readonly DEVELOPMENT_IMAGE="$IMAGE_REPO:dev"
readonly DEVELOPMENT_ENVIRONMENT="dev"
readonly GITHUB_API_LATEST="https://api.github.com/repos/psyb0t/docker-mql-compiler/releases/latest"
readonly WRAPPER_URL="https://raw.githubusercontent.com/psyb0t/docker-mql-compiler/master/wrapper.sh"
readonly CACHE_VOLUME="mql-compiler-cache"
# shellcheck disable=SC2016 # must reach the rc file unexpanded
readonly USER_PATH_SNIPPET='export PATH="$HOME/.local/bin:$PATH"'

MODE=""
ROLLING=0
UNINSTALL=0
INSTALL_PATH=""
WRAPPER_TEMPORARY_FILE=""

say() { printf '==> %s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
fail() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

trap 'printf "error: install failed, see %s\n" "$INSTALL_LOG_FILE" >&2' ERR
trap 'rm -f "$WRAPPER_TEMPORARY_FILE"' EXIT
exec > >(tee -a "$INSTALL_LOG_FILE") 2>&1

development_enabled() {
    case "${MQL_COMPILER_ENV:-}" in
        "") return 1 ;;
        "$DEVELOPMENT_ENVIRONMENT") return 0 ;;
        *) fail "MQL_COMPILER_ENV must be dev when set" ;;
    esac
}

resolve_mode() {
    if [[ -z "$MODE" ]]; then
        if ((EUID == 0)); then MODE="system"; else MODE="user"; fi
    fi
    case "$MODE" in
        system)
            ((EUID == 0)) || fail "the system-wide install needs root: re-run with sudo, or use --user"
            INSTALL_PATH="$SYSTEM_INSTALL_DIR/$COMMAND_NAME"
            ;;
        user)
            ((EUID != 0)) || fail "the per-user install must not run as root: run it as your normal account, or use --system"
            INSTALL_PATH="$USER_INSTALL_DIR/$COMMAND_NAME"
            ;;
    esac
}

resolve_latest_tag() {
    local tag
    tag="$(curl -fsSL "$GITHUB_API_LATEST" | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -n1)"
    [[ -n "$tag" ]] || fail "could not resolve the latest mql-compiler release tag"
    printf '%s\n' "$tag"
}

resolve_image() {
    if development_enabled; then
        printf '%s\n' "$DEVELOPMENT_IMAGE"
        return
    fi
    if ((ROLLING)); then
        printf '%s\n' "$ROLLING_IMAGE"
        return
    fi
    printf '%s:%s\n' "$IMAGE_REPO" "$(resolve_latest_tag)"
}

prepare_image() {
    local image="$1"
    if development_enabled; then
        docker image inspect "$image" >/dev/null 2>&1 ||
            fail "MQL_COMPILER_ENV=dev needs the local image $image: run make build first"
        return
    fi
    docker pull "$image"
}

# The image the installed command is pinned to now, if one is installed.
installed_image() {
    [[ -f "$INSTALL_PATH" ]] || return 0
    sed -n 's/^readonly PINNED_IMAGE="\(.*\)"$/\1/p' "$INSTALL_PATH" | head -n1
}

ensure_managed() {
    if [[ -e "$INSTALL_PATH" ]] && ! grep -Fq "$WRAPPER_MARKER" "$INSTALL_PATH"; then
        fail "$INSTALL_PATH already exists and was not installed by this installer"
    fi
}

write_command() {
    local image="$1" source_dir
    ensure_managed
    install -d "$(dirname "$INSTALL_PATH")"
    WRAPPER_TEMPORARY_FILE="$(mktemp)"
    if development_enabled; then
        source_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        [[ -f "$source_dir/wrapper.sh" ]] || fail "MQL_COMPILER_ENV=dev must run install.sh from the checkout"
        cp "$source_dir/wrapper.sh" "$WRAPPER_TEMPORARY_FILE"
    else
        curl -fsSL "$WRAPPER_URL" >"$WRAPPER_TEMPORARY_FILE"
    fi
    grep -Fq "$WRAPPER_MARKER" "$WRAPPER_TEMPORARY_FILE" || fail "the downloaded wrapper is not an mql-compiler command"
    sed -i "s|^readonly PINNED_IMAGE=.*|readonly PINNED_IMAGE=\"$image\"|" "$WRAPPER_TEMPORARY_FILE"
    bash -n "$WRAPPER_TEMPORARY_FILE"
    install -m 0755 "$WRAPPER_TEMPORARY_FILE" "$INSTALL_PATH"
    say "installed $INSTALL_PATH (pinned to $image)"
}

warn_user_path() {
    [[ "$MODE" == "user" ]] || return 0
    case ":$PATH:" in
        *":$USER_INSTALL_DIR:"*) return 0 ;;
    esac
    warn "$USER_INSTALL_DIR is not on your PATH, so the $COMMAND_NAME command will not be found yet"
    printf '\nAdd it to your shell, then restart the shell (or source the file):\n\n'
    printf "  bash:  echo '%s' >> ~/.bashrc && source ~/.bashrc\n" "$USER_PATH_SNIPPET"
    printf "  zsh:   echo '%s' >> ~/.zshrc && source ~/.zshrc\n\n" "$USER_PATH_SNIPPET"
}

drop_previous_image() {
    local previous="$1" current="$2"
    [[ -n "$previous" && "$previous" != "$current" ]] || return 0
    if docker image rm "$previous" >/dev/null 2>&1; then
        say "removed the previous image $previous"
        return
    fi
    warn "kept the previous image $previous (still in use)"
}

# Uninstalling removes the image the command was pinned to, except the local
# :dev build, which belongs to the checkout rather than the install.
drop_pinned_image() {
    local image="$1"
    [[ -n "$image" && "$image" != "$DEVELOPMENT_IMAGE" ]] || return 0
    if ! command -v docker >/dev/null 2>&1; then
        warn "docker is not installed, so the image $image was not removed"
        return
    fi
    # "No such image" is fine here: the image may already be gone.
    if docker image rm "$image" >/dev/null 2>&1; then
        say "removed the image $image"
        return
    fi
    warn "kept the image $image (in use, or already gone)"
}

uninstall() {
    ensure_managed
    if [[ ! -e "$INSTALL_PATH" ]]; then
        say "nothing installed at $INSTALL_PATH"
        return
    fi
    local image
    image="$(installed_image)"
    rm -f "$INSTALL_PATH"
    say "removed $INSTALL_PATH"
    drop_pinned_image "$image"
    printf '\nThe toolchain volume is kept, since other users on this machine may share it. To free its disk space too:\n\n  docker volume rm %s\n\n' "$CACHE_VOLUME"
}

main() {
    local arg
    for arg in "$@"; do
        case "$arg" in
            --system) MODE="system" ;;
            --user) MODE="user" ;;
            --rolling) ROLLING=1 ;;
            --uninstall) UNINSTALL=1 ;;
            *) fail "unknown argument: $arg (supported: --user, --system, --rolling, --uninstall)" ;;
        esac
    done

    resolve_mode
    if ((UNINSTALL)); then
        uninstall
        return
    fi
    docker info >/dev/null 2>&1 ||
        fail "cannot talk to Docker: is the daemon running, and is your account in the docker group?"

    say "installing $COMMAND_NAME ($MODE mode)"
    local previous image
    previous="$(installed_image)"
    image="$(resolve_image)"
    say "pinning to $image"
    prepare_image "$image"
    write_command "$image"
    if ! development_enabled; then
        drop_previous_image "$previous" "$image"
        warn_user_path
    fi

    printf '\nRun %s in a folder with .mq4/.mq5 files. The first run downloads\n' "$COMMAND_NAME"
    printf 'and installs MT4 and MT5 into the %s volume (about a minute and a half).\n' "$CACHE_VOLUME"
}

main "$@"
