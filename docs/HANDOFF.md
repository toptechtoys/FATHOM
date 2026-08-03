# FATHOM — session handoff

> **This file expires. Delete it once the M4 reference pass is complete.**
> Unlike everything else in `docs/`, this is a point-in-time record, not a living
> spec. Left in place after the reference pass it will misdescribe the repository.
> Every durable item it contains already lives in `RELEASE-GATES.md` and
> `FATHOM-DATA-SOURCES.md`; deleting this file loses nothing. Removing it is the
> closing step of the reference-machine checklist (`RELEASE-GATES.md`, gate 7).

Recorded 3 August 2026. Verification host: **MacBookPro16,1, `x86_64`, macOS
26.5.2 (25F84)** — *not* the reference machine. Every result below was produced
on that host during this session; nothing is carried forward on trust.

The headline correction: the previous handoff recorded *"`swift test`: 110 tests
passed."* That did not reproduce. The suite aborted with `SIGABRT`, and the cause
was a shipping defect rather than a test artifact. Details in §1.

---

## 1. Completed and verified work

### 1.1 Bluetooth TCC termination — a launch crash on the reference machine

`swift test` aborted. The crash report named the cause:

```
"termination": {"namespace":"TCC", "details":["This app has crashed because it
attempted to access privacy-sensitive data without a usage description. The
app's Info.plist must contain an NSBluetoothAlwaysUsageDescription key..."]}
TCC  __TCC_CRASHING_DUE_TO_PRIVACY_VIOLATION__
```

This was not confined to tests. `SystemMonitorModel` called
`BluetoothReader().read()` on the one-second sampling loop that starts when the
app opens, `IOBluetoothDevice.pairedDevices()` issues a TCC request, and macOS
*terminates* any process making that request without the usage string.
`project.yml` declared only `NSLocationUsageDescription`. The reference machine
runs the same OS version, so the shipped app would have died at launch. Builds
passed throughout because the kill is a runtime event, and CI never inspected the
built Info.plist.

Fixed in four places:

- `project.yml` — added `INFOPLIST_KEY_NSBluetoothAlwaysUsageDescription`,
  so regeneration preserves it.
- `FathomKit/System/BluetoothReader.swift` — the reader confirms the host bundle
  declares the key *before* asking. A host without it renders
  `.notPublished` naming the missing key instead of being killed. Three states
  preserved; nothing invented.
- `FathomKitTests/SystemReaderTests.swift` — regression test. The test bundle
  deliberately lacks the key, so it exercises the refusal path.
- `.github/workflows/ci.yml` — new step asserts both usage strings survive into
  the built `FATHOM.app` Info.plist via `PlistBuddy`, using a fixed
  `-derivedDataPath`. A build alone cannot catch this class of defect.

### 1.2 CI was red — `shellcheck` failed

The repo's own `.shellcheckrc` sets `enable=all`, which enables SC2250
(brace style), SC2155 (declare-and-assign) and SC2312 (masked returns). CI runs
`shellcheck scripts/release.sh` unqualified, and it exited **1**. The previous
handoff had checked only `bash -n`, which passes.

`scripts/release.sh` now conforms to the configured ruleset. Behaviour is
unchanged and was re-verified: malformed version still exits 2, `--version`
still prints `1.0.0`, `bats` still 2/2, and a full `--dry-run` prints the
complete archive → sign → verify → notarize → staple → validate → Gatekeeper
sequence for both the app and the DMG.

### 1.3 Reclaim — protected-path refusals were single-layered

`ReclaimEngine.execute` re-checked identity, open files, per-item confirmation
and recipe-root containment, but never re-applied `ReclaimSafety.refusalReason`.
**No shipped recipe sets `allowedRootPath`** (all six are `nil`), so for a
manifest that did not come straight from `dryRun` — and `ReclaimManifest` is
`Codable` with a public `execute` — there was no protected-path check at all.

`ReclaimSafety` now splits the path-only refusals from the dataless check, and
`execute` re-applies them as the last guard before anything moves. The new test
was confirmed to **fail with the guard removed** and pass with it restored, so it
is a real regression guard rather than a passing assertion.

### 1.4 Bluetooth reads gated to the visible section

Bluetooth was enumerated every second on the main actor regardless of which
section was on screen — a TCC-gated call that only `BluetoothView` consumes.
It now reads only while that section is visible; otherwise the snapshot is
`.notPublished(reason: "Paired devices are read only while the Bluetooth section
is open")`.

