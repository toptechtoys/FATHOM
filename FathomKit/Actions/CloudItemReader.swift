import Foundation

public struct CloudItemRecord: Sendable, Equatable, Codable, Identifiable {
    public let url: URL
    public let downloadingStatus: Measurement<String>
    public let isPinned: Measurement<Bool>
    public let sizeOnDisk: Measurement<UInt64>
    public let freedIfEvicted: Measurement<UInt64>

    public var id: String { url.path }

    public init(
        url: URL,
        downloadingStatus: Measurement<String>,
        isPinned: Measurement<Bool>,
        sizeOnDisk: Measurement<UInt64>,
        freedIfEvicted: Measurement<UInt64>
    ) {
        self.url = url
        self.downloadingStatus = downloadingStatus
        self.isPinned = isPinned
        self.sizeOnDisk = sizeOnDisk
        self.freedIfEvicted = freedIfEvicted
    }
}

public struct CloudItemReader: Sendable {
    public init() {}

    public func read(
        root: URL = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Mobile Documents/com~apple~CloudDocs")
    ) -> Measurement<[CloudItemRecord]> {
        let pinKey = URLResourceKey(
            rawValue: "NSURLUbiquitousItemIsExcludedFromSyncKey"
        )
        let keys: [URLResourceKey] = [
            .isRegularFileKey,
            .ubiquitousItemDownloadingStatusKey,
            .fileAllocatedSizeKey,
            pinKey
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return .notPublished(
                reason: "The iCloud Drive container is unavailable"
            )
        }
        var records: [CloudItemRecord] = []
        for case let url as URL in enumerator {
            if let record = readItem(url, keys: Set(keys), pinKey: pinKey) {
                records.append(record)
            }
        }
        return .known(records, source: .ubiquitousDownloadingStatus)
    }

    public func readItem(_ url: URL) -> CloudItemRecord? {
        let pinKey = URLResourceKey(
            rawValue: "NSURLUbiquitousItemIsExcludedFromSyncKey"
        )
        return readItem(
            url,
            keys: [
                .isRegularFileKey,
                .ubiquitousItemDownloadingStatusKey,
                .fileAllocatedSizeKey,
                pinKey
            ],
            pinKey: pinKey
        )
    }

    private func readItem(
        _ url: URL,
        keys: Set<URLResourceKey>,
        pinKey: URLResourceKey
    ) -> CloudItemRecord? {
        do {
                let values = try url.resourceValues(forKeys: keys)
                guard values.isRegularFile == true else { return nil }
                let status: Measurement<String>
                let statusText: String?
                if let published = values.ubiquitousItemDownloadingStatus {
                    statusText = published.rawValue
                    status = .known(
                        published.rawValue,
                        source: .ubiquitousDownloadingStatus
                    )
                } else {
                    statusText = nil
                    status = .notPublished(
                        reason: "iCloud did not publish downloading status"
                    )
                }
                let pinned: Measurement<Bool>
                let pinnedValue = values.allValues[pinKey] as? Bool
                if let pinnedValue {
                    pinned = .known(
                        pinnedValue,
                        source: .ubiquitousExcludedFromSync
                    )
                } else {
                    pinned = .notPublished(
                        reason: "iCloud did not publish pin state"
                    )
                }
                let allocated: Measurement<UInt64>
                if let bytes = values.fileAllocatedSize, bytes >= 0 {
                    allocated = .known(
                        UInt64(bytes),
                        source: .ubiquitousAllocatedSize
                    )
                } else {
                    allocated = .notPublished(
                        reason: "The file did not publish allocated size"
                    )
                }
                return CloudItemRecord(
                        url: url,
                        downloadingStatus: status,
                        isPinned: pinned,
                        sizeOnDisk: allocated,
                        freedIfEvicted: Self.evictable(
                            status: statusText,
                            pinned: pinnedValue,
                            allocated: allocated
                        )
                    )
            } catch {
                return CloudItemRecord(
                        url: url,
                        downloadingStatus: .notPublished(
                            reason: "Resource values failed: \(error)"
                        ),
                        isPinned: .notPublished(
                            reason: "Resource values failed: \(error)"
                        ),
                        sizeOnDisk: .notPublished(
                            reason: "Resource values failed: \(error)"
                        ),
                        freedIfEvicted: .notPublished(
                            reason: "Resource values failed: \(error)"
                        )
                    )
            }
    }

    private static func evictable(
        status: String?,
        pinned: Bool?,
        allocated: Measurement<UInt64>
    ) -> Measurement<UInt64> {
        guard let status else {
            return .notPublished(reason: "Downloading status is not published")
        }
        guard let pinned else {
            return .notPublished(reason: "Pin state is not published")
        }
        guard !pinned else {
            return .known(0, source: .ubiquitousExcludedFromSync)
        }
        guard status == URLUbiquitousItemDownloadingStatus.current.rawValue else {
            return .known(0, source: .ubiquitousDownloadingStatus)
        }
        return allocated
    }
}
