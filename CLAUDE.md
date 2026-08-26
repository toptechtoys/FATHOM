# CLAUDE.md

The build contract for this repository is **AGENTS.md**. Read it before writing
any code. It is shared with Codex so there is one source of truth, not two.

Quick orientation, in reading order:

1. `AGENTS.md` — non-negotiables, repo layout, build order, working agreements
2. `docs/FATHOM-DATA-SOURCES.md` — every number and the exact API behind it
3. `docs/FATHOM-PRD.md` — what ships and why
4. `docs/FATHOM-DESIGN.md` — the locked design system
5. `docs/fathom-app.html` — the visual spec, open it in a browser
6. `docs/RELEASE-GATES.md` — everything still outstanding lives here

The interface is implemented and **has now been run and looked at** — as an
x86_64 build on an Intel Mac, which shows every layout and no Apple-silicon
reading. It found two defects in the first ten minutes that the compiler, the
contrast gate and the arithmetic had all passed, and it drove the owner's
native-feel pass of 25 August. Read `AGENTS.md` §Build order before adding to
it, and run it when you change a screen.

The one rule that overrides everything: **never render a number you cannot trace
to a row in FATHOM-DATA-SOURCES.md.** If you need a new number, add the row
first, with its syscall or IOKit key, and get it reviewed. `DataSource` cases
are checked against that document by `scripts/check-data-sources.py`, which runs
in CI, so an undocumented case fails the build rather than a review.
