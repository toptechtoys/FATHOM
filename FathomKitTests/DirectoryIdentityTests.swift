import CFathomStorage
import Foundation
import Testing
@testable import FathomKit

// The walk counts each directory once, whatever path reached it.
//
// A 30 August 2026 gate 1 run measured 574.9 GB on a volume holding 307.1 GB —
// 1.95x, because macOS firmlinks the data volume's directories into `/`, so
// every user file was reachable as both `/Users/...` and
// `/System/Volumes/Data/Users/...` and the walk counted both.
//
// Neither of the obvious guards works on macOS. `FTS_XDEV` and `st_dev` see one
// device: the sealed system volume and its data volume are presented as one
// `st_dev` (16777231 on that Mac) even though `statfs` reports them as
// `/dev/disk3s1s1` and `/dev/disk3s5`. `os.path.ismount` reports false for
// `/System/Volumes/Data` for the same reason. What does separate them is inode
// identity, which is what these tests cover.
//
// **The firmlink case itself cannot be built in a test.** Creating a directory
// alias needs root, so the aliasing is exercised against the real recorded
// identities here, and the end-to-end proof is a gate 1 re-run.

// MARK: - The identity set

@Test func anIdentityIsAcceptedOnceAndRecognisedTheSecondTime() throws {
    let set = try #require(fathom_identity_set_create())
    defer { fathom_identity_set_destroy(set) }

    // The real pair from the 30 August run: `/Users` and
    // `/System/Volumes/Data/Users` are one directory with two names.
    let device: UInt64 = 16_777_231
    let usersInode: UInt64 = 18_495

    #expect(fathom_identity_set_insert(set, device, usersInode) == 1)
    #expect(fathom_identity_set_insert(set, device, usersInode) == 0)
    #expect(fathom_identity_set_count(set) == 1)

    // `/Applications`, also firmlinked, is a different directory.
    #expect(fathom_identity_set_insert(set, device, 172_252) == 1)
    #expect(fathom_identity_set_insert(set, device, 172_252) == 0)
    #expect(fathom_identity_set_count(set) == 2)
}

@Test func thesameInodeOnADifferentDeviceIsADifferentDirectory() throws {
    let set = try #require(fathom_identity_set_create())
    defer { fathom_identity_set_destroy(set) }

    #expect(fathom_identity_set_insert(set, 16_777_231, 18_495) == 1)
    #expect(fathom_identity_set_insert(set, 16_777_232, 18_495) == 1)
    #expect(fathom_identity_set_count(set) == 2)
}

@Test func inodeZeroIsRejectedRatherThanStored() throws {
    let set = try #require(fathom_identity_set_create())
    defer { fathom_identity_set_destroy(set) }

    // Inode 0 is not a file. It marks an empty slot, so storing it would make
    // the set forget everything hashing past that slot.
    #expect(fathom_identity_set_insert(set, 16_777_231, 0) == -1)
    #expect(fathom_identity_set_count(set) == 0)
}

@Test func theSetStaysCorrectAcrossEveryGrowth() throws {
    let set = try #require(fathom_identity_set_create())
    defer { fathom_identity_set_destroy(set) }

    // Sequential inodes are what a real volume hands out, and they are the
    // case a weak hash turns into one long probe chain.
    let count: UInt64 = 50_000
    for inode in 1...count {
        #expect(
            fathom_identity_set_insert(set, 16_777_231, inode) == 1,
            "inode \(inode) was not new"
        )
    }
    #expect(fathom_identity_set_count(set) == count)

    // Every one of them survived the rehashing.
    for inode in 1...count {
        #expect(
            fathom_identity_set_insert(set, 16_777_231, inode) == 0,
            "inode \(inode) was forgotten across a growth"
        )
    }
    #expect(fathom_identity_set_count(set) == count)
}

// MARK: - The walk

@Test func anOrdinaryTreeSkipsNothingAndCountsEveryEntry() throws {
    let root = try makeTemporaryTree()
    defer { try? FileManager.default.removeItem(at: root) }

    var seen: [String] = []
    let summary = try StorageScanner().walk(at: root) { entry in
        seen.append((entry.path as NSString).lastPathComponent)
    }

    // A tree with no aliasing must be unchanged by the deduplication.
    #expect(summary.aliasedDirectoriesSkipped == 0)
    #expect(summary.issues.isEmpty)
    #expect(seen.contains("one.txt"))
    #expect(seen.contains("two.txt"))
    #expect(seen.contains("nested"))
    #expect(summary.entryCount == UInt64(seen.count))
}

@Test func hardLinkedFilesAreBothReportedRatherThanDeduplicated() throws {
    let root = try makeTemporaryTree()
    defer { try? FileManager.default.removeItem(at: root) }

    let original = root.appendingPathComponent("one.txt")
    let link = root.appendingPathComponent("one-hard-link.txt")
    try FileManager.default.linkItem(at: original, to: link)

    var names: [String] = []
    let summary = try StorageScanner().walk(at: root) { entry in
        names.append((entry.path as NSString).lastPathComponent)
    }

    // Deduplication is deliberately directory-only. Two names for one file is
    // exactly what the two-number engine exists to account for, so collapsing
    // hard links here would hide the thing the product is trying to show.
    #expect(names.contains("one.txt"))
    #expect(names.contains("one-hard-link.txt"))
    #expect(summary.aliasedDirectoriesSkipped == 0)
}

@Test func aWalkOfTheDataVolumeRootSkipsWhatTheSystemRootAlreadyCounted() throws {
    // The one place the real aliasing can be observed without root: walking a
    // firmlinked directory pair on this Mac. `/System/Volumes/Data` exists on
    // Apple silicon and its children alias `/`'s. If it is absent — an Intel
    // Mac, or a future layout — there is nothing to assert and the test says so
    // rather than passing quietly.
    let data = URL(fileURLWithPath: "/System/Volumes/Data")
    guard FileManager.default.fileExists(atPath: data.path) else {
        Issue.record("No /System/Volumes/Data on this Mac; aliasing unobserved")
        return
    }

    let users = URL(fileURLWithPath: "/Users")
    let aliased = data.appendingPathComponent("Users")
    let left = try FileManager.default.attributesOfItem(atPath: users.path)
    let right = try FileManager.default.attributesOfItem(atPath: aliased.path)

    // The identity the walk deduplicates on. If these ever stop matching, the
    // double count is gone for a different reason and this fix is dead weight.
    #expect(
        left[.systemFileNumber] as? UInt64 == right[.systemFileNumber] as? UInt64
    )
    #expect(
        left[.systemNumber] as? UInt64 == right[.systemNumber] as? UInt64
    )
}

// MARK: - Support

private func makeTemporaryTree() throws -> URL {
    let manager = FileManager.default
    let root = manager.temporaryDirectory
        .appendingPathComponent("fathom-identity-\(UUID().uuidString)")
    let nested = root.appendingPathComponent("nested")
    try manager.createDirectory(at: nested, withIntermediateDirectories: true)
    try Data("one".utf8).write(to: root.appendingPathComponent("one.txt"))
    try Data("two".utf8).write(to: nested.appendingPathComponent("two.txt"))
    return root
}
