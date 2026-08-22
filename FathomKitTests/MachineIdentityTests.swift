import Testing
@testable import FathomKit

@Test func theHeaderLineNamesTheMachineAndItsHistory() {
    let identity = MachineIdentity(
        model: .known("Mac16,11", source: .sysctlMachineModel),
        physicalMemoryBytes: .known(24 * 1_073_741_824, source: .sysctlPhysicalMemory)
    )
    let line = identity.headerLine(daysRecorded: 142)
    #expect(line.contains("Mac16,11"))
    #expect(line.contains("24"))
    #expect(line.contains("142 days recorded"))
}

@Test func anUnpublishedPartIsDroppedRatherThanFilledIn() {
    let identity = MachineIdentity(
        model: .notPublished(reason: "sysctl hw.model did not publish a value"),
        physicalMemoryBytes: .known(16 * 1_073_741_824, source: .sysctlPhysicalMemory)
    )
    let line = identity.headerLine(daysRecorded: 3)
    // "Unknown · 16 GB" would claim a reading that was never taken.
    #expect(!line.lowercased().contains("unknown"))
    #expect(!line.contains("—"))
    #expect(line.hasPrefix("16"))
}

@Test func theLineIsEmptyRatherThanFabricatedWhenNothingIsPublished() {
    let identity = MachineIdentity(
        model: .notPublished(reason: "no model"),
        physicalMemoryBytes: .notPublished(reason: "no memsize")
    )
    #expect(identity.headerLine(daysRecorded: nil).isEmpty)
}

@Test func noHistoryYetAndNoHistoryAtAllReadDifferently() {
    let identity = MachineIdentity(
        model: .known("Mac16,11", source: .sysctlMachineModel),
        physicalMemoryBytes: .notPublished(reason: "no memsize")
    )
    // Not read yet says nothing; read and empty says so.
    #expect(!identity.headerLine(daysRecorded: nil).contains("recording"))
    #expect(identity.headerLine(daysRecorded: 0).contains("recording since today"))
}

@Test func oneDayIsSingular() {
    let identity = MachineIdentity(
        model: .notPublished(reason: "no model"),
        physicalMemoryBytes: .notPublished(reason: "no memsize")
    )
    #expect(identity.headerLine(daysRecorded: 1) == "1 day recorded")
    #expect(identity.headerLine(daysRecorded: 2) == "2 days recorded")
}

@Test func theReaderPublishesThisMachinesModelAndMemory() {
    // Runs against the host, so it asserts shape rather than a fixture value.
    let identity = MachineIdentityReader().read()
    guard case let .known(model, source) = identity.model else {
        Issue.record("hw.model published nothing on this host")
        return
    }
    #expect(!model.isEmpty)
    #expect(source == .sysctlMachineModel)
    guard case let .known(bytes, _) = identity.physicalMemoryBytes else {
        Issue.record("hw.memsize published nothing on this host")
        return
    }
    #expect(bytes > 1_073_741_824)
}
