# Repository layout

The full tree. `AGENTS.md` carries the summary and the rule that presentation
logic making a claim belongs in FathomKit.

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
  release.sh            sign, notarise, staple; see RELEASE-GATES.md §Distribution
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
  agents/               topic notes the core AGENTS.md names
```
