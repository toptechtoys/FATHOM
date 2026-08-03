# FATHOM

FATHOM is a native macOS utility for Apple silicon that reports storage,
memory, and SSD endurance without disguising what macOS does not publish.
Every measured value retains its source and one of three states: known, not
published, or not attributable.

The defining storage result is two numbers for every indexed file and folder:
its allocated size on disk and the bytes actually freed if it moves to Trash.
APFS clones, sparse extents, snapshots, hard links, and open file descriptors
are part of that calculation.

## Build

Requirements: macOS 14 or later, Apple silicon for the shipping app, Xcode 26,
Swift 6, and XcodeGen.

```sh
xcodegen generate
xcodebuild -project Fathom.xcodeproj -scheme Fathom \
  -configuration Debug -destination 'generic/platform=macOS' build
swift test
```

`fathom explain <path>` exposes the two-number engine in a terminal.
`fathom doctor` prints a privacy-safe local capability report.
`fathom export-diagnostics <destination>` creates a non-overwriting support
bundle with path fields hashed by default; `--include-paths` is explicit opt-in.
`fathom recipe test <json> --home <fixture-root>` validates contributor recipes
and runs their bounded match rules without moving or deleting anything.
`fathom benchmark / --enforce-reference-gates` runs the complete staged,
snapshot-aware, open-file-aware M1 pipeline and fails unless the reference
duration, memory, completeness, and freeable-publication gates all pass.

## Privacy and safety

- Public IP and country is disabled until explicitly enabled. It is the only
  outbound request and is cached for six hours.
- FATHOM ships no analytics or automatic crash telemetry.
- Reclaim operations dry-run first, state regeneration cost, journal intent,
  re-stat every target, and use `NSFileManager.trashItem` only.
- SSD Health is read-only. FATHOM never writes SMC or NVMe state.
- Full Disk Access is optional and requested contextually.

## Deliberate omissions

FATHOM does not invent per-process network attribution, FPS, ANE utilisation
when no exact runtime key exists, overall health scores, predicted SSD failure
dates, fan control, scheduled deletion, or an application uninstaller. Intel
Macs are outside the shipping target.

The product contract is [AGENTS.md](AGENTS.md). Measurement provenance lives in
[docs/FATHOM-DATA-SOURCES.md](docs/FATHOM-DATA-SOURCES.md), and operational
recovery procedures live in [docs/runbooks](docs/runbooks).

## License

Project source is MIT. Bundled third-party asset notices are in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
