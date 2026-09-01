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

// "Used" meant physical total minus free, and that made a healthy Mac look
// full. macOS keeps every page it can as file cache — empty RAM is wasted RAM —
// and hands it back the instant anything asks.
//
// Taken from a real reading on the reference Mac: 68.72 GB total, 35.81 GB of
// actual demand, 30.59 GB of reclaimable cache, zero swap, and the system
// reporting 91% of memory free. The old definition called that 66.63 GB used,
// 97% of the machine.

@Test func usedMeansDemandAndNotEverythingThatIsNotFree() throws {
    let snapshot = referenceMemorySnapshot()

    let used = try knownMemoryValue(snapshot.usedBytes)
    let cached = try knownMemoryValue(snapshot.cachedBytes)
    let total = try knownMemoryValue(snapshot.totalBytes)
    let free = try knownMemoryValue(snapshot.freeBytes)

    // active + wired + compressed
    #expect(used == 29_870_000_000 + 5_940_000_000 + 4_100_000)
    // inactive + speculative + purgeable, published rather than hidden
    #expect(cached == 29_610_000_000 + 240_000_000 + 740_000_000)

    // The old definition, kept here as the thing that must not come back.
    let totalMinusFree = total - free
    #expect(
        used < totalMinusFree,
        "used should be demand, not everything that is not free"
    )
    #expect(
        Double(used) / Double(total) < 0.60,
        "a machine with zero swap and 91% free read as \(Int(Double(used) / Double(total) * 100))% used"
    )
    #expect(Double(totalMinusFree) / Double(total) > 0.95)
}

@Test func theUsedFractionDoesNotSitAtNinetySevenPercent() throws {
    let snapshot = referenceMemorySnapshot()
    let fraction = try knownMemoryValue(snapshot.usedFraction)
    // 35.81 of 68.72 GB.
    #expect(fraction > 0.50 && fraction < 0.55)
}

/// A real reading from the reference Mac, in bytes.
private func referenceMemorySnapshot() -> MemorySnapshot {
    MemorySnapshot(
        totalBytes: .known(68_720_000_000, source: .sysctlPhysicalMemory),
        freeBytes: .known(2_090_000_000, source: .hostVMStatistics64),
        activeBytes: .known(29_870_000_000, source: .hostVMStatistics64),
        inactiveBytes: .known(29_610_000_000, source: .hostVMStatistics64),
        speculativeBytes: .known(240_000_000, source: .hostVMStatistics64),
        wiredBytes: .known(5_940_000_000, source: .hostVMStatistics64),
        compressedBytes: .known(4_100_000, source: .hostVMStatistics64),
        purgeableBytes: .known(740_000_000, source: .hostVMStatistics64),
        swapUsedBytes: .known(0, source: .sysctlSwapUsage),
        swapTotalBytes: .known(0, source: .sysctlSwapUsage)
    )
}

private func knownMemoryValue<Value>(
    _ measurement: FathomKit.Measurement<Value>
) throws -> Value {
    guard case let .known(value, _) = measurement else {
        throw NotKnown(measurement: String(describing: measurement))
    }
    return value
}
