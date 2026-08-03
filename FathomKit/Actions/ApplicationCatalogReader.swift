import Foundation

public struct ApplicationCatalogRecord: Sendable, Equatable, Identifiable {
    public let url: URL
    public let name: Measurement<String>
    public let bundleIdentifier: Measurement<String>
    public let version: Measurement<String>
    public let lastAccessed: Measurement<Date>
    public let exactLeftoverURLs: Measurement<[URL]>

    public var id: String { url.path }

    public init(
        url: URL,
        name: Measurement<String>,
        bundleIdentifier: Measurement<String>,
        version: Measurement<String>,
        lastAccessed: Measurement<Date>,
        exactLeftoverURLs: Measurement<[URL]>
    ) {
        self.url = url
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.version = version
        self.lastAccessed = lastAccessed
        self.exactLeftoverURLs = exactLeftoverURLs
    }
}

public struct ApplicationCatalogReader: Sendable {
    private let applicationRoots: [URL]
    private let home: URL

    public init(
        applicationRoots: [URL] = [
            URL(fileURLWithPath: "/Applications"),
            FileManager.default.homeDirectoryForCurrentUser
                .appending(path: "Applications")
        ],
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.applicationRoots = applicationRoots
        self.home = home
    }

    public func read() -> Measurement<[ApplicationCatalogRecord]> {
        var appURLs: [URL] = []
        for root in applicationRoots {
            guard let contents = try? FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            appURLs.append(contentsOf: contents.filter {
                $0.pathExtension.lowercased() == "app"
            })
        }
        let records = appURLs.map(record)
            .sorted { displayName($0) < displayName($1) }
        return .known(records, source: .applicationInfoPlist)
    }

    private func record(_ url: URL) -> ApplicationCatalogRecord {
        let infoURL = url.appending(path: "Contents/Info.plist")
        let dictionary: [String: Any]?
        if let data = try? Data(contentsOf: infoURL),
           let object = try? PropertyListSerialization.propertyList(
               from: data,
               options: [],
               format: nil
           ) {
            dictionary = object as? [String: Any]
        } else {
            dictionary = nil
        }
        let bundleID = dictionary?["CFBundleIdentifier"] as? String
        let publishedName = (dictionary?["CFBundleDisplayName"] as? String)
            ?? (dictionary?["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent
        let version = (dictionary?["CFBundleShortVersionString"] as? String)
            ?? (dictionary?["CFBundleVersion"] as? String)
        let access: Measurement<Date>
        do {
            let values = try url.resourceValues(forKeys: [.contentAccessDateKey])
            access = values.contentAccessDate.map {
                .known($0, source: .contentAccessDate)
            } ?? .notPublished(
                reason: "The volume did not publish a content access date; it may use noatime"
            )
        } catch {
            access = .notPublished(
                reason: "Content access date failed: \(error)"
            )
        }
        let leftovers: Measurement<[URL]>
        if let bundleID, !bundleID.isEmpty {
            leftovers = .known(
                exactLeftovers(bundleIdentifier: bundleID),
                source: .exactBundleIDLeftoverMatch
            )
        } else {
            leftovers = .notPublished(
                reason: "The app did not publish a bundle identifier"
            )
        }
        return ApplicationCatalogRecord(
            url: url,
            name: .known(publishedName, source: .applicationInfoPlist),
            bundleIdentifier: bundleID.map {
                .known($0, source: .applicationInfoPlist)
            } ?? .notPublished(
                reason: "Info.plist has no CFBundleIdentifier"
            ),
            version: version.map {
                .known($0, source: .applicationInfoPlist)
            } ?? .notPublished(
                reason: "Info.plist has no version"
            ),
            lastAccessed: access,
            exactLeftoverURLs: leftovers
        )
    }

    private func exactLeftovers(bundleIdentifier: String) -> [URL] {
        let library = home.appending(path: "Library")
        let direct = [
            library.appending(path: "Application Support")
                .appending(path: bundleIdentifier),
            library.appending(path: "Caches")
                .appending(path: bundleIdentifier),
            library.appending(path: "Logs")
                .appending(path: bundleIdentifier),
            library.appending(path: "Saved Application State")
                .appending(path: "\(bundleIdentifier).savedState"),
            library.appending(path: "Preferences")
                .appending(path: "\(bundleIdentifier).plist")
        ]
        return direct.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func displayName(_ record: ApplicationCatalogRecord) -> String {
        guard case let .known(value, _) = record.name else {
            return record.url.lastPathComponent
        }
        return value.localizedCaseInsensitiveCompare("") == .orderedSame
            ? record.url.lastPathComponent
            : value
    }
}
