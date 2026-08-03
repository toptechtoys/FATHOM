import FathomKit
import Testing

@Test func measurementPreservesAllThreeStates() {
    let known = Measurement<UInt64>.known(
        512,
        source: .statAllocatedBlocks
    )
    let notPublished = Measurement<UInt64>.notPublished(
        reason: "macOS does not publish this value"
    )
    let notAttributable = Measurement<UInt64>.notAttributable(
        measured: 1_024,
        explained: 512
    )

    #expect(known == .known(512, source: .statAllocatedBlocks))
    #expect(
        notPublished == .notPublished(
            reason: "macOS does not publish this value"
        )
    )
    #expect(
        notAttributable == .notAttributable(
            measured: 1_024,
            explained: 512
        )
    )
}
