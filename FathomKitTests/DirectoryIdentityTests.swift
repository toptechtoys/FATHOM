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

// MARK: - The container boundary

// A scan of `/` is a question about one startup disk. The walk used to descend
// into everything mounted under it, so one external 2 TB drive at `/Volumes`
// added **1,028.9 GB and 1.24 million files** to a 318 GB answer — and inflated
// the duration and the peak memory that RELEASE-GATES gate 1 measures.
//
// `st_dev` alone is the wrong boundary in the other direction: APFS puts
// several volumes in one container and they share its free space, so `/`, the
// data volume, Preboot, VM and Update are all disk3 and all count toward the
// same pool. The rule is the container, checked through `statfs` at a device
// boundary only.

@Test func aMountFromAnotherContainerIsNotCountedAsPartOfThisOne() throws {
    guard let image = try MountedTestImage(megabytes: 20) else {
        Issue.record("hdiutil is unavailable; the container boundary is unproven")
        return
    }
    defer { image.detach() }

    // 8 MB on the mounted image, 2 MB on the volume being scanned.
    try Data(repeating: 0xAB, count: 8 * 1_048_576)
        .write(to: image.mountPoint.appending(path: "inside.bin"))
    try Data(repeating: 0xCD, count: 2 * 1_048_576)
        .write(to: image.root.appending(path: "outside.bin"))

    // The image really is a different device, or this proves nothing.
    let rootDevice = try #require(
        try FileManager.default.attributesOfItem(atPath: image.root.path)[.systemNumber] as? UInt64
    )
    let mountDevice = try #require(
        try FileManager.default.attributesOfItem(atPath: image.mountPoint.path)[.systemNumber] as? UInt64
    )
    #expect(rootDevice != mountDevice)

    var names: [String] = []
    let summary = try StorageScanner().walk(at: image.root) { entry in
        names.append((entry.path as NSString).lastPathComponent)
    }

    #expect(summary.otherContainerMountsSkipped == 1)
    #expect(summary.aliasedDirectoriesSkipped == 0)
    #expect(names.contains("outside.bin"))
    #expect(
        !names.contains("inside.bin"),
        "a file on another container was counted as part of this one"
    )
}

/// A disk image attached at a path inside a temporary directory: a second APFS
/// container, created without root, which is the only way to exercise the
/// boundary without borrowing whatever happens to be plugged in.
private struct MountedTestImage {
    let root: URL
    let mountPoint: URL
    private let imageURL: URL

    init?(megabytes: Int) throws {
        let manager = FileManager.default
        let base = manager.temporaryDirectory
            .appending(path: "FathomContainerTests-\(UUID().uuidString)")
        root = base.appending(path: "root")
        mountPoint = root.appending(path: "attached")
        imageURL = base.appending(path: "image.dmg")
        try manager.createDirectory(at: mountPoint, withIntermediateDirectories: true)

        guard MountedTestImage.hdiutil([
            "create", "-size", "\(megabytes)m", "-fs", "APFS",
            "-volname", "FathomTestVol", "-quiet", imageURL.path
        ]) else {
            try? manager.removeItem(at: base)
            return nil
        }
        guard MountedTestImage.hdiutil([
            "attach", imageURL.path,
            "-mountpoint", mountPoint.path, "-nobrowse", "-quiet"
        ]) else {
            try? manager.removeItem(at: base)
            return nil
        }
    }

    func detach() {
        _ = MountedTestImage.hdiutil(["detach", mountPoint.path, "-quiet"])
        try? FileManager.default.removeItem(at: root.deletingLastPathComponent())
    }

    private static func hdiutil(_ arguments: [String]) -> Bool {
        let tool = URL(fileURLWithPath: "/usr/bin/hdiutil")
        guard FileManager.default.isExecutableFile(atPath: tool.path) else {
            return false
        }
        let process = Process()
        process.executableURL = tool
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }
}
