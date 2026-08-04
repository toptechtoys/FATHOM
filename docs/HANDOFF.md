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

### 1.7 Version control, and Git LFS for the images

The workspace had no `.git`. It is now a repository on `main` with four commits:

```
267c6a5  Check every app icon for an LFS pointer, not just the 1024
f472c7f  Fail the build when the app icon is an unresolved Git LFS pointer
b1494f4  Keep the app icon intact now that the artwork lives in Git LFS
802a1a2  Initial import: FATHOM at its first honestly-green build
```

The import is a single commit because the pre-session state was unrecoverable —
there was no history to diff against, so a split would have been fabricated.
`.gitignore` already covered `.build/` (1.6 GB); `FATHOM-handoff.zip` was added
to it after inspection showed it to be a stale 30 July copy of `AGENTS.md` and
`docs/` that this repository already tracks. It remains on disk, untracked, so
the duplicate cannot drift from the originals.

**Ten images are stored in Git LFS**: three `docs/*.png` — 11.7 MB of the
16.1 MB initial import, so roughly three-quarters of it — and the seven
`AppIcon-*.png`. `.gitattributes` carries both patterns. LFS does not shrink the
local repository; the win is that re-exporting a screenshot adds one object
instead of welding another 5 MB blob into history permanently.

Two things about this are worth knowing before touching it:

- `git lfs migrate import` leaves the working tree holding **132-byte pointer
  files**, not the images. It happened on both migrations. `git lfs checkout`
  materialises them. Checksums were taken before each migration and re-verified
  after; all ten files are byte-identical to their pre-LFS originals.
- **An unresolved pointer is a readable file.** `actool` compiles one into the
  asset catalog without complaint, so a clone without git-lfs produces a green
  build and an app whose icon is 132 bytes of text. Three guards now prevent
  that, and each was tested in both directions by corrupting `AppIcon-16.png` —
  the file a 1024-only probe would have missed:

  | Entry point | Guard | On a pointer |
  |---|---|---|
  | CI | `lfs: true` on `actions/checkout@v4` | objects fetched, so no pointer reaches the build |
  | `scripts/release.sh` | refuses before archiving | **exit 3**, names the file |
  | `xcodebuild` | pre-build phase in `project.yml` | **exit 65**, names the file |

  Both scripted guards walk every PNG in `AppIcon.appiconset` and fail if the
  directory yields none, so a moved or emptied iconset cannot pass silently.

### 1.8 CI ran for the first time, and failed three times

Pushing to GitHub triggered the workflow, which had never executed before —
there was no remote. It failed three times, and every failure was real. None of
them could have been found on this host, because this machine has the same
macOS 26 SDK the code was written against.

**A portability defect in the C layer.** `CFathomStorage.c` used the
`SNAPSHOT_MNT_*` flag names, which older SDKs do not declare, so the build
failed outright on anything but a macOS 26 SDK. `fs_snapshot_mount()` itself has
been available since macOS 10.12 — only the names are new.
`<sys/snapshot.h>` documents each flag as *"same as MNT_\*"* and the values in
`<sys/mount.h>` match exactly, so the flags now fall back to those long-standing
constants rather than to bare literals, with `_Static_assert`s that fail the
build if a future SDK ever breaks that documented equivalence. Verified by
compiling the translation unit with all five names forcibly undefined, which
reproduces the runner's exact condition.

**CI was on a toolchain the project never claimed to support.** The build then
failed with strict-concurrency errors on `UNUserNotificationCenter` in
`ConsequenceAlertScheduler` and `DigestNotificationModel`. Those were not app
defects: the runner was `macos-15` with Xcode 16.4 and the macOS 15.5 SDK, where
those UserNotifications types are not yet `Sendable`. `README.md` and
`scripts/release.sh` both require **Xcode 26**; macOS 14 is the *deployment*
target — what the app runs on — not the SDK it is built with. The job now runs
on `macos-26`, which reports macOS 26.5.2, Xcode 26.6 and Swift 6.3.3, and a new
step records `sw_vers`, `xcodebuild -version` and `swift --version` so every run
proves which toolchain produced it.

