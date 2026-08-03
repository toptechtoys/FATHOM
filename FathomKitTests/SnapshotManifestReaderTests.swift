import Foundation
@testable import FathomKit
import Testing

@Test func emptySnapshotInventoryPublishesAnEmptyManifestWithoutMounting()
    throws
{
    let nonexistentMount = FileManager.default.temporaryDirectory
        .appending(path: "FathomNeverMounted-\(UUID().uuidString)")
    let manifests = try SnapshotManifestReader().manifests(
        forVolumeAt: URL(fileURLWithPath: "/"),
        snapshots: [],
        mountPointURL: nonexistentMount
    )

    #expect(manifests == .known([], source: .snapshotManifestDiff))
    #expect(!FileManager.default.fileExists(atPath: nonexistentMount.path))
}

@Test func snapshotManifestMergesOverlappingPhysicalReferencesExactly()
    throws
{
    let merged = try mergedSnapshotExtents(
        [
            1: [
                SnapshotPhysicalExtent(
                    device: 1,
                    deviceOffset: 0,
                    length: 4_096
                ),
                SnapshotPhysicalExtent(
                    device: 1,
                    deviceOffset: 2_048,
                    length: 4_096
                ),
                SnapshotPhysicalExtent(
                    device: 1,
                    deviceOffset: 8_192,
                    length: 4_096
                )
            ],
            2: [
                SnapshotPhysicalExtent(
                    device: 2,
                    deviceOffset: 0,
                    length: 512
                )
            ]
        ],
        snapshotName: "fixture"
    )

    #expect(
        merged == [
            SnapshotPhysicalExtent(
                device: 1,
                deviceOffset: 0,
                length: 6_144
            ),
            SnapshotPhysicalExtent(
                device: 1,
                deviceOffset: 8_192,
                length: 4_096
            ),
            SnapshotPhysicalExtent(
                device: 2,
                deviceOffset: 0,
                length: 512
            )
        ]
    )
}
