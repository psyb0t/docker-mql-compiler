# Project rules

Rules for agents and people changing docker-mql-compiler. Each file covers one topic, each rule is meant to be checkable, and where a test, lint or script enforces a rule the rule names it. Start with [AGENTS.md](../../AGENTS.md) for the project overview.

Every rule starts with a bold ID: one prefix per file and a number counted from 1 in that file. Cite rules by ID (for example "TST3") in reviews, commits and code comments. IDs are never reused or renumbered: a removed rule's ID stays retired, and a new rule takes the next free number in its file.

| File | Prefix | Covers |
| --- | --- | --- |
| [architecture.md](architecture.md) | ARC | The three scripts and what each owns, the run order, mounts, the include root, the cache. |
| [bash-code.md](bash-code.md) | SH | Bash style as practised here: strict mode, named constants, logging, stdout versus stderr, silenced commands. |
| [testing.md](testing.md) | TST | The end-to-end suite, fixtures, regression tests, the test cache. |
| [security.md](security.md) | SEC | Installer signature checks, the container's privileges, pins, secrets, outside contributions. |
| [docs-and-releases.md](docs-and-releases.md) | DOC | Docs kept in step with code, prose style, CHANGELOG, versions, tags, CI publishing. |
| [chat.md](chat.md) | CHAT | How an agent signs off its chat replies, PR, issue and discussion comments, messages and commit messages. |

When a rule here and the code disagree, the code and its tests win; fix the rule in the same change.
