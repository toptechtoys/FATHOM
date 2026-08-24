import Combine
import FathomKit
import Foundation

@MainActor
final class AttributionAppModel: ObservableObject {
    enum State {
        case disabled
        case collecting
        case recomputeRequired(String)
        case failed(String)
    }

    static let enabledKey = "attribution.enabled"
    private static let lastEventIDKey = "attribution.lastEventID"
    private static let volumeUUIDKey = "attribution.volumeUUID"

    @Published private(set) var state: State = .disabled

    /// How many curated paths the running stream is watching.
    ///
    /// The count the stream was *started* with, not the count
    /// `recommendedStoragePaths` would suggest — those differ on a Mac that
    /// has no `/usr/local`, and the readout says what is true of this machine.
    /// Zero whenever nothing is watching, which is a reading and not a gap:
    /// collection being off is a real answer to "how many".
    @Published private(set) var watchedPathCount = 0
    private let recorder = FSEventRecorder()
    private var recording = false

    func restoreIfEnabled() {
        if UserDefaults.standard.bool(forKey: Self.enabledKey) {
            start()
        }
    }

    func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
        enabled ? start() : stop()
    }

    private func start() {
        guard !recording else { return }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let paths = FSEventRecorder.recommendedStoragePaths(home: home)
        guard let currentVolumeUUID = FSEventRecorder.volumeUUID(for: home)
        else {
            watchedPathCount = 0
            state = .failed(
                "FSEvents did not publish the watched volume identity"
            )
            return
        }
        let storedVolumeUUID = UserDefaults.standard.string(
            forKey: Self.volumeUUIDKey
        )
        let volumeChanged = storedVolumeUUID != nil &&
            storedVolumeUUID != currentVolumeUUID
        let hasStoredEventID = UserDefaults.standard.object(
            forKey: Self.lastEventIDKey
        ) != nil
        let storedEventID = Int64(
            UserDefaults.standard.integer(forKey: Self.lastEventIDKey)
        )
        let since = volumeChanged || !hasStoredEventID
            ? UInt64.max
            : UInt64(bitPattern: storedEventID)
        do {
            recorder.setEventHandler { [weak self] measurement in
                Task { @MainActor [weak self] in
                    self?.receive(measurement)
                }
            }
            try recorder.start(paths: paths, since: since)
            recording = true
            watchedPathCount = paths.count
            UserDefaults.standard.set(
                currentVolumeUUID,
                forKey: Self.volumeUUIDKey
            )
            state = .collecting
            if volumeChanged {
                NotificationCenter.default.post(
                    name: .fathomStorageContinuityRescan,
                    object: "The FSEvents volume identity changed; a complete scan is required"
                )
            }
        } catch {
            recorder.setEventHandler(nil)
            watchedPathCount = 0
            state = .failed("FSEvents causal window could not start: \(error)")
        }
    }

    private func receive(
        _ measurement: FathomKit.Measurement<[FathomFileSystemEvent]>
    ) {
        if case let .notPublished(reason) = measurement {
            recorder.stop()
            recorder.setEventHandler(nil)
            recording = false
            watchedPathCount = 0
            state = .recomputeRequired(reason)
            NotificationCenter.default.post(
                name: .fathomStorageContinuityRescan,
                object: reason
            )
            return
        }
        do {
            try persist(measurement)
        } catch {
            state = .failed(
                "Causal event history could not be persisted: \(error)"
            )
            stop()
        }
    }

    private func stop() {
        recording = false
        watchedPathCount = 0
        recorder.setEventHandler(nil)
        recorder.stop()
        if case .failed = state { return }
        if case .recomputeRequired = state { return }
        state = .disabled
    }

    private func persist(
        _ measurement: FathomKit.Measurement<[FathomFileSystemEvent]>
    ) throws {
        guard case let .known(allEvents, _) = measurement,
              !allEvents.isEmpty else {
            return
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let events = allEvents.filter {
            !FSEventRecorder.isFathomPrivatePath($0.path, home: home)
        }
        if let last = allEvents.max(by: { $0.eventID < $1.eventID }) {
            UserDefaults.standard.set(
                Int64(bitPattern: last.eventID),
                forKey: Self.lastEventIDKey
            )
        }
        guard !events.isEmpty else { return }
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/FATHOM")
            .appending(path: "attribution-events.jsonl")
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if !FileManager.default.fileExists(atPath: url.path) {
            guard FileManager.default.createFile(atPath: url.path, contents: nil)
            else { throw CocoaError(.fileWriteUnknown) }
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        for event in events {
            var data = try JSONEncoder().encode(event)
            data.append(0x0A)
            try handle.write(contentsOf: data)
        }
        try handle.synchronize()
    }
}
