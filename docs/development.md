---
title: "Development"
description: "Build, test and lint mql-compiler from a checkout with Make and Docker, build this documentation site, and see what the CI pipeline runs."
nav_order: 7
---

# Development

```bash
make build      # build psyb0t/mql-compiler:dev, :v<VERSION> and :latest
make test       # compile tests/fixtures with the built image and check the results
make test-all   # make test plus a real release install from Docker Hub
make test-ci    # make test-all under a 25-minute limit, printing the compiler log on failure (what CI runs)
make lint       # shellcheck and shfmt on the scripts, hadolint on the Dockerfile
make format     # rewrite the scripts with shfmt
make sec        # gitleaks secrets scan, hadolint, grype vulnerability scan of the image
make install    # build :dev and install the command from this checkout
make uninstall  # remove the installed command
make version    # print the version; V=X.Y.Z sets it
make seccomp    # regenerate seccomp/wine.json from Docker's pinned default profile plus userfaultfd
make docs       # build this documentation site into .testing/docs-site
make help       # every target
```

Every tool runs from a digest-pinned image, so the host needs Docker, Make, Bash, `curl` and `jq` and nothing else. The targets live in the [`Makefile`](https://github.com/psyb0t/docker-mql-compiler/blob/master/Makefile).

## Tests

[`tests/test.sh`](https://github.com/psyb0t/docker-mql-compiler/blob/master/tests/test.sh) is an end-to-end suite. It runs the built image by hand and through [`wrapper.sh`](https://github.com/psyb0t/docker-mql-compiler/blob/master/wrapper.sh), the host command, against copies of the MQL4 and MQL5 trees in [`tests/fixtures/`](https://github.com/psyb0t/docker-mql-compiler/tree/master/tests/fixtures), and checks stdout, stderr, exit codes and the files written. `make test` installs the real toolchain into `.testing/cache` the first time (about a minute and a half) and reuses it after. It also runs a real `--update`, so it reinstalls the toolchain once per run, and covers the installer, the GitHub Action's script and the failure paths. A run takes about five minutes with a warm cache. The scripts in [`tests/unit/`](https://github.com/psyb0t/docker-mql-compiler/tree/master/tests/unit) test entrypoint functions inside the image with one dependency stubbed.

`make test-all` adds a real release install from Docker Hub, which replaces your local `psyb0t/mql-compiler` release images.

## CI

Every push runs [`.github/workflows/pipeline.yml`](https://github.com/psyb0t/docker-mql-compiler/blob/master/.github/workflows/pipeline.yml):

- the `code` job runs `make lint` and `make test-ci` through the shared code workflow, with no credentials;
- the `action` job builds the image and runs the GitHub Action in this repository against it (`uses: ./`), once on a good file and once on a broken one;
- after both pass on `master`, the image workflow builds the amd64 image, pushes `:latest` and `:sha-<commit>`, and reports a Grype scan to the Security tab;
- a `v*` tag waits for that commit's `master` run to succeed, promotes the same image to `:vX.Y.Z` without rebuilding, cuts the GitHub release from the tag message, and publishes the [skill](https://github.com/psyb0t/docker-mql-compiler/blob/master/.agents/skills/mql-compiler/SKILL.md) to ClawHub;
- the version and license badges refresh on `master` and on tags.

## Documentation

This site is the `docs/` directory, built by GitHub Pages with Jekyll and the Just the Docs theme. Every page needs front matter with a `title` and a one-sentence `description`. Link between pages with relative `.md` paths, and link files outside `docs/` with full `https://github.com/psyb0t/docker-mql-compiler/blob/master/...` URLs, because a `../` link breaks on the site. `make docs` builds the site with GitHub's own build image into `.testing/docs-site`, so you can check a change before pushing it.
