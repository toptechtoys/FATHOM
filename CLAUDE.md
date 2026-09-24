# CLAUDE.md

The build contract for this repository is **AGENTS.md**, imported here so it is
always loaded. It is shared with Codex so there is one source of truth, not two.

@AGENTS.md

Quick orientation, in reading order:

1. `AGENTS.md` — non-negotiables, repo layout, build order, working agreements
2. `docs/FATHOM-DATA-SOURCES.md` — every number and the exact API behind it
3. `docs/FATHOM-PRD.md` — what ships and why
4. `docs/FATHOM-DESIGN.md` — the locked design system
5. `docs/fathom-app.html` — the visual spec, open it in a browser
6. `docs/RELEASE-GATES.md` — everything still outstanding lives here

Run the app when you change a screen. `AGENTS.md` §Build order says how to build
it on an Intel host and what that build can and cannot show.

The one rule that overrides everything: **never render a number you cannot trace
to a row in FATHOM-DATA-SOURCES.md.** If you need a new number, add the row
first, with its syscall or IOKit key, and get it reviewed. `DataSource` cases
are checked against that document by `scripts/check-data-sources.py`, which runs
in CI, so an undocumented case fails the build rather than a review.
