---
paths:
  - ".github/**"
  - "scripts/*.sh"
  - "scripts/check-data-sources.py"
  - "tests/**"
  - "FathomCLI/**"
  - "Sources/**"
  - "FathomKit/Storage/**"
  - "Package.swift"
  - "project.yml"
---

Before you change CI, a script, the build inputs or the storage engine, read
`docs/agents/build-and-gates.md`. It has the milestones M1 to M7 with their gates
(M1 counts entries per second rather than gigabytes, and why) and which paths the
CI audits do and do not cover.
