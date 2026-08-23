# AGENTS.md — FATHOM

**Read this before writing any code.** Claude Code and Codex both read this file
automatically. It is the contract for the build.

---

## What you are building

A macOS utility for Apple silicon that tells the truth about storage, memory and
SSD endurance. Native SwiftUI app plus a menu bar widget. Ships outside the Mac
App Store, Developer ID signed and notarised.

**One sentence:** every other Mac utility shows you a number it cannot justify;
FATHOM shows you two numbers and names the one it does not know.

---

## Non-negotiables

These are product law. A pull request that violates one does not merge, no
matter how good the code is.

1. **Never invent a number.** If a value cannot be traced to a row in
   `FATHOM-DATA-SOURCES.md`, it does not render. Add the row first.
2. **Three states for every value: known, not published, not attributable.**
   Every view must handle all three. Not-published rows render greyed with the
   words *not published*. Unattributed remainders get their own row, never
   redistributed to make percentages total 100.
3. **Two numbers on every file.** *On disk* and *freed if deleted*. The second is
   the product. Sparse files, clones, snapshots and open file descriptors all
   make it differ from the first.
4. **Nothing is deleted.** Everything moves to the Trash via
   `NSFileManager.trashItem`. No `unlink`. No exceptions, including caches.
5. **Every action states its cost before it runs.** "Frees 48.2 GB, costs one
   Xcode rebuild, about 8 minutes."
6. **No health score.** No letter grade, no percentage of overall wellbeing, no
   green tick. The Home screen is allowed to say *nothing is wrong*.
7. **No manufactured urgency.** No red badges for routine state, no countdown, no
   "your Mac is at risk". The weekly digest is allowed to say nothing.
8. **Idle cost is a shipped number, and the widget measures it.** Menu bar
   widget: ≤ 0.2% CPU with four items, and 0.5% blocks the release. `FathomBar`
   reads `proc_pid_rusage` on the loop that costs it and publishes the figure
   with the item count it was taken with; the app displays that, never the
   budget. Energy impact ≤ 2.1, and 4.0 blocks — but **the app does not display
   it**: the composite needs root, and FATHOM does not take root to report on
   itself. It stays a manual Activity Monitor reading in `RELEASE-GATES.md`.
9. **One outbound request, ever.** Public IP lookup, cached ≥ 15 minutes,
   disableable, no identifier. Nothing else leaves the machine. No analytics, no
   crash telemetry without explicit opt-in.
10. **Read-only means read-only.** The SSD Health screen cannot mutate anything.

---

## Repository layout

```
Fathom.xcodeproj
Fathom/                 SwiftUI app
  App/                  entry point, window, navigation
  Design/               tokens, worlds, plate, grain, focus ring, fonts
  Sections/             one folder per section, 20 total
  Components/           rail, readout grid, panel, and the 13 panel types
FathomKit/              all measurement, no UI, fully testable
  Storage/              FTS walk, two-number engine, clone + sparse detection
  Hardware/             SMART, SMC, IOReport, IOKit
  System/               CPU, GPU, memory, network, bluetooth
  Model/                Measurement<T> and the three-state type
FathomBar/              menu bar widget target
FathomKitTests/         fixtures from the reference machine
scripts/
  check-contrast.py     the contrast gate; runs in CI
  build-prototype.py    regenerates docs/fathom-app.html
docs/
  FATHOM-PRD.md
  FATHOM-DESIGN.md
  FATHOM-DATA-SOURCES.md
  RELEASE-GATES.md      what the reference machine must still prove
  fathom-app.html       the locked visual reference
```

**Presentation logic that makes a claim belongs in FathomKit, not beside the
view.** A treemap whose areas are wrong misrepresents a volume as confidently as
a wrong number does, so `TreemapLayout` is tested. So are `SampleHistory`, which
decides how a chart draws a second nobody measured, and `FindingEngine`, which
decides what is worth saying at all. The rule of thumb: if getting it wrong
would make the product lie, it is measurement, whatever it looks like.

---

## The central type

Everything measured flows through this. It is what makes rule 2 enforceable by
the compiler rather than by review.

```swift
enum Measurement<T> {
    case known(T, source: DataSource)
    case notPublished(reason: String)
    case notAttributable(measured: T, explained: T)
}
```

`DataSource` names the syscall or IOKit key. The UI can show provenance on
demand, and every screenshot in a bug report can be traced to an API.

Do not add a `.unknown` case. Do not add optional-returning convenience
accessors that collapse the three states into one. That collapse is exactly how
honest tools become dishonest.

Transforms that *preserve* all three are fine and exist: `map` carries a
not-published reason through a unit conversion and transforms both halves of an
unattributed reading, and `combined` keeps the weakest state of a pair, so a
ratio with an unpublished denominator comes back unpublished rather than
dividing by an invented number. The test is whether the gap can survive the
call. If it cannot, do not write it.

