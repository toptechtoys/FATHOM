import Testing
@testable import FathomKit

@Test func zeroIsANumeralAndNeverTheWord() {
    // `ByteCountFormatStyle` spells out zero by default, and the whole app was
    // taking that default: the Network section printed a column of "Zero kB/s"
    // the first time it was run. Zero bytes is a real reading and has to look
    // like one -- and has to stay distinguishable from *not published*, which
    // is a different statement entirely.
    #expect(ByteString.file(0) == "0 bytes")
    #expect(ByteString.memory(0) == "0 bytes")
    #expect(ByteString.perSecond(0) == "0 bytes/s")
    #expect(!ByteString.file(0).lowercased().contains("zero"))
    #expect(!ByteString.memory(0).lowercased().contains("zero"))
    #expect(!ByteString.memoryGigabytes(0).lowercased().contains("zero"))
}

@Test func ordinarySizesReadTheWayTheyAlwaysDid() {
    #expect(ByteString.file(1_600_000_000) == "1.6 GB")
    #expect(ByteString.perSecond(1_600_000_000) == "1.6 GB/s")
}

@Test func aComputedSizeThatCannotBeAByteCountSaysSo() {
    // A rate multiplied out, an extrapolation, a subtraction that went
    // negative: printing whatever the conversion produced would be inventing a
    // number, and `UInt64(Double.nan)` traps outright.
    #expect(ByteString.file(rounding: Double.nan) == "outside display range")
    #expect(ByteString.file(rounding: Double.infinity) == "outside display range")
    #expect(ByteString.file(rounding: -1.0) == "outside display range")
    #expect(ByteString.file(rounding: 0.0) == "0 bytes")
    #expect(ByteString.file(rounding: 1_600_000_000.4) == "1.6 GB")
}
