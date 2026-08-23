# Reference machine pass — record

**Nothing in this file is filled in.** Every field is blank because nothing has
been measured. Leave a field blank rather than writing a plausible figure; a
blank says *not measured*, and an invented number says something worse.

`RELEASE-GATES.md` says what each gate is and why. This is where the results go.
Fill it in on the reference machine and commit it — as its own pull request if
the results warrant discussion, directly if they do not. Record every gate,
including the ones that come back *not published*, which are outcomes rather
than failures.

Copy this file per release rather than overwriting it. A pass is evidence about
one commit on one machine, and last release's figures are not this release's.

| | |
|---|---|
| **Machine** | |
| **macOS build** | |
| **Volume, capacity, filesystem** | |
| **Drive model and node** | |
| **Date of pass** | |
| **Commit under test** | |
| **git-lfs objects present** | `git lfs ls-files` must list 10 · result: |

---

## Gate 1 — Benchmark

```sh
fathom benchmark / --enforce-reference-gates
```

| Measurement | Budget | Observed |
|---|---|---|
| Duration | under 30 s | |
| Peak resident memory | under 300 MB | |
| Peak index size on disk | no budget; **record it** | |
| Free space before the run | — | |

The under-300 MB budget is a *memory* budget; the staged pipeline meets it by
moving cost to disk, so gate 1 is incomplete without the index figure. The only
prior observation is 10 GB on a non-reference volume, from an interrupted run —
a lower bound for that volume and nothing about this one. **Measure it; do not
scale it.**

---

## Gate 2 — Hardware fixtures

Compare against `FATHOM-DATA-SOURCES.md`. A denied entitlement or an absent
channel stays *not published*; it is never replaced with another value.

| Source | Field | Expected | Observed | Matches |
|---|---|---|---|---|
| NVMe SMART | Percentage used | | | |
| NVMe SMART | Data written | | | |
| NVMe SMART | Power-on hours | | | |
| NVMe SMART | Unsafe shutdowns | | | |
| SMC | Total system power (`PSTR`) | | | |
| SMC | Fan keys | | | |
| IOHID | Temperature sensor count | | | |
| IOReport | Power channels published | | | |

Any row that does not match is a finding, not a rounding error. Record what was
observed and open an issue before changing a fixture.

**Raw payload capture** — the recordings that let these be tested anywhere.

| Payload | Captured | Committed as |
|---|---|---|
| NVMe SMART log page, raw bytes | | |
| SMC key inventory | | |
| SMC key values read | | |
| IOReport channel subscription | | |

No test replays real hardware bytes today. These recordings are the only way to
prove a parser reads an actual log correctly, and this is the only moment they
can be taken.

---

## Gate 3 — Idle cost

Run FATHOM Bar with its four default items and read the figure off the Menu Bar
section. The widget measures its own CPU through `proc_pid_rusage`; this is a
reading, not a stopwatch exercise.

| Measurement | Target | Blocks at | Observed | Items shown |
|---|---|---|---|---|
| Widget CPU | ≤ 0.2% | 0.5% | | |
| Energy Impact | ≤ 2.1 | 4.0 | | |

Energy Impact is a **manual Activity Monitor reading**. The app does not display
it: the composite needs root and FATHOM does not take root to report on itself.

Record the item count alongside the CPU figure. The target is stated for four
items, and a cost measured with fewer is a real measurement of a different
thing.

---

## Gate 4 — Accessibility and interface

**This gate carries the project's largest open risk.** The interface has never
been seen running. It has been verified by compiler, by the contrast gate and by
arithmetic — which caught every defect found so far, and says nothing about
whether a screen is legible.

Look at CPU, Storage and Bluetooth first: a sparkline with gap handling, a
treemap whose areas are load-bearing, and a row that reads *does not report*.

| Check | Result |
|---|---|
| Onboarding | |
| Menu-bar visibility guidance | |
| Sleep/wake suspension | |
| Memory-pressure second row | |
| VoiceOver, per view | |
| Keyboard navigation and focus ring | |
| Dynamic Type to Accessibility Large | |
| Reduce Motion | |
| The plate reads correctly on a real display | |
| `.ultraThinMaterial` behind cards — does it erode the margin? | |

Two things the contrast gate cannot model and a person must judge:

- Whether `.ultraThinMaterial` behind `HardwareResultCard` lightens the
  composite enough to matter. The cell keeps 1.20 of margin, which should
  absorb it.
- Whether the enlarged charts read well at Accessibility sizes, and whether the
  9px tracked micro-labels stay legible.

**No per-view VoiceOver audit has been done.** Labels live in the shared
components, so a wrong one is wrong everywhere at once. Scope that audit as its
own reviewed change rather than folding it in here.

---

## Gate 5 — Bluetooth against a signed build

Signed, hardened and notarized — not a local unsigned build.
`Fathom.entitlements` is deliberately empty while the hardened runtime is on.

| Check | Result |
|---|---|
| Consent prompt appears | |
| App survives the prompt | |
| Paired devices publish after granting | |
| If denied: the exact denial observed | |

If the signed build is denied enumeration, the documented remedy is
`com.apple.security.device.bluetooth`. Add it **only** if this machine proves it
necessary, and record the denial alongside it. An unresolved denial stays *not
published*.

---

## Gate 6 — Section navigation lifecycle

Walk CPU → Bluetooth → CPU → Memory and back. Neither app target has a test
bundle, so this has no automated coverage.

| Check | Result |
|---|---|
| Every section keeps updating after a switch | |
| Bluetooth populates on entry, no *not published* flash | |
| Leaving Bluetooth stops the reads | |

---

## Distribution

Untested end to end. There is no Developer ID certificate on the development
host and no `notarytool` profile, so `scripts/release.sh` has never run against
real credentials.

| Check | Result |
|---|---|
| `security find-identity -v -p codesigning` | |
| `notarytool` profile configured | |
| Signed, stapled app | |
| Signed, stapled DMG | |
| Gatekeeper assessment | |

---

## Outcome

| | |
|---|---|
| **All gates recorded** | |
| **Blocking failures** | |
| **Issues opened** | |
| **Cleared for release** | |
