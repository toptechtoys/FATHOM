# AGENTS.md — FATHOM

**Read this before writing any code.** It is the contract for the build, and
every coding agent working here reads it: Codex loads it directly, Claude Code
through `CLAUDE.md`.

This file is the core. Detail that matters for one part of the codebase lives
in `docs/agents/`; see *Where the rest lives*.

## What you are building

A macOS utility for Apple silicon that tells the truth about storage, memory and
SSD endurance. Native SwiftUI app plus a menu bar widget. Ships outside the Mac
App Store, Developer ID signed and notarised.

**One sentence:** every other Mac utility shows you a number it cannot justify;
FATHOM shows you two numbers and names the one it does not know.

## Non-negotiables

These are product law. A pull request that violates one does not merge, no
matter how good the code is.

1. **Never invent a number.** If a value cannot be traced to a row in
   `FATHOM-DATA-SOURCES.md`, it does not render. Add the row first. This one is
   gated rather than reviewed: `scripts/check-data-sources.py` reads every raw
   value out of the `DataSource` enum and fails the build if one of them is not
   named in the document. Review had already missed three.
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

## Repository layout

`Fathom/` is the SwiftUI app, 20 sections under `Fathom/Sections/`. `FathomKit/`
is all measurement: no UI, fully testable. `FathomBar/` is the menu bar widget,
`FathomCLI/` the `fathom` binary that `RELEASE-GATES.md` gate 1 runs, `Sources/`
the C shims Swift cannot reach directly, `FathomKitTests/` the behaviour and
replay tests. `Fathom.xcodeproj` is generated from `project.yml`. The full tree
is in `docs/agents/layout.md`.

**Presentation logic that makes a claim belongs in FathomKit, not beside the
view.** A treemap whose areas are wrong misrepresents a volume as confidently as
a wrong number does, so `TreemapLayout` is tested. So are `SampleHistory`, which
decides how a chart draws a second nobody measured, and `FindingEngine`, which
decides what is worth saying at all. The rule of thumb: if getting it wrong
would make the product lie, it is measurement, whatever it looks like.

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

## Build order

Ship the moat first. Do not build twenty screens before the two-number engine
works, because everything else depends on it being correct.

The milestones, M1 (the engine) through M7 (memory over time), and the gate each
ships on are in `docs/agents/build-and-gates.md`.

**Status.** M1–M7 are implemented, all twenty sections are on the Instrument
Panel vocabulary, and the owner's native-feel pass has been applied across every
one of them — 214pt labelled sidebar, type at ×1.32, card readouts and panels,
filled action buttons. `RELEASE-GATES.md` is the live record of which
reference-machine gates have passed and which are still open.

**Run the app when you change a screen.** `docs/agents/running-the-app.md` covers
the Intel host build, what it cannot show, and how to check what you see.

## Where the rest lives

Read these after this file, in order:

1. `docs/FATHOM-DATA-SOURCES.md` — every number and the exact API behind it
2. `docs/FATHOM-PRD.md` — what ships and why
3. `docs/FATHOM-DESIGN.md` — the locked design system
4. `docs/fathom-app.html` — the visual spec, open it in a browser
5. `docs/RELEASE-GATES.md` — everything still outstanding lives here

Build and test commands are in `README.md` §Build. The topic notes in
`docs/agents/` hold detail for one part of the codebase; open the matching one
before you change those files:

- `layout.md` — the full repository tree
- `design.md` — the native-feel rider, the contrast gate, the field check, labels
- `hardware-testing.md` — recorded fixtures, replay tests, the unrecorded SMART log
- `build-and-gates.md` — milestones M1–M7 and their gates, what CI covers
- `running-the-app.md` — building on an Intel host, checking the number before a pixel

## Working agreements

**Correctness over coverage.** A screen that shows four values it can prove
beats one that shows twelve it cannot. When you cannot get a number honestly,
render the not-published state and open an issue. Do not approximate.

**The prototype is the visual spec.** `docs/fathom-app.html` is locked, and it
is the Instrument Panel — one always-on window, every section a set of readouts
beside a 214px labelled sidebar. Match its spacing, type scale, colour worlds
and materials.
If you believe a screen needs to change, change the prototype first and get it
approved, then implement. Do not diverge silently in Swift.

It is generated by `scripts/build-prototype.py`, so edit that and re-run it
rather than hand-editing 700 KB of embedded fonts.
The owner's native-feel pass of 25 August is recorded as a rider in
`docs/agents/design.md`.

**Where the prototype and the contrast rule disagree, the rule wins — and you
record it.** Never silently soften a design value; state what it measured and
what you changed it to. The four cases so far are in `docs/agents/design.md`.

**`perflevel0` is the performance cluster.** Not efficiency. This is the most
common bug in Mac monitoring code and it was in our own prototype.

**No shelling out in the shipping build.** `tmutil` and friends are fine for
prototyping. Production reads the API.

**Accessibility is not a phase.** Full VoiceOver labels, Dynamic Type, Reduce
Motion honoured, contrast ≥ 4.5:1 on every surface, complete keyboard
navigation. Build it in, do not retrofit. `scripts/check-contrast.py` gates
contrast; what it covers, and what you must add to it, is in
`docs/agents/design.md`.

**Commit messages state the user-visible effect.** "Explore now shows 0 GB
freeable for Docker's sparse image" beats "fix size calc".

## When you are unsure

Stop and ask rather than guessing. Specifically:

- A number you cannot trace to `FATHOM-DATA-SOURCES.md`
- An API that requires an entitlement Apple may not grant
- Anything that would make an action irreversible
- A layout the prototype does not cover
- A place where the honest answer is "we cannot know this"

That last one is not a failure. It is the product. Surfacing a gap correctly is
worth more than filling it plausibly.
