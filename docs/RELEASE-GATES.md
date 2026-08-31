# Release gates

The implementation is buildable and testable without release credentials, but
the following measurements must be made on the reference Apple-silicon Mac
before a release can be called complete.

## Continuous integration

Green on `macos-26`, running every step on a real arm64 runner: LFS checkout,
`shellcheck`, `bats`, `xcodegen`, `swift test`, Release builds of both schemes,
the privacy usage descriptions, the contrast gate, the data-source gate and the
forbidden-API audit.

**The data-source gate makes non-negotiable 1 mechanical.**
`scripts/check-data-sources.py` reads every raw value out of the `DataSource`
enum and fails the build if one of them is missing from that document's *source
index*, is spelled differently there, or names a section that does not exist.
Until 26 August the rule was enforced by review, and review had missed three:
`IOHIDEventSystemClient` temperature, the `IOBlockStorageDriver` byte counters
and the `SF_DATALESS` flag all rendered values in the shipping UI with no row
behind them. Their rows exist now, and a fourth omission fails a build rather
than waiting for an audit.

The forbidden-API audit greps `Fathom/`, `FathomKit/` and `FathomBar/` only, so
`FathomCLI/`, `Sources/` and `scripts/` are ungated and were last checked clean
by hand.

**It was dark from 4 August to 23 August 2026 and the cause is worth recording.**
Thirty-one consecutive runs failed in three to four seconds with no runner
assigned and no step executed — a scheduling failure, so nothing was ever
compiled or tested, and a red badge on any commit in that window said nothing
about that commit.

The repository was private, and macOS runners bill at ten times the standard
rate. The included-minutes allowance ran out. Making the repository public —
macOS minutes are free for public repositories — got a runner assigned within
seconds, and the first run passed every step.

Two things worth keeping from that. A red badge nobody investigates is worse
than no badge, because it trains everyone to ignore the one signal that is
supposed to stop a bad merge. And **a green local run is not a green CI run**:
this host is Intel and cross-compiles, while CI builds on arm64 with its own
toolchain. Local runs are a fast check, not a substitute.

---

## Prerequisite: Git LFS

The app icons and the `docs/` screenshots are Git LFS objects, so **git-lfs is a
build requirement, not a convenience**. Clone with git-lfs installed, or run
`git lfs pull` afterwards; `git lfs ls-files` must list 10 files.

An unresolved LFS pointer is a readable file that `actool` will happily compile,
which would otherwise produce a green build and an app whose icon is 132 bytes
of text. Three guards make that failure loud instead: CI checks out with
`lfs: true`, `scripts/release.sh` refuses before archiving, and a pre-build phase
in `project.yml` fails the build. The scripted guards check every PNG in
`AppIcon.appiconset` and name the offending file.

Results go in `REFERENCE-PASS.md`, which is a blank form rather than prose —
these gates ask for figures to be recorded, and until now there was nowhere to
record them.

## Reference Mac mini M4 Pro

