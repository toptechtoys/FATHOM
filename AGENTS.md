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

---

## Repository layout

```
Package.swift           FathomKit, the C shims, the CLI, the test target
project.yml             XcodeGen input; Fathom.xcodeproj is generated from it
Fathom.xcodeproj
Fathom/                 SwiftUI app
  App/                  entry point, window, navigation
  Design/               tokens, worlds, plate, grain, focus ring, fonts
  Sections/             one folder per section, 20 total
  Components/           rail, readout grid, panel, and 12 of the 13 panel
                        types — Rule rows lives in Sections/Reclaim
  Resources/            asset catalogue, Info.plist, entitlements
FathomKit/              all measurement, no UI, fully testable
  Storage/              FTS walk, two-number engine, clone + sparse detection
  Hardware/             SMART, SMC, IOReport, IOHID, IOKit
    ChannelMaps/        the Ed25519-signed IOReport channel map
  System/               CPU, GPU, memory, network, bluetooth
  Model/                Measurement<T> and the three-state type
  Actions/              reclaim engine, recipe catalogue, cloud eviction,
                        application catalogue, journal recovery
    Recipes/            reclaim-recipes.json and its detached signature
Sources/                the C shims Swift cannot reach directly
  CFathomHardware/      IOKit, IOReport, IOHID
  CFathomStorage/       fts(3), fgetattrlist, F_LOG2PHYS_EXT, SEEK_HOLE
  CSQLite/              the amalgamation the storage index builds on
FathomBar/              menu bar widget target
FathomCLI/
  FathomCLI.swift       the `fathom` binary RELEASE-GATES gate 1 runs
FathomKitTests/         behaviour tests, plus the gate 2 replay tests
  Fixtures/             recorded hardware payloads, declared with `.copy`
tests/release.bats      the release script's own tests
scripts/
  check-contrast.py     the contrast gate; runs in CI
  check-data-sources.py the data-source gate; runs in CI
  build-prototype.py    regenerates docs/fathom-app.html
  prototype-content.js  the prototype's section content, read by the above
  release.sh            sign, notarise, staple; see §Distribution
docs/
  FATHOM-PRD.md
  FATHOM-DESIGN.md
  FATHOM-DATA-SOURCES.md
  RELEASE-GATES.md      what the reference machine must still prove
  REFERENCE-PASS.md     the blank form those gates are recorded on
  M1-ENGINE-STATUS.md
  FATHOM-LOGO-BRIEF.md
  fathom-app.html       the locked visual reference
  runbooks/
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

**Status, 25 August 2026.** M1–M7 are implemented, all twenty sections are on
the Instrument Panel vocabulary, and the owner's native-feel pass has been
applied across every one of them — 214pt labelled sidebar, type at ×1.32, card
readouts and panels, filled action buttons. What is left is the
reference-machine measurements in `RELEASE-GATES.md`.

**The interface has now been seen running, and it is worth knowing exactly how
much that settles.** `project.yml` pins `ARCHS: arm64`; overriding it builds a
working x86_64 app, and that ran on an Intel MacBookPro16,1 under macOS 26.
Every screen was walked. Two defects turned up in the first ten minutes that
the compiler, the contrast gate and the arithmetic had all passed: the
readout row resolved to CSS `auto-fill` and stopped a third of the way across
every section, and the `Layout` written to fix it trapped on SwiftUI's infinite
width proposal and killed the app at launch with no crash report.

What that host cannot answer is most of what remains. Every Apple-silicon
reading renders *not published* on Intel — IOReport, SMC temperature,
`perflevel1`, the NVMe SMART user client — so gate 2 is untouched, and gate 3's
idle cost is meaningless anywhere but Apple silicon. **Run it anyway when you
change a screen.** It is the cheapest check in this repository and it is the
only one that has ever caught a layout.

---

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

*Rider, 25 August 2026.* The owner reviewed the running app on screen and
directed a native-feel pass that supersedes the prototype on five points —
type renders ×1.32, the icon rail is a 214pt labelled sidebar, readout cells
are separated cards, the prominent action is a filled button, and scanning
screens carry an elapsed clock. Each is recorded with its values in
`FATHOM-DESIGN.md` §*The native-feel pass*. The colour worlds, materials,
grain, highlight and everything else still follow the prototype, and the
prototype was regenerated on 25 August to fold these in, so it and the app
agree again.

It is generated by `scripts/build-prototype.py`, so edit that and re-run it
rather than hand-editing 700 KB of embedded fonts.

**Where the prototype and the contrast rule disagree, the rule wins — and you
record it.** This has happened four times: the design's white materials — one
flip, which took the readout cell, the data row and its hover from white tint to
black — two semantic colours, the grain's blend, and the white highlight over
the field, which the app draws at half the prototype's strength because 30% puts
body text at 4.24:1. Each is documented in `FATHOM-DESIGN.md`
with the measurement that forced it. Never silently soften a design value; state
what it measured and what you changed it to.

**And where they disagree for no reason, that is a defect.** The field was the
last thing still carrying values from the direction the Instrument Panel
replaced, because it was written before the prototype was and nobody re-read it
afterwards: its gradient put the middle stop at 50% against the specified 60%,
it painted a fourth layer under the plate that the prototype has no equivalent
for, and it drew the grain over the highlight rather than under it. None of that
failed a build, and none of it was visible to inspection — which is why
`check-contrast.py` now reads the field's layers and their order out of
`FathomWorldBackground` and refuses to run if they are not what it composites.

**Test against real bytes — half true since 30 August 2026, and the half
matters.** Every hardware test used to assert *behaviour* only — that a tampered
channel map fails its signature, that energy units convert only when named, that
an absent channel reports the gap rather than a zero. Those are good tests and
they are not the same thing. Behaviour tests prove the reader handles what it is
given; a fixture proves it reads real bytes correctly.

`FathomKitTests/Fixtures/` now holds recorded AppleSMC, IOReport and IOHID
payloads, and `RecordedHardwareReplayTests.swift` replays them through the
shipping decoders: 2,206 real SMC values, a 10,570-channel IOReport inventory, a
664-channel energy delta and 45 IOHID sensors. A parser that misreads a real
payload now fails a build.

**They came from a Mac15,9 M3 Max, not from the Mac mini M4 Pro that
`RELEASE-GATES.md` names.** So gate 2's *comparison against the reference
machine* is still open; what closed is the narrower and more urgent gap, that no
test had ever put real hardware bytes through these decoders at all. Capture
again on the reference machine and commit both — the manifest names the Mac, so
two recordings cannot be mistaken for each other.

**The SMART log is still unrecorded, and that is a finding rather than an
omission.** The NVMe SMART user client returns IOReturn -536870201 on Apple
silicon — `0xe00002c7`, `kIOReturnUnsupported`, not `kIOReturnNotPrivileged`.
`AppleANS3CGv2Controller` does not advertise `NVMeSMARTCapable` and offers no
such user client, so **no entitlement changes this**, and M3's instruction to
"verify the NVMe entitlement situation on Tahoe" is answered: it is not an
entitlement situation. Endurance on an Apple-silicon internal SSD needs a
different source, or it stays *not published*.

Two production seams exist so the replay tests exercise the shipping path rather
than a copy of it: `IOReportSampler.decodeDelta` and
`TemperatureSensorReader.decodeSensors`, both alongside the older
`IOReportReader.decodeChannelInventory`. The live readers call them. **Keep it
that way** — a decoder the tests reach but the app does not is worth nothing.

Until then, do not write a test that asserts a reference figure from memory.
An invented fixture is worse than no fixture: it passes, and it certifies
nothing.

**Make the app print the number before you believe a pixel.** Running it is
the cheapest check here, and reading it wrong is the cheapest mistake. Three
diagnoses in one day were wrong the same way: a window "opening below its
minimum" that was measured off a screenshot at an assumed scale — the real
scale is 0.52 px per point on the development display, and the window was
opening at exactly its declared default; and twice, keyboard input "not being
delivered" when it was arriving the whole time.

Every one collapsed the moment something was instrumented to answer directly.
A temporary overlay reporting `GRID 2,184x164` proved the readout row was
sized correctly and specified wrongly. `defaults read com.exhibinaut.fathom`
showed five saved window frames and named the real defect. An `NSEvent`
counter beside a handler counter — arrivals versus calls — settled in one
screenshot what two speculative fixes had not. `sample(1)` named the exact
frame the Bluetooth read was parked in. Forty-eight timed reads turned a
timeout somebody liked the sound of into one the machine chose.

A screenshot shows you *that* something is wrong. It is very bad at *what*,
and it will let you write a confident paragraph about a defect that does not
exist. Add the counter, take the measurement, delete it afterwards.

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
wrong everywhere at once. A static per-view audit of labels, charts, motion
gating and type scaling was done on 25 August and fixed what it found;
VoiceOver itself has still never spoken this interface, which stays a
reference-machine task in `RELEASE-GATES.md`.

**CI runs every gate on arm64, and it is green.** The contrast gate, the
data-source gate, the forbidden-API audit and the privacy-string check all fail
the build for real. The forbidden-API audit greps `Fathom/`, `FathomKit/` and
`FathomBar/` only, so `FathomCLI/`, `Sources/` and `scripts/` are ungated and
were last checked clean by hand — do not read its green as covering them.
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