**The shipping-API audit had never executed.** It invoked `ripgrep`, which is
absent from the runner image, so the step exited `rg: command not found`. Every
earlier failure happened upstream of it, which is why nobody noticed: the check
enforcing two non-negotiables — *nothing is deleted* and *one outbound request,
ever* — was dead from the day it was written. It is now built on `grep`, always
present, and each rule reports the rule it broke. Verified in four directions:
passes on a clean tree; fails naming the file when a `removeItem` call is
injected; fails reporting "found 2 files" when a second `URLSession` file is
injected; passes again once both are removed.

The workflow is now green — all ten steps, 1m58s, run `30826426803`. The README
carries a CI badge. The repository is private, so that badge renders only for
viewers signed in with access; fetched anonymously it returns HTTP 404.

### 1.9 Files changed

```
Fathom/App/SystemMonitorModel.swift          Fathom/Sections/Bluetooth/BluetoothView.swift
FathomKit/System/BluetoothReader.swift       FathomKit/Actions/ReclaimEngine.swift
FathomKitTests/SystemReaderTests.swift       FathomKitTests/ReclaimEngineTests.swift
project.yml                                  scripts/release.sh
.github/workflows/ci.yml                     docs/FATHOM-DATA-SOURCES.md
docs/RELEASE-GATES.md                        docs/HANDOFF.md (this file)
.gitignore                                   .gitattributes (new)
Sources/CFathomStorage/CFathomStorage.c      README.md
FathomKitTests/StorageGoldenFixtureTests.swift
```

Test count 110 → 113 (three added: the Bluetooth usage-description refusal, the
reclaim protected-path bypass, and the clone/hardlink/sparse golden fixture). No
unrelated work was modified.

---

## 2. Exact commands and results

All run on the host named above. The whole set was re-run end to end after the
CI, Git LFS and portability work landed, so these are results against the final
tree rather than figures carried forward from when each fix was made.

| Command | Result |
|---|---|
| `swift test --disable-sandbox` | **EXIT=0** — 113 tests passed *(was: SIGABRT, exit 1)* |
| `xcodegen generate` | **EXIT=0** |
| `xcodebuild … -scheme Fathom -configuration Release ARCHS=arm64` | **EXIT=0** — 0 errors, 0 warnings |
| `xcodebuild … -scheme FathomBar -configuration Release ARCHS=arm64` | **EXIT=0** — 0 errors, 0 warnings |
| `xcodebuild … -scheme Fathom -configuration Debug ARCHS=arm64` | **EXIT=0** |
| `swift build -c release --arch arm64 --disable-sandbox` | **EXIT=0** |
| `shellcheck scripts/release.sh` | **EXIT=0** *(was: exit 1)* |
| `bats tests/release.bats` | **EXIT=0** — 2/2 |
| GitHub Actions `CI` on `macos-26` | **success** — 10/10 steps, 1m58s, run `30826426803` *(was: 3 consecutive failures)* |

Contract constraints, each checked rather than assumed:

| Constraint | Evidence |
|---|---|
| No shipping shell-outs or permanent deletion | CI's audit script, run locally: **0 matches** for `unlink(` / `removeItem(` / `Process(` / `NSTask` / `system_profiler` / `tmutil` / `diskutil` |
| One outbound request | Same script: **exactly 1** file matches `URLSession\|URLRequest` — `FathomKit/System/PublicIPService.swift` |
| Removal via Trash only | `FathomKit/Actions/ReclaimEngine.swift:168` `FileManager.default.trashItem` |
| Three `Measurement` states | `Measurement.swift:6-8` — `known` / `notPublished` / `notAttributable`, no `.unknown` |
| SSD Health read-only | 0 mutation matches in `SSDHealthView.swift` |
| Privacy disclosures ship | `PlistBuddy` prints both strings from the built `FATHOM.app/Contents/Info.plist` |
| LFS images intact | all 10 SHA-256s match the checksums taken before migration |
| Icon survives the asset compiler | Release build produces a 2.9 MB `Assets.car`, `CFBundleIconName = AppIcon` |
| Pointer guards fire | A different icon was corrupted on each pass — `AppIcon-1024`, `-16`, `-256`, `-64` — and every time `release.sh` **exit 3** and `xcodebuild` **exit 65**, naming that file. Rotating the target is what proves the guards walk the whole set rather than probing one path |
| C layer builds on an older SDK | `CFathomStorage.c` compiles with all five `SNAPSHOT_MNT_*` names forcibly undefined, reproducing the runner condition that broke CI |
| Local matches what CI verified | `git rev-parse HEAD` == `origin/main`, clean tree, latest CI run green |