1. Build the Release CLI and run
   `fathom benchmark / --enforce-reference-gates` against the approximately
   500 GB reference volume with Full Disk Access. The recorded duration must be
   under 30 seconds and peak resident memory under 300 MB.

   **The first real run of this gate failed on every criterion, and it found a
   bug rather than a slow engine.** On 30 August 2026, on a Mac15,9 M3 Max with
   Full Disk Access: 341.615 s against a 30 s budget, 588 MB against 300 MB,
   230,799 inspection issues against zero, and *freed if deleted* unpublished.
   It walked 5,266,367 entries and measured **574.9 GB on a volume holding
   about 307 GB**.

   The 1.95× is the diagnosis. macOS firmlinks the data volume's directories
   into `/`, so `/Users` and `/System/Volumes/Data/Users` are one directory with
   two names — seven of the data volume's children are reachable both ways —
   and the walk counted each file twice. Neither obvious guard finds it:
   `FTS_XDEV` and `st_dev` see a single device, because the sealed system
   volume and its data volume are deliberately presented as one `st_dev` even
   though `statfs` reports `/dev/disk3s1s1` and `/dev/disk3s5`, and
   `ismount` reports false for `/System/Volumes/Data`. Only inode identity
   separates them, so `fathom_fts_walk` now counts each `(device, inode)`
   directory once and prunes the second path, publishing the count of subtrees
   it declined as `aliasedDirectoriesSkipped`. Files are never deduplicated —
   hard links are a real thing the two-number engine accounts for.

   A confirming run without Full Disk Access — so not a gate measurement, and
   not comparable on time or entry count — skipped 17 aliased subtrees and
   closed the measured-versus-explained gap from 265 GB to 18 GB.

   **This gate is unmeasured until it is run again.** Two things to watch when
   it is. Peak resident memory was still 483 MB in that confirming run, so the
   300 MB budget may fail for a reason that has nothing to do with the double
   count. And the duration is unknown: the 341 s figure was walking twice the
   volume, and the honest position is that no valid timing exists yet.

   **The gate's inspection-issue count was one bug, found 30 August 2026.**
   A run with Full Disk Access reported 184,853 issues, and they were not
   permissions: only **276** were traversal errors, out of 3,774,168 entries.
   **178,710 of them — 96.7% — were the same thing**, *Physical extents do not
   reconcile with allocated bytes*, and every sampled one was `UF_COMPRESSED`.

   macOS ships its own binaries filesystem-compressed. A compressed file keeps
   its bytes in the **resource fork**, leaves the data fork empty, and still
   reports the uncompressed length in `st_size` — `/usr/bin/tee` is 101,040
   bytes logical, 12,288 allocated, with 10,736 bytes of compressed data in the
   fork. `fathom_file_extents` mapped only the data fork, explained zero bytes
   of a real allocation, and returned *not attributable*. That is honest, and it
   is why *freed if deleted* — the number the product exists to show — was
   unpublished for the entire volume.

   The reader now maps the resource fork too. On `/usr/bin`: **26 of 883 files
   inspected with 858 issues, before; 883 with 1 issue, after.** Files are
   deduplicated by nothing here — the resource fork's extents are simply part of
   the file's allocation, and deleting the file frees them.

   **Peak memory passed for the first time on 30 August 2026, at 274.6 MB
   against the 300 MB budget.** RSS sampled every 25 ms through a scan showed
   where the 483 MB had been going: flat at 50 MB for twenty seconds while the
   index grew to 307 MB, then climbing only in the last second and a half. The
   streaming design holds everywhere except `reduceStagedAccounting`, which
   loads five per-node vectors into RAM.

   Neither problem was the design. The vectors were appended without being
   reserved, so each carried up to twice the capacity it needed and paid a full
   copy at every growth — 118 bytes per node to hold 29. And three of the five
   were copied rather than moved, because Swift copies an array on write while
   two references exist, even when the original is never read again. Reserving
   the exact row count and emptying each original before mutating took memory
   from **114.2 to 50.5 bytes per node**.

   That measurement was taken **without Full Disk Access**, so it is not the
   gate reading. Memory survives that: an earlier no-FDA run peaked within 0.2%
   of the same commit's FDA run, because blocked paths change what is walked far
   more than what is held. **Duration and issue count do not survive it** and
   are not quoted from that run.

   **The inspection-issue count fell 99.1% across four fixes, and the last of
   them is worth recording because the failure looked like a filesystem
   limitation and was not.** `F_LOG2PHYS_EXT` reports runs of whole allocation
   blocks. A range shorter than one block has no run length to report, so it
   answers with a valid device address and a contiguous length of **zero** — and
   the mapping loop read that as `EIO` and abandoned the whole file. It cost
   **13,475 files**, 97% of them under `/System/Volumes/Preboot`, and it is
   pre-existing behaviour in the data-fork loop rather than anything the
   resource-fork work introduced: 95% of the affected files have no resource
   fork at all.

   A zero-length run is now accepted only when the remainder fits inside one
   allocation block **and** the cursor is block-aligned, so it cannot straddle a
   boundary and is contiguous by construction. Both conditions are checked
   rather than assumed, because a zero-length run anywhere else is a real
   failure. Two of the sampled files were smaller than a single block, so the
   very first call returned zero — "no progress yet" does not separate the
   failure from the ordinary case, and only the block arithmetic does.

   Issue counts on a whole volume, in order of the four fixes:

   | | Issues |
   |---|---|
   | Before any fix | 230,799 |
   | After the firmlink fix | 184,853 |
   | After compressed-file extents | 15,170 |
   | After the partial block | **2,058** |

   What remains is 987 extent reconciliations, 441 unreadable entries, three
   unpublished addresses, and roughly 627 files that changed while the scan ran.
   **That last group may never reach zero on a running Mac**, which is a question
   about this gate's zero-issue condition rather than about the engine.

   **Provide disk headroom, and record what the index actually used.** The
   under-300 MB budget is a *memory* budget. The staged pipeline meets it by
   writing FTS records and extent results to SQLite in bounded pages instead of
   holding them in RAM, so the cost moves to disk: the benchmark index lands at
   `FileManager.default.temporaryDirectory` as `fathom-benchmark.sqlite`
   (plus `-wal` and `-shm`), and it is not the engine's separate 512 MB sibling
   reservation. Confirm free space before the run, and record the peak index size
   next to the duration and RSS figures — the gate is incomplete without it.

   No required headroom figure is stated here because none has been measured on
   the reference volume. The only observation available is from a non-reference
   host (MacBookPro16,1, macOS 26.5.2) scanning `/`: the index reached 10 GB
   while resident memory stayed near 120 MB, and that run was interrupted before
   completion, so 10 GB is a lower bound for that volume and says nothing
   quantitative about the M4 reference volume. Measure it; do not scale it.
