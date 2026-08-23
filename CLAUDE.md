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

The interface is implemented and **has never been seen running**. It was
verified by compiler, by the contrast gate and by arithmetic. Before adding to
it, read `AGENTS.md` §Build order on why that matters.

The one rule that overrides everything: **never render a number you cannot trace
to a row in FATHOM-DATA-SOURCES.md.** If you need a new number, add the row
first, with its syscall or IOKit key, and get it reviewed.
