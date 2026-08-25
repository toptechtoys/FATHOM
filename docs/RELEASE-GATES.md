# Release gates

The implementation is buildable and testable without release credentials, but
the following measurements must be made on the reference Apple-silicon Mac
before a release can be called complete.

## Continuous integration

Green on `macos-26`, running every step on a real arm64 runner: LFS checkout,
`shellcheck`, `bats`, `xcodegen`, `swift test`, Release builds of both schemes,
the privacy usage descriptions, the contrast gate and the forbidden-API audit.

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

   **Capture the raw payloads while you are there.** No test currently replays
   real hardware bytes — `FathomKitTests` holds no recorded data, so every
   hardware test asserts behaviour rather than parsing. Dump the raw NVMe SMART
   log page, the SMC key inventory and values, and the IOReport channel
   subscription to files, commit them as test resources, and add tests that
   replay them. This is the only moment anyone can take those recordings, and
   without them a parser that misreads a real log has nothing standing in its
   way. A denied entitlement or absent channel remains
   *not published*; it is not a reason to substitute another value.
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
   composite depends on the wallpaper behind the window — and that VoiceOver,
   keyboard focus, Dynamic Type and Reduce Motion behave.

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
   seen on an x86_64 build on an Intel host, so both want confirming here.

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
   `GPUReader` on the same loop, and the section stops waiting after four
   seconds and says so. It does not stop the *read* — a blocked `IOBluetooth`
   call cannot be recalled — so the outstanding one keeps its place and the row
   fills in if it ever returns. On the test machine that is exactly what
   happened: *requested, macOS has not answered yet*, then *did not answer
   within four seconds*, then, once consent was given, ten paired devices and
   one connected.

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
