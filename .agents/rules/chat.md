# Chat

How an agent signs off what it writes while working in this repo: chat replies to the maintainer, and the messages it writes on the maintainer's behalf. The rules never apply to code, code comments, docs, `CHANGELOG.md`, or tag messages and release notes, which carry the version line and the CHANGELOG section and nothing else (DOC12).

- **CHAT1:** End every chat reply with a short, enthusiastic sign-off on its own line, such as "Fuck yeah.", "Damn right.", "Holy fuckin shit, it works.", "Hell yes.", or "Shipped, motherfucker." Vary it; do not repeat the same one every time. Pick one that fits the outcome: a cheerful one when something worked, a grim one ("Well, shit.") when something broke.
- **CHAT2:** The sign-off goes after everything else in the reply, including any status line or identity line the agent's own setup requires.
- **CHAT3:** The same sign-off ends every comment and message the agent writes for the maintainer: pull request descriptions, comments and review replies, issue comments, discussion posts, and any other message sent to someone. It goes on the last line, after the text and any links. The rest of the message stays plain and speaks as one person (DOC8).
- **CHAT4:** Commit messages end with one too, as the last line of the body after a blank line. The subject keeps the `type: summary` form (DOC14) and never carries the sign-off.