Gating alone would have shipped a broken screen. `start()` guarded on
`samplingTask == nil` while `stop()` cancelled unconditionally, and SwiftUI fires
the incoming view's `onAppear` before the outgoing view's `onDisappear` — so
entering Bluetooth from CPU cancelled the loop the new section depends on. That
pre-existing bug affects all five sharing sections. `SystemMonitorModel` now
counts observers and only tears down at zero, which closes both issues with one
mechanism. `beginBluetoothObservation()` also takes an immediate reading when it
is the first observer, so the section cannot briefly display *not published*
while it is in fact open.

### 1.5 Accessibility

`BluetoothView` carried its not-published *reason* only in `.help()` — a tooltip,
invisible to VoiceOver — and that reason now names the missing key. Added
`.accessibilityLabel` for both non-known states, matching the pattern already
established in `MeasurementValueView`.

### 1.6 Documentation

- `FATHOM-DATA-SOURCES.md` — Bluetooth section records the TCC termination
  behaviour and the declaration precondition; permissions table gains the
  `NSBluetoothAlwaysUsageDescription` row.
- `RELEASE-GATES.md` — gate 1 gains the disk-headroom requirement (§4), plus new
  gates 5 (Bluetooth on the signed build) and 6 (section-navigation lifecycle).

### 1.7 Files changed

```
Fathom/App/SystemMonitorModel.swift          Fathom/Sections/Bluetooth/BluetoothView.swift
FathomKit/System/BluetoothReader.swift       FathomKit/Actions/ReclaimEngine.swift
FathomKitTests/SystemReaderTests.swift       FathomKitTests/ReclaimEngineTests.swift
project.yml                                  scripts/release.sh
.github/workflows/ci.yml                     docs/FATHOM-DATA-SOURCES.md
docs/RELEASE-GATES.md                        docs/HANDOFF.md (this file)
```

Test count 110 → 112 (two added). No unrelated work was modified.

---

## 2. Exact commands and results

All run on the host named above, against the final tree.

| Command | Result |
|---|---|
| `swift test --disable-sandbox` | **EXIT=0** — 112 tests passed *(was: SIGABRT, exit 1)* |
| `xcodegen generate` | **EXIT=0** |
| `xcodebuild … -scheme Fathom -configuration Release ARCHS=arm64` | **EXIT=0** — 0 errors, 0 warnings |
| `xcodebuild … -scheme FathomBar -configuration Release ARCHS=arm64` | **EXIT=0** — 0 errors, 0 warnings |
| `xcodebuild … -scheme Fathom -configuration Debug ARCHS=arm64` | **EXIT=0** |
| `swift build -c release --arch arm64 --disable-sandbox` | **EXIT=0** |
| `shellcheck scripts/release.sh` | **EXIT=0** *(was: exit 1)* |
| `bats tests/release.bats` | **EXIT=0** — 2/2 |

Contract constraints, each checked rather than assumed:

| Constraint | Evidence |
|---|---|
| No shipping shell-outs or permanent deletion | `rg 'unlink\(\|removeItem\(\|Process\(\|NSTask\|system_profiler\|tmutil\|diskutil'` → **0 matches** |
| One outbound request | `rg -l 'URLSession\|URLRequest'` → **1 file**, `FathomKit/System/PublicIPService.swift` |
| Removal via Trash only | `FathomKit/Actions/ReclaimEngine.swift:168` `FileManager.default.trashItem` |
| Three `Measurement` states | `Measurement.swift:6-8` — `known` / `notPublished` / `notAttributable`, no `.unknown` |
| SSD Health read-only | 0 mutation matches in `SSDHealthView.swift` |
| Privacy disclosures ship | `PlistBuddy` prints both strings from the built `FATHOM.app/Contents/Info.plist` |

### Runtime evidence — the engine was exercised, not only read

- **Two-number engine.** A fixture with a hardlink pair, an APFS clone and a
  sparse file returned `accounted on disk: 8392704 bytes` — 8 MB counted once
  (hardlink not double-counted, clone family credited once at the LCA) plus 4 KB
  for the sparse file. Exact. `explain` correctly refused to publish
  freed-if-deleted in subtree mode, naming the reason.
