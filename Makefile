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

SHELL_SCRIPTS := entrypoint.sh wrapper.sh install.sh action/run.sh tests/test.sh tests/unit/lib.sh tests/unit/signature.sh tests/unit/no-result.sh tests/unit/install-timeout.sh scripts/ci-dockerhub-login.sh scripts/make-seccomp.sh
# The toolchain cache the tests reuse between runs (gitignored).
TEST_CACHE    := $(CURDIR)/.testing/cache
GRYPE_SEVERITY ?= high
RUN_AS_ME     := --user $$(id -u):$$(id -g)
# Docker's default seccomp profile (moby/profiles seccomp/v0.3.0, the one
# Docker 29 builds in), pinned by checksum; `make seccomp` adds userfaultfd.
SECCOMP_BASE_URL    := https://raw.githubusercontent.com/moby/profiles/seccomp/v0.3.0/seccomp/default.json
SECCOMP_BASE_SHA256 := 6416b47770785a41ac59073cdc77d9fe98517df2799dc83ef207e622de3053f6
SECCOMP_PROFILE     := seccomp/wine.json
# A passing CI test run takes about six minutes, the first install included.
# Without a limit, v0.5.1's runs sat in a first install that never finished
# for six hours before GitHub cancelled them.
TEST_CI_TIMEOUT     := 25m
# GitHub Pages' own Jekyll build image, so the local site matches the live one.
JEKYLL_IMAGE        := ghcr.io/actions/jekyll-build-pages:v1.0.13@sha256:6791ebfd912185ed59bfb5fb102664fa872496b79f87ff8b9cfba292a7345041
DOCS_SITE           := .testing/docs-site

.PHONY: help version build seccomp install uninstall test test-all test-ci docs lint format sec sec-secrets sec-image sec-dockerfile clean

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

seccomp: build ## Regenerate seccomp/wine.json: Docker's default profile plus userfaultfd, which Wine needs under Linux 7.0
	docker run --rm $(RUN_AS_ME) -v "$(CURDIR)":/repo -w /repo --entrypoint bash $(IMAGE_NAME):$(DEV_TAG) \
		scripts/make-seccomp.sh "$(SECCOMP_BASE_URL)" "$(SECCOMP_BASE_SHA256)" "$(SECCOMP_PROFILE)"

install: build ## Build :dev and install the mql-compiler command from this checkout (~/.local/bin)
	MQL_COMPILER_ENV=dev bash ./install.sh

uninstall: ## Remove the installed mql-compiler command (the toolchain volume is kept)
	bash ./install.sh --uninstall

test: build ## Compile the fixtures with the built image (first run downloads the toolchain into .testing/cache)
	IMAGE=$(IMAGE_NAME):$(DEV_TAG) TEST_CACHE=$(TEST_CACHE) bash tests/test.sh

test-all: build ## make test plus a real release install from Docker Hub (replaces local psyb0t/mql-compiler release images; CI runs it through test-ci)
	IMAGE=$(IMAGE_NAME):$(DEV_TAG) TEST_CACHE=$(TEST_CACHE) MQL_COMPILER_TEST_RELEASE_INSTALL=1 bash tests/test.sh

# The suite hides the compiler's stderr; its own copy of the last run is what
# says where a failed or stuck setup stopped, so print it when the run fails.
test-ci: ## make test-all under a 25-minute limit, printing the compiler log on failure (what CI runs)
	@status=0; \
	timeout $(TEST_CI_TIMEOUT) $(MAKE) --no-print-directory test-all || status=$$?; \
	if [ "$$status" -ne 0 ]; then \
		for log in $(TEST_CACHE)/uid-*/logs/last-run.log; do \
			[ -f "$$log" ] || continue; \
			echo "== $$log"; \
			cat "$$log"; \
		done; \
	fi; \
	exit "$$status"

docs: ## Build the documentation site into .testing/docs-site with GitHub Pages' Jekyll image
	@mkdir -p "$(DOCS_SITE)"
	docker run --rm \
		--user "$$(id -u):$$(id -g)" \
		-e HOME=/tmp \
		-e GITHUB_WORKSPACE=/work \
		-e GITHUB_REPOSITORY=psyb0t/docker-mql-compiler \
		-e INPUT_SOURCE=docs \
		-e INPUT_DESTINATION="$(DOCS_SITE)" \
		-e INPUT_VERBOSE=false \
		-v "$(CURDIR):/work" \
		$(JEKYLL_IMAGE)

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
