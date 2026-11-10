# Docs and release rules

Prefix: DOC.

## Docs move with the code

- **DOC1:** A change that alters behaviour a user or agent can see updates the docs in the same change. The owners:
  - project overview, quick start and the links into the docs site: `README.md`;
  - the docs site's home page and page index: `docs/index.md`;
  - what a run does, paths, includes, options, the JSON output and exit codes: `docs/usage.md`;
  - installation, upgrades and environment variables: `docs/installation.md`;
  - Wine, signature checks, cache layout and mounts: `docs/architecture.md`;
  - the GitHub Action's inputs and outputs and manual Docker runs: `docs/ci-and-docker.md`;
  - error messages, their causes and fixes: `docs/troubleshooting.md`;
  - the GitHub Action's own metadata: the `description` fields in `action.yml`;
  - the same facts for agents: `.agents/skills/mql-compiler/SKILL.md`;
  - installing, upgrading, the first run and troubleshooting: `.agents/skills/mql-compiler/references/installation.md`;
  - the in-image summary: `usage()` in `entrypoint.sh` (`--help`) and the header comments of `entrypoint.sh` and `wrapper.sh`;
  - internals and landmines: `AGENTS.md` and `.agents/rules/`;
  - Make targets, the test suite and CI: the `##` comments in the `Makefile` (`make help`) and `docs/development.md`.
- **DOC2:** README, SKILL.md, `--help` and AGENTS.md must not contradict each other. When one changes a fact, check the other three for it.

## Prose style

- **DOC6:** Each Markdown paragraph is one source line.
- **DOC7:** The README and the pages in `docs/` use a crude, joking voice; keep it when editing them. SKILL.md, its `references/installation.md`, AGENTS.md, the rules, the CHANGELOG and comments use a plain one.

## CHANGELOG and versions

- **DOC9:** A `CHANGELOG.md` release heading is `## vX.Y.Z, YYYY-MM-DD`.
- **DOC11:** `make version V=X.Y.Z` sets the version in `VERSION` and `.agents/.codex-plugin/plugin.json`. `.agents/.claude-plugin/plugin.json` has no version field.
- **DOC12:** Each release is an annotated tag `vX.Y.Z` on the release commit. The tag message is the version on the first line, a blank line, then that release's CHANGELOG bullets.
- **DOC13:** Every push runs `.github/workflows/pipeline.yml`: the `code` job (`make lint` and `make test-ci` through the reusable code workflow) and the `action` job (the Action in this repository against an image built from the commit). On `master`, the reusable docker-image workflow then builds and pushes `psyb0t/mql-compiler:latest` and `:sha-<commit>` (amd64 only, Grype scan reported to the Security tab). A `v*` tag runs no checks: it waits for that commit's `master` run to succeed (`wait`), promotes the same digest to `:vX.Y.Z` (`docker-promote`), cuts the GitHub release from the tag message (`release`), and then publishes the skill to ClawHub. `install.sh` pins the newest release tag, so a release is what users get.

## Docs site

- **DOC16:** `docs/` is the GitHub Pages site at https://psyb0t.github.io/docker-mql-compiler/, built from `master`'s `/docs` by Jekyll with the Just the Docs theme. Pages link to each other with relative `.md` paths; files outside `docs/` are linked with full `https://github.com/psyb0t/docker-mql-compiler/blob/master/...` URLs, because a `../` link breaks on the site. The README links into the site with full site URLs, never with relative `docs/` paths, because Docker Hub shows the README too.
- **DOC17:** A docs change builds with `make docs` (GitHub Pages' own build image, output in `.testing/docs-site`) before it is called done, and a code block holding `{{` or `{%` is wrapped in `<!-- {% raw %} -->` and `<!-- {% endraw %} -->` so Liquid leaves it alone.
