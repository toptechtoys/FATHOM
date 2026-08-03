import CoreServices
import Foundation

public struct FathomFileSystemEvent: Sendable, Equatable, Codable, Identifiable {
    public let eventID: UInt64
    public let path: String
    public let flags: UInt32
    public let observedAt: Date

    public var id: UInt64 { eventID }

    public init(
        eventID: UInt64,
        path: String,
        flags: UInt32,
        observedAt: Date
    ) {
        self.eventID = eventID
        self.path = path
        self.flags = flags
        self.observedAt = observedAt
    }
}

public enum FSEventRecorderError: Error, Sendable, Equatable {
    case noPaths
    case cannotCreateStream
    case cannotStartStream
}

public final class FSEventRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private let queue = DispatchQueue(
        label: "com.exhibinaut.fathom.fsevents",
        qos: .utility
    )
    private var stream: FSEventStreamRef?
    private var bufferedEvents: [FathomFileSystemEvent] = []
    private var continuityFailure: String?
    private var eventHandler: (@Sendable (
        Measurement<[FathomFileSystemEvent]>
    ) -> Void)?

    public init() {}

    public func setEventHandler(
        _ handler: (@Sendable (
            Measurement<[FathomFileSystemEvent]>
        ) -> Void)?
    ) {
        lock.withLock { eventHandler = handler }
    }

    public func start(
        paths: [URL],
        since eventID: UInt64 = UInt64(kFSEventStreamEventIdSinceNow)
    ) throws {
        guard !paths.isEmpty else { throw FSEventRecorderError.noPaths }
        stop()
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let watchedPaths = paths.map(\.standardizedFileURL.path) as CFArray
        guard let created = FSEventStreamCreate(
            kCFAllocatorDefault,
            fathomFSEventCallback,
            &context,
            watchedPaths,
            FSEventStreamEventId(eventID),
            2.0,
            FSEventStreamCreateFlags(
                kFSEventStreamCreateFlagUseCFTypes |
                    kFSEventStreamCreateFlagFileEvents |
                    kFSEventStreamCreateFlagWatchRoot
            )
        ) else {
            throw FSEventRecorderError.cannotCreateStream
        }
        FSEventStreamSetDispatchQueue(created, queue)
        guard FSEventStreamStart(created) else {
            FSEventStreamInvalidate(created)
            FSEventStreamRelease(created)
            throw FSEventRecorderError.cannotStartStream
        }
        lock.withLock { stream = created }
    }

    public func stop() {
        let existing = lock.withLock { () -> FSEventStreamRef? in
            defer { stream = nil }
            return stream
        }
        guard let existing else { return }
        FSEventStreamStop(existing)
        FSEventStreamInvalidate(existing)
        FSEventStreamRelease(existing)
    }

    public func drain() -> Measurement<[FathomFileSystemEvent]> {
        let drained = lock.withLock { () -> ([FathomFileSystemEvent], String?) in
            defer { bufferedEvents.removeAll(keepingCapacity: true) }
            defer { continuityFailure = nil }
            return (bufferedEvents, continuityFailure)
        }
        if let reason = drained.1 {
            return .notPublished(reason: reason)
        }
        return .known(drained.0, source: .fseventsCausalWindow)
    }

    public static func volumeUUID(for url: URL) -> String? {
        var metadata = stat()
        guard stat(url.standardizedFileURL.path, &metadata) == 0,
              let uuid = FSEventsCopyUUIDForDevice(metadata.st_dev)
        else { return nil }
        return CFUUIDCreateString(kCFAllocatorDefault, uuid) as String
    }

    public static func recommendedStoragePaths(home: URL) -> [URL] {
        [
            home.appending(path: "Library/Developer"),
            home.appending(path: "Library/Caches"),
            home.appending(path: "Library/Containers"),
            home.appending(path: "Library/Application Support"),
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/usr/local")
        ].filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    public static func isFathomPrivatePath(
        _ path: String,
        home: URL
    ) -> Bool {
        let privateRoot = home
            .appending(path: "Library/Application Support/FATHOM")
            .standardizedFileURL.path
        let normalized = URL(fileURLWithPath: path).standardizedFileURL.path
        return normalized == privateRoot ||
            normalized.hasPrefix(privateRoot + "/")
    }

    static func continuityReason(
        flags: FSEventStreamEventFlags
    ) -> String? {
        var reasons: [String] = []
        if flags & FSEventStreamEventFlags(
            kFSEventStreamEventFlagMustScanSubDirs
        ) != 0 {
            reasons.append("macOS requires a recursive rescan")
        }
        if flags & FSEventStreamEventFlags(
            kFSEventStreamEventFlagUserDropped
        ) != 0 {
            reasons.append("the client event buffer dropped events")
        }
        if flags & FSEventStreamEventFlags(
            kFSEventStreamEventFlagKernelDropped
        ) != 0 {
            reasons.append("the kernel event buffer dropped events")
        }
        if flags & FSEventStreamEventFlags(
            kFSEventStreamEventFlagEventIdsWrapped
        ) != 0 {
            reasons.append("FSEvent identifiers wrapped")
        }
        if flags & FSEventStreamEventFlags(
            kFSEventStreamEventFlagRootChanged
        ) != 0 {
            reasons.append("a watched root changed identity")
        }
        guard !reasons.isEmpty else { return nil }
        return "FSEvents continuity is not published: " +
            reasons.joined(separator: "; ")
    }

    fileprivate func receive(
        paths: CFArray,
        flags: UnsafePointer<FSEventStreamEventFlags>,
        identifiers: UnsafePointer<FSEventStreamEventId>,
        count: Int
    ) {
        let observedAt = Date()
        let events = (0..<count).compactMap { index -> FathomFileSystemEvent? in
            guard let raw = CFArrayGetValueAtIndex(paths, index) else {
                return nil
            }
            let string = Unmanaged<CFString>
                .fromOpaque(raw)
                .takeUnretainedValue() as String
            return FathomFileSystemEvent(
                eventID: UInt64(identifiers[index]),
                path: string,
                flags: UInt32(flags[index]),
                observedAt: observedAt
            )
        }
        let failure = (0..<count).compactMap {
            Self.continuityReason(flags: flags[$0])
        }.first
        let handler = lock.withLock { () -> (@Sendable (
            Measurement<[FathomFileSystemEvent]>
        ) -> Void)? in
            if eventHandler == nil {
                bufferedEvents.append(contentsOf: events)
                if let failure { continuityFailure = failure }
            }
            return eventHandler
        }
        if let handler {
            if let failure {
                handler(.notPublished(reason: failure))
            } else {
                handler(.known(events, source: .fseventsCausalWindow))
            }
        }
    }

    deinit {
        stop()
    }
}

private let fathomFSEventCallback: FSEventStreamCallback = {
    _, context, count, rawPaths, flags, identifiers in
    guard let context else { return }
    let recorder = Unmanaged<FSEventRecorder>
        .fromOpaque(context)
        .takeUnretainedValue()
    let paths = Unmanaged<CFArray>
        .fromOpaque(rawPaths)
        .takeUnretainedValue()
    recorder.receive(
        paths: paths,
        flags: flags,
        identifiers: identifiers,
        count: count
    )
}
