# Testing hardware readers against real bytes

Read before you change `FathomKit/Hardware/`, `Sources/CFathomHardware/`, a
recorded fixture, or any test that asserts a hardware figure. Milestone M3 in
`build-and-gates.md` states the SMART finding from the build-order side.

**Test against real bytes.** Behaviour tests — that a tampered channel map
fails its signature, that energy units convert only when named, that an absent
channel reports the gap rather than a zero — prove the reader handles what it is
given. A fixture proves it reads real bytes correctly. Hardware code needs both.

`FathomKitTests/Fixtures/` holds recorded AppleSMC, IOReport and IOHID payloads,
and `RecordedSMCReplayTests.swift` and `RecordedIOReportReplayTests.swift` replay
them through the shipping decoders: 2,206 real SMC values, a 10,570-channel
IOReport inventory, a 664-channel energy delta and 45 IOHID sensors. A parser
that misreads a real payload fails a build.

**They came from a Mac15,9 M3 Max, not from the Mac mini M4 Pro that
`RELEASE-GATES.md` names.** So gate 2's *comparison against the reference
machine* is still open; what closed is the narrower and more urgent gap, that no
test had ever put real hardware bytes through these decoders at all. Capture
again on the reference machine and commit both — the manifest names the Mac, so
two recordings cannot be mistaken for each other.

**The SMART log is still unrecorded, and that is a finding rather than an
omission.** The NVMe SMART user client returns IOReturn -536870201 on Apple
silicon — `0xe00002c7`, `kIOReturnUnsupported`, not `kIOReturnNotPrivileged`.
`AppleANS3CGv2Controller` does not advertise `NVMeSMARTCapable` and offers no
such user client, so **no entitlement changes this**. Endurance on an
Apple-silicon internal SSD needs a different source, or it stays *not
published*.

Two production seams exist so the replay tests exercise the shipping path rather
than a copy of it: `IOReportSampler.decodeDelta` and
`TemperatureSensorReader.decodeSensors`, both alongside the older
`IOReportReader.decodeChannelInventory`. The live readers call them. **Keep it
that way** — a decoder the tests reach but the app does not is worth nothing.

Do not write a test that asserts a reference figure from memory.
An invented fixture is worse than no fixture: it passes, and it certifies
nothing.
