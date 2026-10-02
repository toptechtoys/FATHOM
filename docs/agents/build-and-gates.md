# Build order and CI gates

Read before you change `.github/`, `scripts/`, `tests/`, `Package.swift`,
`project.yml`, `FathomCLI/`, `Sources/` or the storage engine. The opening rule
of the build order stays in `AGENTS.md`: ship the moat first.

## Milestones

**M1 — the engine.** `FathomKit/Storage`. FTS walk, allocated vs logical, clone
detection via `F_LOG2PHYS_EXT`, sparse via `SEEK_HOLE`, snapshot enumeration.
No UI. Ships when it walks at 15,000 entries per second or better and every
number matches the reference machine fixtures. **The target is entries, not
gigabytes**: a bare `find -xdev /` takes 126.1 s on a 315 GB volume holding 3.1
million entries, so a wall-clock budget measured the disk rather than the
engine. See `RELEASE-GATES.md` gate 1.

**M2 — Explore and Storage.** The two screens that show the engine. First point
where a human can see the product's whole argument.

**M3 — hardware truth.** SMART, SMC, IOReport. Endurance, SSD Health, Sensors.
The NVMe SMART user client is unsupported on an Apple-silicon internal SSD, not
withheld by an entitlement — see *The SMART log is still unrecorded* in
`hardware-testing.md`, and
confirm it on the reference M4 Pro before designing around it.

**M4 — live monitors.** CPU, GPU, Memory, Network, Bluetooth. Cheap once the
IOKit layer from M3 exists.

**M5 — the widget.** Menu bar. Measure its cost the day it first runs, not at
the end.

**M6 — action.** Reclaim, Applications, Cloud, Maintenance. Everything that
moves a file. Trash-only, dry-run first, cost stated.

**M7 — memory over time.** Timeline, Attribution, Weekly digest. These need
history, so they can only be honest after the app has been running for days.

Home and Deep Scan assemble from the others and land last, not first.

## CI gates

**CI runs every gate on arm64, and it is green.** The contrast gate, the
data-source gate, the forbidden-API audit and the privacy-string check all fail
the build for real. The forbidden-API audit greps `Fathom/`, `FathomKit/` and
`FathomBar/` only, so `FathomCLI/`, `Sources/` and `scripts/` are ungated and
were last checked clean by hand — do not read its green as covering them.
Run them locally before you push anyway — they are fast — but remember a local
run cross-compiles from whatever host you are on and CI does not. When the two
disagree, CI is right.
