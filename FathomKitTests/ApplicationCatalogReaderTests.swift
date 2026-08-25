import Foundation
import Testing
@testable import FathomKit

/// Builds a fake home and application root, returns the reader and the home.
private func makeCatalogFixture(
    bundleID: String
) throws -> (reader: ApplicationCatalogReader, home: URL, appRoot: URL) {
    let base = FileManager.default.temporaryDirectory.appending(
        path: "fathom-catalog-\(UUID().uuidString)"
    )
    let appRoot = base.appending(path: "Applications")
    let home = base.appending(path: "Home")
    let contents = appRoot.appending(path: "Probe.app/Contents")
    try FileManager.default.createDirectory(
        at: contents,
        withIntermediateDirectories: true
    )
    let plist: [String: Any] = [
        "CFBundleIdentifier": bundleID,
        "CFBundleName": "Probe"
    ]
    let data = try PropertyListSerialization.data(
        fromPropertyList: plist,
        format: .xml,
        options: 0
    )
    try data.write(to: contents.appending(path: "Info.plist"))
    return (
        ApplicationCatalogReader(applicationRoots: [appRoot], home: home),
        home,
        appRoot
    )
}

@Test func leftoversCoverAllSixPlacesTheDataSourceContractNames() throws {
    // FATHOM-DATA-SOURCES.md §Applications names exactly six leftover
    // locations. `Containers` was absent from the scan for a while — the
    // copy said six places while the reader checked five — so this test
    // constructs all six and requires every one back.
    let bundleID = "com.example.probe"
    let (reader, home, _) = try makeCatalogFixture(bundleID: bundleID)
    defer { try? FileManager.default.removeItem(at: home.deletingLastPathComponent()) }

    let library = home.appending(path: "Library")
    let directories = [
        "Application Support/\(bundleID)",
        "Caches/\(bundleID)",
        "Containers/\(bundleID)",
        "Logs/\(bundleID)",
        "Saved Application State/\(bundleID).savedState"
    ]
    for path in directories {
        try FileManager.default.createDirectory(
            at: library.appending(path: path),
            withIntermediateDirectories: true
        )
    }
    let preferences = library.appending(path: "Preferences")
    try FileManager.default.createDirectory(
        at: preferences,
        withIntermediateDirectories: true
    )
    try Data().write(to: preferences.appending(path: "\(bundleID).plist"))

    guard case let .known(records, _) = reader.read() else {
        Issue.record("the catalog did not publish")
        return
    }
    let record = try #require(records.first)
    guard case let .known(leftovers, _) = record.exactLeftoverURLs else {
        Issue.record("leftovers did not publish for a bundle with an ID")
        return
    }
    let names = Set(leftovers.map {
        $0.deletingLastPathComponent().lastPathComponent
    })
    #expect(leftovers.count == 6)
    #expect(names == [
        "Application Support", "Caches", "Containers", "Logs",
        "Saved Application State", "Preferences"
    ])
}

@Test func leftoversRequireTheExactBundleIdentifierAsThePathComponent() throws {
    // A neighbouring directory that merely starts with the bundle ID must
    // not be credited: prefix matching would sweep up a second app.
    let bundleID = "com.example.probe"
    let (reader, home, _) = try makeCatalogFixture(bundleID: bundleID)
    defer { try? FileManager.default.removeItem(at: home.deletingLastPathComponent()) }

    let caches = home.appending(path: "Library/Caches")
    try FileManager.default.createDirectory(
        at: caches.appending(path: "\(bundleID)-helper"),
        withIntermediateDirectories: true
    )

    guard case let .known(records, _) = reader.read(),
          let record = records.first,
          case let .known(leftovers, _) = record.exactLeftoverURLs else {
        Issue.record("the catalog did not publish")
        return
    }
    #expect(leftovers.isEmpty)
}
