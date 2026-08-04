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
3. Run FATHOM Bar with its four default items. Record idle CPU and Energy Impact.
   The shipped targets are at most 0.2% CPU and 2.1 Energy Impact; 0.5% or 4.0
   blocks release. The automated sampling-plan test additionally caps the
   default steady-state plan at 34 high-level reads per minute (12 CPU, 12
   network, 6 capacity and 4 temperature inventories). That deterministic cap
   catches polling regressions, but does not replace the physical measurement.
4. Exercise onboarding, menu-bar visibility guidance, sleep/wake suspension,
   memory-pressure second-row rendering, VoiceOver, keyboard navigation,
   Dynamic Type and Reduce Motion.

   **This gate cannot pass today.** `scripts/check-contrast.py` measures body
   text — `white` at 82% — against each world's bottom stop, the worst case
   `FATHOM-DESIGN.md` names, and **all twenty worlds fail** the 4.5:1 rule in
   `AGENTS.md`. The range is 2.02:1 (network) to 4.32:1 (memory). The text sits
   directly on the gradient: no card, no material, and a `white` 15% radial
   highlight lightens the upper field further, so these figures are optimistic.
   Even at full opacity 16 of 20 still fail, so this cannot be fixed by dropping
   the text alpha alone. Resolving it means changing locked colour tokens, which
   `AGENTS.md` requires be approved on the prototype first. Run the script; it
   exits non-zero while any world fails. It is deliberately not yet a CI gate,
   because wiring it in before the design decision would simply hold the build
   red.
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
7. Once gates 1–6 are recorded, **delete `docs/HANDOFF.md`**. It is a
   point-in-time session record rather than a living spec, and after this pass it
   describes a repository state that no longer exists. Everything durable in it
   is already here or in `FATHOM-DATA-SOURCES.md`, so nothing is lost. Move it to
   the Trash — the same rule the product applies to a user's files applies to our
   own.

## Distribution

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
