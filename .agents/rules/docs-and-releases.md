# Docs and release rules

Prefix: DOC.

## Docs move with the code

- **DOC1:** A change that alters behaviour a user or agent can see updates the docs in the same change. The owners:
  - what a run does, paths, includes, output, exit codes, environment variables: `README.md`;
  - the same facts for agents: `.agents/skills/mql-compiler/SKILL.md`;
  - installing, upgrading, the first run and troubleshooting: `.agents/skills/mql-compiler/references/installation.md`;
  - the in-image summary: `usage()` in `entrypoint.sh` (`--help`) and the header comments of `entrypoint.sh` and `wrapper.sh`;
  - internals and landmines: `AGENTS.md` and `.agents/rules/`;
  - Make targets: the `##` comments in the `Makefile` (`make help`) and the README's development section.
- **DOC2:** README, SKILL.md, `--help` and AGENTS.md must not contradict each other. When one changes a fact, check the other three for it.
- **DOC3:** A changed project convention updates `AGENTS.md` or the matching file in `.agents/rules/` in the same change.

## Prose style

- **DOC4:** No em dashes or en dashes anywhere: docs, README, CHANGELOG, rules, comments, commit messages, tag messages. Use a comma, a colon, parentheses or a new sentence.
- **DOC5:** Plain, specific words. Say what happens with real file names, flags and numbers. No filler or marketing words ("leverage", "robust", "seamless", "delve", "powerful", "simply").
- **DOC6:** Headings are sentence case. Each Markdown paragraph is one source line.
- **DOC7:** The README uses a crude, joking voice; keep it when editing the README. SKILL.md, installation.md, AGENTS.md, the rules, the CHANGELOG and comments use a plain one.
- **DOC8:** Anything written to other people (release notes, issue and PR replies) speaks as one person: "I", never "we", "our" or "the team".

## CHANGELOG and versions

- **DOC9:** Every user-visible change gets a `CHANGELOG.md` entry. A new release goes at the top as `## vX.Y.Z, YYYY-MM-DD` followed by bullets written for the user: what they will see, then what changed. A fix says what went wrong and when before what happens now.
- **DOC10:** Versions follow semver pre-1.0 as the CHANGELOG intro states: a patch for docs, build and fixes, a minor for new behaviour, with breaking changes called out.
- **DOC11:** `make version V=X.Y.Z` sets the version in `VERSION` and `.agents/.codex-plugin/plugin.json`. `.agents/.claude-plugin/plugin.json` has no version field.
- **DOC12:** Each release is an annotated tag `vX.Y.Z` on the release commit. The tag message is the version on the first line, a blank line, then that release's CHANGELOG bullets.
- **DOC13:** Every push runs `.github/workflows/pipeline.yml`: `lint` and `test`, then the reusable docker-image workflow (amd64 only, Grype scan reported to the Security tab) builds and pushes `psyb0t/mql-compiler` and, for a `v*` tag, the GitHub release. On a tag, the skill is published to ClawHub after the image succeeds. `install.sh` pins the newest release tag, so a release is what users get.
- **DOC14:** Commit subjects follow `type: summary` as in the history (`feat: ...`, `fix: ...`, `docs: ...`), with a body that explains what changed and why.
- **DOC15:** The maintainer cuts releases; an agent working for the maintainer releases only through the maintainer's release tooling, never with raw `git commit`, `git push` or `git tag`. Contributors send pull requests and leave versions, tags and the CHANGELOG release heading to the maintainer. Never commit, tag, push, publish or touch issues unless the user asked for that specific action in the current turn, and never put `Closes #N`, `Fixes #N` or `Resolves #N` in a commit, PR or tag unless the user said to close that issue.
