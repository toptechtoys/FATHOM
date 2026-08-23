# Release gates

The implementation is buildable and testable without release credentials, but
the following measurements must be made on the reference Apple-silicon Mac
before a release can be called complete.

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
   `FATHOM-DATA-SOURCES.md`. A denied entitlement or absent channel remains
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
   the bare plate at 4.72:1. `scripts/check-contrast.py` composites seven
   surfaces and five semantic colours across all twenty worlds from source,
   including the white radial highlight the plate sits on, and runs in CI, so a
   token change that breaks any of them fails the build.
   What still needs a human on the reference machine is everything the numbers
   cannot settle: that the plate reads correctly on a real display — including
   whether `.ultraThinMaterial` behind the cards erodes the margin the gate
   cannot model — and that VoiceOver, keyboard focus, Dynamic Type and Reduce
   Motion behave.

   **Accessibility labels live in the shared components, not the sections.**
   Eleven components carry `accessibilityLabel`; the section views carry almost
   none of their own and rely entirely on those. That is deliberate — a label
   written once beside the value it describes cannot drift from it — but it
   means a component with a wrong label is wrong everywhere at once. **No
   per-view VoiceOver audit has been done**, and it should be scoped as its own
   reviewed change rather than folded into this pass.

   Dynamic Type is settled as far as static reading can settle it: the fonts
   scale, and the containers that used to clip were fixed. What is unproven is
   whether the enlarged charts read well and whether the 9px tracked
   micro-labels stay legible at Accessibility sizes.
5. Open the Bluetooth section and confirm macOS shows the Bluetooth consent
   prompt and that the app keeps running through it. `SystemMonitorModel` reads
   paired devices on its sampling loop, so a missing or rejected
   `NSBluetoothAlwaysUsageDescription` terminates the process rather than
   degrading; the unit suite proves the reader refuses to ask without the key,
   but only the reference machine proves the granted path publishes devices.
   Run this against the **signed, hardened, notarized** build, not just a local
   unsigned one. `Fathom.entitlements` is deliberately empty and the hardened
   runtime is enabled. If the signed build is denied paired-device enumeration,
   the documented remedy is the `com.apple.security.device.bluetooth` resource
   entitlement — add it only if the reference machine proves it is required, and
   record the observed denial alongside it. A denial that cannot be resolved
   stays *not published*; it is never replaced with another value.
6. Walk CPU → Bluetooth → CPU → Memory and back. `SystemMonitorModel` counts its
   observers, and reads paired devices only while the Bluetooth section is on
   screen. Confirm three things: every section keeps updating after a switch
   (the shared loop must survive the outgoing section's `onDisappear`); the
   Bluetooth section shows devices immediately on entry rather than flashing
   *not published*; and leaving it stops the reads. Neither app target has a test
   bundle (`testTargets: []`), so this lifecycle has no automated coverage and
   must be exercised by hand.
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
