import Testing
@testable import FathomKit

@Test func physicalMemoryComesFromThePublishedSysctl() {
    switch MemoryReader.readPhysicalMemory() {
    case let .known(bytes, source):
        #expect(bytes > 0)
        #expect(source == .sysctlPhysicalMemory)
    case let .notPublished(reason):
        Issue.record("Physical memory was not published: \(reason)")
    case .notAttributable:
        Issue.record("Physical memory unexpectedly lost attribution")
    }
}

@Test func memoryReaderPublishesDirectMachAndSwapCounters() throws {
    let snapshot = MemoryReader().read()
    #expect(try known(snapshot.freeBytes) >= 0)
    #expect(try known(snapshot.activeBytes) > 0)
    #expect(try known(snapshot.wiredBytes) > 0)
    #expect(try known(snapshot.compressedBytes) >= 0)
    #expect(try known(snapshot.swapUsedBytes) <= known(snapshot.swapTotalBytes))
}

private func known(
    _ measurement: FathomKit.Measurement<UInt64>
) throws -> UInt64 {
    guard case let .known(value, _) = measurement else {
        throw MemoryFixtureError.notKnown
    }
    return value
}

private enum MemoryFixtureError: Error {
    case notKnown
}
