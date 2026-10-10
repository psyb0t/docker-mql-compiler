IMAGE_NAME := psyb0t/mql-compiler
# VERSION is the single source of the release version. The codex plugin
# manifest mirrors it; `make version V=X.Y.Z` updates both.
VERSION    ?= $(shell cat VERSION)
TAG        := v$(VERSION)
DEV_TAG    := dev

# Every tool runs from a pinned image, so the host needs only Docker and Make.
SHELLCHECK_IMAGE := koalaman/shellcheck:v0.11.0@sha256:bb596a0d169b85ddd81d8b6d3a2ff6d5baf5fca10b97f575ebc647c3dff62b3d
SHFMT_IMAGE      := mvdan/shfmt:v3.14.1@sha256:8c06884a35683d8763fba6c0d9484d11a61a96da65f8d497d6f625825a6043f2
HADOLINT_IMAGE   := hadolint/hadolint:v2.15.1@sha256:32dac94127fd60b7b7e3fbfc65e1383b9b5e25c9bfd7b8536de7a539fe68a12d
GITLEAKS_IMAGE   := ghcr.io/gitleaks/gitleaks@sha256:c00b6bd0aeb3071cbcb79009cb16a60dd9e0a7c60e2be9ab65d25e6bc8abbb7f
GRYPE_IMAGE      := anchore/grype:v0.120.1@sha256:e4a44ef45d285b829ce6efe2642980329661bd2d18eab5fc539138d4adaebbbe

SHELL_SCRIPTS := entrypoint.sh wrapper.sh install.sh action/run.sh tests/test.sh tests/unit/lib.sh tests/unit/signature.sh tests/unit/no-result.sh scripts/ci-dockerhub-login.sh
# The toolchain cache the tests reuse between runs (gitignored).
TEST_CACHE    := $(CURDIR)/.testing/cache
GRYPE_SEVERITY ?= high
RUN_AS_ME     := --user $$(id -u):$$(id -g)

.PHONY: help version build install uninstall test test-all lint format sec sec-secrets sec-image sec-dockerfile clean

help: ## Show the documented targets
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-16s\033[0m %s\n", $$1, $$2}'

version: ## Print the version; with V=X.Y.Z set it in VERSION and the codex manifest (no git)
ifeq ($(strip $(V)),)
	@echo $(TAG)
else
	@printf '%s\n' "$$NEW_VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$$' \
		|| { echo "V must be X.Y.Z, got '$$NEW_VERSION'" >&2; exit 1; }
	@printf '%s\n' "$$NEW_VERSION" > VERSION
	@tmp=$$(mktemp) && jq --arg v "$$NEW_VERSION" '.version = $$v' .agents/.codex-plugin/plugin.json > "$$tmp" \
		&& mv "$$tmp" .agents/.codex-plugin/plugin.json
	@echo "version set to v$$NEW_VERSION in VERSION and .agents/.codex-plugin/plugin.json"
endif
version: export NEW_VERSION = $(V)

build: ## Build the image as :dev, :v<VERSION> and :latest
	docker build -t $(IMAGE_NAME):$(DEV_TAG) -t $(IMAGE_NAME):$(TAG) -t $(IMAGE_NAME):latest .

install: build ## Build :dev and install the mql-compiler command from this checkout (~/.local/bin)
	MQL_COMPILER_ENV=dev bash ./install.sh

uninstall: ## Remove the installed mql-compiler command (the toolchain volume is kept)
	bash ./install.sh --uninstall

test: build ## Compile the fixtures with the built image (first run downloads the toolchain into .testing/cache)
	IMAGE=$(IMAGE_NAME):$(DEV_TAG) TEST_CACHE=$(TEST_CACHE) bash tests/test.sh

test-all: build ## make test plus a real release install from Docker Hub (replaces local psyb0t/mql-compiler release images; what CI runs)
	IMAGE=$(IMAGE_NAME):$(DEV_TAG) TEST_CACHE=$(TEST_CACHE) MQL_COMPILER_TEST_RELEASE_INSTALL=1 bash tests/test.sh

lint: ## shellcheck + shfmt on the scripts, hadolint on the Dockerfile
	docker run --rm -v "$(CURDIR)":/mnt:ro -w /mnt $(SHELLCHECK_IMAGE) $(SHELL_SCRIPTS)
	docker run --rm -v "$(CURDIR)":/mnt:ro -w /mnt $(SHFMT_IMAGE) -d -i 4 -ci $(SHELL_SCRIPTS)
	docker run --rm -i $(HADOLINT_IMAGE) hadolint - < Dockerfile

format: ## Rewrite the scripts with shfmt
	docker run --rm $(RUN_AS_ME) -v "$(CURDIR)":/mnt -w /mnt $(SHFMT_IMAGE) -w -i 4 -ci $(SHELL_SCRIPTS)

sec: sec-secrets sec-dockerfile sec-image ## Every security check: secrets, Dockerfile, image vulnerabilities

sec-secrets: ## Scan the working tree for secrets with gitleaks
	docker run --rm --network none -v "$(CURDIR)":/repo:ro $(GITLEAKS_IMAGE) dir /repo --config /repo/.gitleaks.toml --no-banner --redact

sec-dockerfile: ## Lint the Dockerfile for security and correctness with hadolint
	docker run --rm -i $(HADOLINT_IMAGE) hadolint --failure-threshold warning - < Dockerfile

sec-image: build ## Scan the built image for known vulnerabilities with grype (GRYPE_SEVERITY, default high)
	docker run --rm -v /var/run/docker.sock:/var/run/docker.sock:ro $(GRYPE_IMAGE) \
		$(IMAGE_NAME):$(DEV_TAG) --only-fixed --fail-on $(GRYPE_SEVERITY)

clean: ## Remove the built images and the test toolchain cache
	docker rmi $(IMAGE_NAME):$(DEV_TAG) $(IMAGE_NAME):$(TAG) $(IMAGE_NAME):latest 2>/dev/null || true # absent images are fine
	rm -rf .testing