2. Compare the exact SMART, SMC and IOReport readings with the fixtures in
   `FATHOM-DATA-SOURCES.md`.

   **Capture the raw payloads while you are there.** Dump the raw NVMe SMART
   log page, the SMC key inventory and values, and the IOReport channel
   subscription to files, commit them as test resources, and add tests that
   replay them. Without them a parser that misreads a real log has nothing
   standing in its way. A denied entitlement or absent channel remains
   *not published*; it is not a reason to substitute another value.

   **Half done, 30 August 2026 — and read which half.** `fathom
   capture-fixtures` was run on a **MacBook Pro Mac15,9, Apple M3 Max**, not on
   the Mac mini M4 Pro. Six payloads landed in `FathomKitTests/Fixtures/` and
   `RecordedSMCReplayTests.swift` and `RecordedIOReportReplayTests.swift` replay
   them through the shipping decoders: 2,206 real SMC values, a 10,570-channel
   IOReport inventory, a 664-channel energy delta and 45 IOHID sensors. The
   claim "no test replays real hardware bytes" is no longer true, and a parser
   that misreads a real payload now fails a build.

   **What is still open is this gate as written** — the comparison against the
   *reference machine's* readings. Capture again on the M4 Pro and commit both;
   the manifest names the Mac, and a test pins it, so two recordings cannot be
   confused. The recordings are also hash-checked against their own manifest, so
   a hand-edited fixture fails rather than quietly testing something else.

   **The SMART log page is the one payload that did not record, and that is an
   answer rather than a gap.** The NVMe SMART user client returns IOReturn
   -536870201 — `0xe00002c7`, `kIOReturnUnsupported`, not
   `kIOReturnNotPrivileged` (`0x2c1`) and not `kIOReturnNotPermitted`
   (`0x2e2`). The controller is `AppleANS3CGv2Controller`, it does not advertise
   `NVMeSMARTCapable`, and `NVMeSMARTLib.plugin` is present on the system, so
   the plug-in exists and the controller offers no such user client. **No
   entitlement changes this**, which settles AGENTS.md M3's instruction to
   "verify the NVMe entitlement situation on Tahoe": it is not an entitlement
   situation. Endurance on an Apple-silicon internal SSD needs a different
   source, or it stays *not published*. Confirm on the M4 Pro before designing
   around it — one Mac is one Mac.
3. Run FATHOM Bar with its four default items and read the idle cost off the
   Menu Bar section. **The widget now measures its own CPU** through
   `proc_pid_rusage` and publishes it; the app displays that figure and says
   which item count it was taken with, so this step is a reading rather than a
   stopwatch exercise. At most 0.2% CPU; 0.5% blocks release.

   **Energy Impact is still a manual reading.** Activity Monitor's composite
   comes from `powermetrics`, which requires root, so FATHOM does not take it.
   Read it from Activity Monitor: at most 2.1, and 4.0 blocks release.

   The automated sampling-plan test additionally caps the default steady-state
   plan at 34 high-level reads per minute (12 CPU, 12 network, 6 capacity and 4
   temperature inventories). That deterministic cap catches polling
   regressions, but does not replace the physical measurement.

   **The measurement must be taken on Apple silicon.** The targets are
   Apple-silicon figures, and a number taken on an Intel Mac is a measurement
   of something else.
