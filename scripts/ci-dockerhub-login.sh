#!/bin/bash
# Logs the CI runner in to Docker Hub before the suite pulls its base images.
# Anonymous pulls are rate limited per runner IP, which GitHub's hosted
# runners share, so without a login the jobs die on 429 before any test runs.
#
# Docker Hub's token endpoint sometimes times out from one runner while it
# answers everyone else, so this retries with a growing pause. When every
# attempt fails the job carries on with anonymous pulls and a warning: a
# missed login is no worse than having none.
#
# Reads DOCKERHUB_USERNAME and DOCKERHUB_TOKEN. The token reaches docker on
# stdin and is never printed.

set -euo pipefail

readonly ATTEMPTS=5
readonly BACKOFF_STEP_SECONDS=15

log() {
    local level="$1"
    shift
    printf '[%s] [%s] [dockerhub-login] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$level" "$*" >&2
}

# A GitHub Actions annotation, so the fallback shows on the run summary.
annotate_warning() {
    printf '::warning::%s\n' "$*"
}

if [[ -z "${DOCKERHUB_USERNAME:-}" || -z "${DOCKERHUB_TOKEN:-}" ]]; then
    log WARN "DOCKERHUB_USERNAME or DOCKERHUB_TOKEN is empty, pulling anonymously"
    annotate_warning "Docker Hub credentials missing, pulling anonymously"
    exit 0
fi

for ((attempt = 1; attempt <= ATTEMPTS; attempt++)); do
    if printf '%s' "$DOCKERHUB_TOKEN" | docker login --username "$DOCKERHUB_USERNAME" --password-stdin >/dev/null; then
        log INFO "logged in to Docker Hub attempt=$attempt"
        exit 0
    fi
    log WARN "Docker Hub login failed attempt=$attempt of=$ATTEMPTS"
    if ((attempt < ATTEMPTS)); then
        sleep $((attempt * BACKOFF_STEP_SECONDS))
    fi
done

log WARN "Docker Hub login failed every attempt, pulling anonymously attempts=$ATTEMPTS"
annotate_warning "Docker Hub login failed $ATTEMPTS times, pulling anonymously"
