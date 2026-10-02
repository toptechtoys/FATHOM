# CLAUDE.md

The build contract for this repository is **AGENTS.md**, imported here so it is
always loaded. It is shared with Codex so there is one source of truth, not two.

@AGENTS.md

`.claude/rules/` holds path-scoped rules: each loads when you read files it
covers and names the `docs/agents/` note to read before you change them.

The one rule that overrides everything: **never render a number you cannot trace
to a row in FATHOM-DATA-SOURCES.md.** If you need a new number, add the row
first, with its syscall or IOKit key, and get it reviewed. `DataSource` cases
are checked against that document by `scripts/check-data-sources.py`, which runs
in CI, so an undocumented case fails the build rather than a review.