- **Honest degradation.** `fathom doctor` on this Intel host: NVMe SMART denied →
  *not published*; 4119 IOReport channels resolved but **refused to label them**
  without a signed map for `MacBookPro16,1`; real SMC reads (`PSTR` 24.36 W);
  IOHID temperatures *not published*. No substituted values anywhere.
- **Reclaim recipes.** `fathom recipe test` — all six bundled recipes pass with
  their regeneration costs stated (rule 5).
- **Release pipeline.** `scripts/release.sh --dry-run` completes end to end.

---

## 3. Remaining external gates

Blocked by the machine and credentials, not by code. None of these can be closed
from this host.

1. **M4 reference measurements.** This host is `x86_64` / `MacBookPro16,1`.
2. **M1 benchmark.** ~500 GB reference volume, under 30 s, under 300 MB peak RSS
   — plus the disk-headroom figure now required by gate 1.
3. **FathomBar idle cost.** ≤ 0.2% CPU and ≤ 2.1 Energy Impact; > 0.5% or > 4.0
   blocks release. The 34-reads-per-minute test is a deterministic regression
   proxy only.
4. **Code signing.** `security find-identity -v -p codesigning` → **0 valid
   identities found**.
5. **Notarization.** No `fathom-notary` keychain profile
   (`notarytool` reports no such credential).
6. **Signed IOReport channel map and expanded reclaim recipes.** Require the
   trusted source and signing key. Do not fabricate either.

*Closed this session:* `shellcheck` and `bats` were previously unavailable
locally. Both are now installed and run clean, and `shellcheck` immediately
surfaced a real CI failure (§1.2).

---

## 4. What must be run on the M4 reference machine

Follow `docs/RELEASE-GATES.md`; these are the items this session added or
sharpened.

1. **Benchmark, including disk headroom.** The under-300 MB budget is a *memory*
   budget. The staged pipeline meets it by writing to SQLite instead of holding
   records in RAM, so the cost moves to disk. Confirm free space first, and
   record peak index size alongside duration and RSS — gate 1 is incomplete
   without it. On this host, scanning `/` drove the index to **10 GB** while RSS
   stayed near **120 MB**; that run was interrupted, so 10 GB is a lower bound
   for *that* volume and implies nothing quantitative about the reference volume.
   **Measure it; do not scale it.**
2. **Bluetooth against the signed, hardened, notarized build.** Not a local
   unsigned one. `Fathom.entitlements` is deliberately empty while the hardened
   runtime is enabled, and Bluetooth is a hardened-runtime resource. Confirm the
   consent prompt appears and the app survives it. If the signed build is denied
   enumeration, the documented remedy is
   `com.apple.security.device.bluetooth` — add it **only** if the reference
   machine proves it necessary, and record the observed denial alongside it. An
   unresolved denial stays *not published*.
3. **Section-navigation lifecycle.** Walk CPU → Bluetooth → CPU → Memory and
   back. Confirm every section keeps updating after a switch, Bluetooth populates
   immediately on entry rather than flashing *not published*, and leaving it
   stops the reads. **Neither app target has a test bundle
   (`testTargets: []`)**, so this has no automated coverage and must be
   exercised by hand.
4. **Hardware fixtures.** Compare SMART, SMC and IOReport readings against
   `FATHOM-DATA-SOURCES.md`. A denied entitlement or absent channel stays
   *not published*.
5. **Accessibility pass.** VoiceOver, keyboard navigation, Dynamic Type, Reduce
   Motion. Note that only `MeasurementValueView`, `HardwareMeasurementView` and
   `BluetoothView` carry explicit labels; the remaining **11** section views
   contain no `accessibility` call of their own and rely entirely on those
   shared components. A full per-view audit has not been done and should be
   scoped as its own reviewed change.

---

## 5. Status

FATHOM is **not** release-complete, and M1 is **not** signed off. The physical
M4 measurements and the signing and notarization evidence do not exist.

What changed is that the build is now honestly green rather than green by
assertion: the test suite genuinely passes instead of aborting, CI genuinely
passes instead of failing at its first shell step, and the app no longer contains
a guaranteed launch crash on the target OS.

One open observation, flagged rather than changed: the app's shared monitor still
samples CPU, memory, GPU and network every second for whichever section is
visible. That is by design, but it is worth watching during the Energy Impact
pass now that Bluetooth no longer contributes.