---

## Build order

Ship the moat first. Do not build twenty screens before the two-number engine
works, because everything else depends on it being correct.

**M1 — the engine.** `FathomKit/Storage`. FTS walk, allocated vs logical, clone
detection via `F_LOG2PHYS_EXT`, sparse via `SEEK_HOLE`, snapshot enumeration.
No UI. Ships when it walks a 500 GB volume in under 30 seconds and every number
matches the reference machine fixtures.

**M2 — Explore and Storage.** The two screens that show the engine. First point
where a human can see the product's whole argument.

**M3 — hardware truth.** SMART, SMC, IOReport. Endurance, SSD Health, Sensors.
Verify the NVMe entitlement situation on Tahoe before designing around it.

**M4 — live monitors.** CPU, GPU, Memory, Network, Bluetooth. Cheap once the
IOKit layer from M3 exists.

**M5 — the widget.** Menu bar. Measure its cost the day it first runs, not at
the end.

**M6 — action.** Reclaim, Applications, Cloud, Maintenance. Everything that
moves a file. Trash-only, dry-run first, cost stated.

**M7 — memory over time.** Timeline, Attribution, Weekly digest. These need
history, so they can only be honest after the app has been running for days.

Home and Deep Scan assemble from the others and land last, not first.

**Status, 23 August 2026.** M1–M7 are implemented and all twenty sections are on
the Instrument Panel vocabulary. What is left is not code: the reference-machine
measurements in `RELEASE-GATES.md`, and the fact that **none of the interface
has been seen running.** It has been verified by compiler, by the contrast gate
and by arithmetic, which caught every defect found so far — but no human has
looked at a screen. Treat that as the project's largest open risk, and do not
add to the pile without saying so.

---

## Working agreements

**Correctness over coverage.** A screen that shows four values it can prove
beats one that shows twelve it cannot. When you cannot get a number honestly,
render the not-published state and open an issue. Do not approximate.

**The prototype is the visual spec.** `docs/fathom-app.html` is locked, and it
is the Instrument Panel — one always-on window, every section a set of readouts
behind a 64px rail. Match its spacing, type scale, colour worlds and materials.
If you believe a screen needs to change, change the prototype first and get it
approved, then implement. Do not diverge silently in Swift.

It is generated by `scripts/build-prototype.py`, so edit that and re-run it
rather than hand-editing 700 KB of embedded fonts.

**Where the prototype and the contrast rule disagree, the rule wins — and you
record it.** This has happened four times: the design's white materials, two
semantic colours, the grain's blend, and the readout cell's depth. Each is
documented in `FATHOM-DESIGN.md` with the measurement that forced it. Never
silently soften a design value; state what it measured and what you changed it
to.

**Test against the reference machine.** `FathomKitTests` fixtures come from a
Mac mini M4 Pro, macOS Tahoe 26.5.2, listed in `FATHOM-DATA-SOURCES.md`. Every
hardware reader gets a test that asserts the exact reference value.

**`perflevel0` is the performance cluster.** Not efficiency. This is the most
common bug in Mac monitoring code and it was in our own prototype.

**No shelling out in the shipping build.** `tmutil` and friends are fine for
prototyping. Production reads the API.

**Accessibility is not a phase.** Full VoiceOver labels, Dynamic Type, Reduce
Motion honoured, contrast ≥ 4.5:1 on every surface, complete keyboard
navigation. Build it in, do not retrofit.

Contrast is gated rather than reviewed. `scripts/check-contrast.py` composites
the whole stack from source — worlds, grain, highlight, plate, materials,
semantic palette, focus ring, text alpha — and fails the build if any surface
drops below the rule on any of the twenty worlds. **Anything you draw beneath
the plate must be added to it.** Three separate layers have now quietly cost
text contrast, and none was visible to inspection.

Labels live in the shared components rather than the section views, so a label
written beside the value it describes cannot drift from it — and a wrong one is
wrong everywhere at once. No per-view VoiceOver audit has been done.

**CI runs every gate on arm64, and it is green.** The contrast gate, the
forbidden-API audit and the privacy-string check all fail the build for real.
Run them locally before you push anyway — they are fast — but remember a local
run cross-compiles from whatever host you are on and CI does not. When the two
disagree, CI is right.

**Commit messages state the user-visible effect.** "Explore now shows 0 GB
freeable for Docker's sparse image" beats "fix size calc".

---

## When you are unsure

Stop and ask rather than guessing. Specifically:

- A number you cannot trace to `FATHOM-DATA-SOURCES.md`
- An API that requires an entitlement Apple may not grant
- Anything that would make an action irreversible
- A layout the prototype does not cover
- A place where the honest answer is "we cannot know this"

That last one is not a failure. It is the product. Surfacing a gap correctly is
worth more than filling it plausibly.
