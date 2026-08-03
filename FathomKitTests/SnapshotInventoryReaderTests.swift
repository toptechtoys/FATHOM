import FathomKit
import Foundation
import Testing

@Test func snapshotInventoryIsKnownOrNamesWhyItIsNotPublished() throws {
    let inventory = try SnapshotInventoryReader().inventory(
        forVolumeAt: URL(fileURLWithPath: "/")
    )

    switch inventory {
    case let .known(snapshots, source):
        #expect(source == .fsSnapshotList)
        #expect(snapshots.allSatisfy { !$0.name.isEmpty })
    case let .notPublished(reason):
        #expect(!reason.isEmpty)
    case .notAttributable:
        Issue.record(
            "Snapshot names are either published or not published, not unattributable"
        )
    }
}