### Runtime evidence — the engine was exercised, not only read

- **Two-number engine — now an automated fixture, not a hand check.** A scratch
  directory holding a hardlink pair, an APFS clone and a sparse file returned
  `accounted on disk: 8392704 bytes`: 8 MB counted once, with the hardlink not
  double-counted and the clone family credited once at the LCA, plus 4 KB for
  the sparse file. `explain` also refused to publish freed-if-deleted in subtree
  mode, naming the reason.

  That check existed only as a scratch directory and a pair of eyes, so it died
  with the scratchpad. It is now
  `cloneHardlinkAndSparseTreeIsCreditedExactlyOnce` in
  `StorageGoldenFixtureTests`, which builds the same tree with `clonefile(2)`
  and `link(2)`, scans it with the real engine, and asserts the total. The
  expected value is derived from `stat(2)` rather than carrying 8392704 forward,
  because allocation policy belongs to the runner; what the fixture pins is the
  relationship. It asserts its own preconditions too — the hole stayed a hole,
  the clone really shares storage — so it cannot pass on a filesystem that
  quietly materialised either, and it was verified to fail when the expectation
  is changed to credit the clone twice.
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
surfaced a real CI failure (§1.2). CI itself is no longer theoretical either — it
runs on GitHub against `macos-26` and is green (§1.8).

---

## 4. What must be run on the M4 reference machine

Follow `docs/RELEASE-GATES.md`; these are the items this session added or
sharpened.

**Before anything else: install git-lfs on that machine and fetch the objects.**
The app icons are LFS objects, so this is now a build prerequisite, not a
convenience. `git clone` followed by `git lfs pull` (or a clone with git-lfs
already installed) is required; `git lfs ls-files` must list **10** files. A
checkout without them fails the build deliberately — `xcodebuild` exits 65
naming the offending icon — so the failure is loud rather than a silently
wrong app icon. `xcodebuild`, `scripts/release.sh` and CI each enforce this
independently.

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

**One defect found in this session is still open, and it is not external.**
Body text fails the 4.5:1 contrast rule on **all twenty colour worlds**, from
2.02:1 (network) to 4.32:1 (memory) — measured by `scripts/check-contrast.py`,
which reads the tokens and the text alpha from source so it cannot drift. The
text sits directly on the gradient with no card or material behind it, and a
`white` 15% radial highlight lightens the upper field further, so those numbers
are the optimistic case. It is not fixable by opacity alone: at full white, 16
of 20 still fail. Every remedy changes locked colour tokens, so per `AGENTS.md`
it needs a prototype change and approval rather than a silent Swift edit. This
blocks the accessibility gate, not the reference-machine measurements.

What changed is that the build is now honestly green rather than green by
assertion: the test suite genuinely passes instead of aborting, CI genuinely
passes **on a real runner** rather than by local inference, and the app no longer
contains a guaranteed launch crash on the target OS.

That distinction was earned the hard way. An earlier draft of this file claimed
CI passed because `shellcheck` had stopped failing locally. That was an
inference, and it was wrong: the first real CI run failed three times for three
unrelated reasons (§1.8), including a step that had never executed at all.
Nothing here should be read as passing until something has actually run it —
which is the same standard the product applies to its own measurements.

One open observation, flagged rather than changed: the app's shared monitor still
samples CPU, memory, GPU and network every second for whichever section is
visible. That is by design, but it is worth watching during the Energy Impact
pass now that Bluetooth no longer contributes.
