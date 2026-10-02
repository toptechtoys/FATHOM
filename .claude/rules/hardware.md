---
paths:
  - "FathomKit/Hardware/**"
  - "Sources/CFathomHardware/**"
  - "FathomKitTests/**"
---

Before you change a hardware reader, a recorded fixture or a test that asserts a
hardware figure, read `docs/agents/hardware-testing.md`. It explains why the
replay tests exist, which Mac the fixtures came from, why the NVMe SMART log is
unrecorded, and the production seams the live readers must keep calling.