4. Exercise onboarding, menu-bar visibility guidance, sleep/wake suspension,
   memory-pressure second-row rendering, VoiceOver, keyboard navigation,
   Dynamic Type and Reduce Motion.

   Contrast is now enforced rather than assumed. Body text — `white` at 82% —
   previously sat straight on the gradient and failed the 4.5:1 rule on **all
   twenty worlds**, from 2.05:1 (bluetooth) to 4.32:1 (memory). The content
   column and the rail now sit on a black plate at 45%, and the Instrument
   Panel's materials layer on top of it — cell 16%, row 7%, hover 13% — with
   the colour worlds themselves untouched. The tightest surface is body text on
   the bare plate at 4.60:1. `scripts/check-contrast.py` composites seven
   surfaces and five semantic colours across all twenty worlds from source,
   including the white radial highlight the plate sits on, and runs in CI, so a
   token change that breaks any of them fails the build.
   What still needs a human on the reference machine is everything the numbers
   cannot settle: that the plate reads correctly on a real display — including
   whether the rail's `.ultraThinMaterial` erodes the 0.10 of margin its
   unselected icons have, which the gate cannot model because a material's
   composite depends on the wallpaper behind the window, and whether Reclaim's
   journal-recovery banner, which draws `.ultraThinMaterial` directly under its
   own text in all three of its states, lightens the ground beneath it — and
   that VoiceOver, keyboard focus, Dynamic Type and Reduce Motion behave.

   **Accessibility labels live in the shared components, not the sections.**
   Eleven components carry `accessibilityLabel`; the section views carry almost
   none of their own and rely entirely on those. That is deliberate — a label
   written once beside the value it describes cannot drift from it — but it
   means a component with a wrong label is wrong everywhere at once.

   **A static per-view audit was done on 25 August — code-reading, not
   listening.** It inventoried every accessibility modifier, chart, animation
   and font in both UI targets and verified the good news: all seven animation
   sites honour Reduce Motion, every font routes through a `relativeTo:`
   scaling helper, and every hand-drawn chart carries a composed label that
   names its source. It also fixed the four defects it found: the seven-day
   columns spoke only the net of the two-bar split they draw and called a
   half-recorded day *no record*; Explore's two byte columns were spoken as
   bare counts with nothing saying which was *on disk* and which *freed if
   deleted* — the exact distinction the product exists to draw; and the
   unattributable readout printed raw unformatted integers. What a static
   audit cannot settle stays here: **VoiceOver has never actually spoken this
   interface**, and walking all twenty sections with it on the reference
   machine remains open.

   Dynamic Type is settled as far as static reading can settle it: the fonts
   scale, and the containers that used to clip were fixed. What is unproven is
   whether the enlarged charts read well and whether the 9px tracked
   micro-labels stay legible at Accessibility sizes.

   **Two things a walk of all twenty sections left open, 24 August.** Both were
   seen on an x86_64 build on an Intel host, so both want confirming here — and
   both predate the 25 August native-feel pass, which changed the sidebar
   width, the type scale and every readout and panel, so the layout they were
   seen against no longer exists.

   *The section title and the status strip overlapped, twice, and it has not
   been reproduced since.* The display title rendered underneath the strip's
   25% black rather than below it. **An earlier note here said the window had
   opened below the `minWidth: 720, minHeight: 560` it declares. That was
   wrong** — it was measured off a screenshot at an assumed scale, and the
   screenshots are 0.52 px per point on this display. Every frame macOS has
   ever saved for this window records `1200 760`, exactly the declared default.
   Nothing has ever opened undersized.

   What was real, and is now fixed, is that the window kept being restored to
   frames recorded against a screen layout that no longer matched — see the
   autosave-name defect in `FathomWindow`. That is the likeliest reason the
   window kept reappearing in different places and on the other display, and
   plausibly the reason for the overlap, but it is not proven. If the title
   ever sits under the strip again, capture the window frame at the same
   moment.

   *Arrow navigation was broken, and is fixed.* An earlier note here guessed
   the key events were not being delivered. **They were.** An instrumented
   build counted them arriving with an `NSEvent` monitor while SwiftUI's
   `.onKeyPress` was called zero times — it only fires on a focused view, and
   this window has none, because `Full Keyboard Access` is off by default and
   Tab reaches no button in the rail. `Command-K` had been working the whole
   time; the palette was opening on the other display.

   Arrow navigation is now the window-level monitor the prototype specifies.
   Verified by hand: Down and Right step forward, Up and Left step back,
   `Command-K` still opens the palette, and arrows inside the palette move the
   palette rather than the section behind it.

   **The first rail icon used to lose the top of its focus ring.** A
   `ScrollView` clips its children and the ring is drawn *outside* the icon it
   surrounds; the first icon sat at exactly y=0, so the ring's top edge landed
   at -4pt and was thrown away. The rail now takes `FathomFocus.reach` off the
   traffic-light reservation and gives it back inside the scroll, so the ring
   has room and no icon moves — measured both ways, first icon at window y=331
   before and after, 335 without the compensation. The last icon was never
   affected: it already had 8pt beneath it.

   **What still wants a person here**: all twenty sections and back with the
   arrows, `Tab` into the rail with Full Keyboard Access *on* — which this
   machine had off, so no ring has ever been seen where focus actually put it —
   Increased Contrast widening it to 3pt, and VoiceOver over the same path.
5. Open the Bluetooth section and confirm macOS shows the Bluetooth consent
   prompt and that the app keeps running through it.

   **The hang that used to block this gate is fixed, and what caused it is
   worth keeping.** Opening the section froze the whole window: the reader was
   `@MainActor` and called synchronously from `onAppear`, so the main thread
   parked inside `-[IOBluetoothCoreBluetoothCoordinator init]` and the 1 Hz
   loop stopped in every section. It was waiting on the TCC consent prompt —
   which arrived minutes later, on the other display. Nothing exotic: the first
   paired-device request on any Mac raises that prompt, and the answer comes
   whenever the person gets to it. The app was at the mercy of a dialog nobody
   had seen.

   The read now runs through `Task.detached`, like `MemoryReader` and
   `GPUReader` on the same loop, and the section stops waiting after ten
   seconds and says so — `SystemMonitorModel.bluetoothDeadlineSeconds = 10`,
   interpolated into the sentence the section shows. It does not stop the
   *read* — a blocked `IOBluetooth` call cannot be recalled — so the
   outstanding one keeps its place and the row fills in if it ever returns. On
   the test machine that is exactly what happened: *requested, macOS has not
   answered yet*, then *did not answer within four seconds* — the deadline in
   force that day, since retuned to ten — then, once consent was given, ten
   paired devices and one connected.

   **Take the read timing again while you are here.** The deadline before the
   section says macOS has not answered is ten seconds, and that figure comes
   from one machine: 48 consecutive reads, the first at **5,777 ms** while the
   CoreBluetooth coordinator was built, the other 47 at a median of **3.5 ms**
   and a worst case of 83 ms. The cold read is the only one that matters and
   there is exactly one sample of it. If the reference machine's cold read is
   materially slower, the deadline is too short and will announce a failure
   just before the answer arrives — which is what four seconds did.

   **This does not close the gate.** It was seen on an Intel MacBookPro16,1 and
   an unsigned debug build; the gate asks for the signed, hardened, notarized
   build on Apple silicon, and only that proves the entitlement situation.
   What is now known is that the granted path publishes devices and the denied
   or pending path is a sentence on screen rather than a frozen app.

6. Walk CPU → Bluetooth → CPU → Memory and back. `SystemMonitorModel` counts its
   observers, and reads paired devices only while the Bluetooth section is on
   screen. Confirm three things: every section keeps updating after a switch
   (the shared loop must survive the outgoing section's `onDisappear`); the
   Bluetooth section shows devices immediately on entry rather than flashing
   *not published*; and leaving it stops the reads. Neither app target has a test
   bundle (`testTargets: []`), so this lifecycle has no automated coverage and
   must be exercised by hand.

   **Walked on 24 August, on the wrong hardware.** CPU -> Bluetooth ->
   Memory: every section kept updating across the switches, Bluetooth
   showed its devices immediately on re-entry rather than flashing *not
   published* — the model publishes the cached reading and refreshes
   behind it — and leaving stopped the reads, with no `BluetoothReader` or
   `IOBluetoothDevice` frames in a three-second sample and no thread growth.
   Intel, unsigned; redo it here on the signed build.
7. ~~Delete `docs/HANDOFF.md`.~~ **Done, 23 August.** It was a point-in-time
   session record rather than a living spec, and it had come to describe a
   repository state that no longer existed. Its two pieces of durable content
   were moved here first — the credential state under *Distribution*, and the
   accessibility caveat into gate 4 — so nothing was lost. It remains in git
   history, which is this repository's version of the Trash: removed from the
   working tree, recoverable, not destroyed.

## Distribution

**None of this has been exercised, and the credentials do not exist yet.** On
the development host `security find-identity -v -p codesigning` reports **0
valid identities**, and `notarytool` has no `fathom-notary` profile. Signing and
notarization are therefore untested end to end, not merely unrun — the script
below has never had a real certificate to work with.

Two further items are blocked on something outside this repository rather than
on time: the **signed IOReport channel map** and the **expanded reclaim
recipes** both need a trusted source and a signing key. Neither may be
fabricated to unblock a build; an unsigned map stays *not published*.

Configure the Developer ID certificate and a `notarytool` keychain profile
locally; do not put credentials in the repository. Then run:

```sh
FATHOM_DEVELOPER_ID_APPLICATION='Developer ID Application: …' \
FATHOM_NOTARY_PROFILE='fathom-notary' \
scripts/release.sh --release-version X.Y.Z
```

The script refuses existing artifacts, verifies the signed app, submits and
staples both the app and DMG, and runs Gatekeeper assessment before reporting
success.
