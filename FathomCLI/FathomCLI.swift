import CFathomHardware
import CryptoKit
import Darwin
import Foundation
import FathomKit

@main
struct FathomCommand {
    static func main() async {
        do {
            try await run(arguments: Array(CommandLine.arguments.dropFirst()))
        } catch {
            FileHandle.standardError.write(
                Data("fathom: \(error)\n".utf8)
            )
            exit(EXIT_FAILURE)
        }
    }

    private static func run(arguments: [String]) async throws {
        guard let command = arguments.first else {
            printUsage()
            return
        }

        switch command {
        case "explain":
            guard arguments.count >= 2 else {
                throw CLIError.missingPath(command: command)
            }
            let wholeVolume = arguments.dropFirst(2).contains(
                "--whole-volume"
            )
            try await explain(
                path: arguments[1],
                wholeVolume: wholeVolume
            )
        case "scan":
            guard arguments.count >= 2 else {
                throw CLIError.missingPath(command: command)
            }
            try await scan(path: arguments[1])
        case "benchmark":
            guard arguments.count >= 2 else {
                throw CLIError.missingPath(command: command)
            }
            let options = Array(arguments.dropFirst(2))
            guard options.allSatisfy({ $0 == "--enforce-reference-gates" })
            else {
                throw CLIError.invalidOptions(command: command)
            }
            try await benchmark(
                path: arguments[1],
                enforceReferenceGates:
                    options.contains("--enforce-reference-gates")
            )
        case "doctor":
            try await doctor()
        case "export-diagnostics":
            guard arguments.count >= 2 else {
                throw CLIError.missingPath(command: command)
            }
            let options = Array(arguments.dropFirst(2))
            guard options.allSatisfy({ $0 == "--include-paths" }) else {
                throw CLIError.invalidOptions(command: command)
            }
            try await exportDiagnostics(
                destinationPath: arguments[1],
                includePaths: options.contains("--include-paths")
            )
        case "recipe":
            try recipe(arguments: Array(arguments.dropFirst()))
        case "dump-channels":
            dumpChannels()
        case "capture-fixtures":
            guard arguments.count >= 2 else {
                throw CLIError.missingPath(command: command)
            }
            let options = Array(arguments.dropFirst(2))
            guard options.allSatisfy({
                $0 == "--include-unparsed-smc-bytes"
            }) else {
                throw CLIError.invalidOptions(command: command)
            }
            try await captureFixtures(
                destinationPath: arguments[1],
                includeUnparsedSMCBytes: options.contains(
                    "--include-unparsed-smc-bytes"
                )
            )
        case "help", "--help", "-h":
            printUsage()
        default:
            throw CLIError.unknownCommand(command)
        }
    }

    private static func explain(
        path: String,
        wholeVolume: Bool
    ) async throws {
        let requestedURL = URL(fileURLWithPath: path).standardizedFileURL
        let values = try requestedURL.resourceValues(
            forKeys: [.volumeURLKey]
        )
        let volumeURL = try requireVolumeURL(
            values.volume,
            for: requestedURL
        )
        let scanURL = wholeVolume ? volumeURL : requestedURL
        let scope: ScanScope = wholeVolume ? .wholeVolume : .subtree
        let result = try await StorageEngine().scan(
            at: scanURL,
            scope: scope
        )
        guard let entry = result.entries.first(where: {
            $0.path == requestedURL.path
        }) else {
            throw CLIError.pathNotFoundAfterScan(requestedURL.path)
        }

        let deletionPaths: Set<String>
        if entry.kind == .directory {
            let prefix = requestedURL.path.hasSuffix("/")
                ? requestedURL.path
                : requestedURL.path + "/"
            deletionPaths = Set(
                result.inspectedFiles.compactMap {
                    let candidate = $0.entry.path
                    return candidate == requestedURL.path ||
                        candidate.hasPrefix(prefix)
                        ? candidate
                        : nil
                }
            )
        } else {
            deletionPaths = [requestedURL.path]
        }
        let deletion = result.estimateDeletion(of: deletionPaths)

        print(requestedURL.path)
        print("  logical: \(render(entry.logicalSize))")
        print("  on disk: \(render(deletion.sizeOnDisk))")
        print("  freed if deleted: \(render(deletion.freedIfDeleted))")
        if !wholeVolume {
            print(
                "  note: subtree mode cannot prove references outside the scan; use --whole-volume for an attributable result"
            )
        }
        if !result.issues.isEmpty {
            print("  scan issues: \(result.issues.count)")
        }
    }

    private static func scan(path: String) async throws {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        let values = try url.resourceValues(forKeys: [.volumeURLKey])
        let volumeURL = try requireVolumeURL(values.volume, for: url)
        let scope: ScanScope =
            url.path == volumeURL.standardizedFileURL.path
            ? .wholeVolume
            : .subtree
        let start = ContinuousClock.now
        let result = try await StorageEngine().scan(at: url, scope: scope)
        let duration = start.duration(to: .now)

        print("root: \(result.rootURL.path)")
        print("entries: \(result.entries.count)")
        print("regular files inspected: \(result.inspectedFiles.count)")
        print("issues: \(result.issues.count)")
        print("duration: \(format(duration: duration))")
        print("snapshot inventory: \(renderSnapshots(result.snapshotInventory))")
        print(
            "open-file completeness: \(renderCompleteness(result.openFileReferences.completeIdentities))"
        )

        let accounting = StorageAccountingBuilder().build(from: result)
        switch accounting {
        case let .known(snapshot, _):
            let root = snapshot.nodes[Int(snapshot.rootID.rawValue)]
            print("accounted on disk: \(render(root.subtreeSizeOnDisk))")
            print("clone families: \(snapshot.cloneFamilies.count)")
        case let .notPublished(reason):
            print("accounted on disk: not published — \(reason)")
        case .notAttributable:
            print("accounted on disk: not attributable")
        }
    }

    private static func benchmark(
        path: String,
        enforceReferenceGates: Bool
    ) async throws {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        let volumeURL = try url.resourceValues(forKeys: [.volumeURLKey])
            .volume ?? url
        let isWholeVolume = url.resolvingSymlinksInPath().path ==
            volumeURL.resolvingSymlinksInPath().path
        let indexURL = FileManager.default.temporaryDirectory
            .appending(path: "fathom-benchmark.sqlite")
        let snapshotMountURL = FileManager.default.temporaryDirectory
            .appending(path: "fathom-benchmark-snapshot-mount")
        let index = try StorageIndex(url: indexURL)

        let start = ContinuousClock.now
        let traversal = try await index.stageTraversal(
            at: url,
            scope: isWholeVolume ? .wholeVolume : .subtree
        )
        let extentSummary = try await index.inspectStagedExtents(
            scanID: traversal.scanID
        )
        let accounting = try await index.reduceStagedAccounting(
            scanID: traversal.scanID
        )
        var freeable: FathomKit.Measurement<UInt64> = .notPublished(
            reason: "Freeable accounting requires a whole-volume benchmark"
        )
        if isWholeVolume {
            let snapshots = try SnapshotInventoryReader().inventory(
                forVolumeAt: volumeURL
            )
            let coverage: FathomKit.Measurement<[String]>
            switch snapshots {
            case let .known(inventory, _):
                do {
                    coverage = try await index.stageSnapshotReferences(
                        scanID: traversal.scanID,
                        volumeURL: volumeURL,
                        snapshots: inventory,
                        mountPointURL: snapshotMountURL
                    )
                } catch {
                    coverage = .notPublished(
                        reason: "Read-only snapshot inspection failed: \(error)"
                    )
                }
            case let .notPublished(reason):
                coverage = .notPublished(reason: reason)
            case .notAttributable:
                coverage = .notPublished(
                    reason: "Snapshot inventory is not attributable"
                )
            }
            let openFiles = try OpenFileReferenceReader().inventory()
            let reduced = try await index.reduceStagedFreeableAccounting(
                scanID: traversal.scanID,
                snapshotInventory: snapshots,
                snapshotCoverage: coverage,
                openFileIdentities: openFiles.completeIdentities
            )
            freeable = reduced.freedIfDeleted
        }
        let duration = start.duration(to: .now)
        let seconds = durationSeconds(duration)
        let rate = seconds > 0
            ? Double(traversal.entryCount) / seconds
            : 0
        let residentBytes = peakResidentBytes()
        let issueCount = traversal.issues.count +
            Int(extentSummary.failedFileCount)

        print("path: \(url.path)")
        print("entries: \(traversal.entryCount)")
        print("regular files inspected: \(extentSummary.inspectedFileCount)")
        print("duration: \(format(duration: duration))")
        print(String(format: "entries/second: %.0f", rate))
        print("peak resident bytes: \(residentBytes)")
        print("issues: \(issueCount)")
        print("accounted on disk: \(render(accounting.sizeOnDisk))")
        print("freed if deleted: \(render(freeable))")
        print("index: \(indexURL.path)")
        await index.close()

        if enforceReferenceGates {
            guard isWholeVolume else {
                throw CLIError.referenceGateFailed(
                    "the reference gate requires the volume root"
                )
            }
            guard seconds < 30 else {
                throw CLIError.referenceGateFailed(
                    "scan duration was \(String(format: "%.3f", seconds)) seconds; required under 30"
                )
            }
            guard residentBytes < 300_000_000 else {
                throw CLIError.referenceGateFailed(
                    "peak resident memory was \(residentBytes) bytes; required under 300000000"
                )
            }
            guard issueCount == 0 else {
                throw CLIError.referenceGateFailed(
                    "the scan reported \(issueCount) inspection issues"
                )
            }
            guard case .known = freeable else {
                throw CLIError.referenceGateFailed(
                    "freed-if-deleted was not fully published"
                )
            }
            print("reference gates: PASS")
        }
    }

    private static func doctor() async throws {
        for line in try await doctorReport() {
            print(line)
        }
    }

    private static func doctorReport() async throws -> [String] {
        var lines = [
            "FATHOM doctor",
            "macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "hardware model: \(sysctlString("hw.model"))",
            "Full Disk Access: \(renderBoolean(FullDiskAccessReader().read()))"
        ]
        let support = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/FATHOM")
        let indexURL = support.appending(path: "storage.sqlite")
        if FileManager.default.fileExists(atPath: indexURL.path) {
            let bytes = try? indexURL.resourceValues(
                forKeys: [.fileSizeKey]
            ).fileSize
            lines.append(
                "index size: \(bytes.flatMap { $0 }.map { "\($0) bytes" } ?? "not published")"
            )
            do {
                let diagnostics = try StorageIndex.readOnlyDiagnostics(at: indexURL)
                lines.append("index schema: \(diagnostics.schemaVersion)")
                lines.append(
                    "last scan duration: \(diagnostics.lastScanDurationSeconds.map { "\($0) seconds" } ?? "not published")"
                )
            } catch {
                lines.append("index schema: not published — \(error)")
                lines.append("last scan duration: not published — index unavailable")
            }
        } else {
            lines.append("index size: not published — no completed indexed scan")
            lines.append("index schema: not published — index does not exist")
            lines.append("last scan duration: not published — no completed indexed scan")
        }
        lines.append(
            "reclaim journal entries: \(lineCount(at: support.appending(path: "reclaim-journal.jsonl")))"
        )
        lines.append(
            "cloud journal entries: \(lineCount(at: support.appending(path: "cloud-eviction-journal.jsonl")))"
        )

        let snapshots = try SnapshotInventoryReader().inventory(
            forVolumeAt: URL(fileURLWithPath: "/")
        )
        lines.append("snapshot API: \(renderSnapshots(snapshots))")
        let openFiles = try OpenFileReferenceReader().inventory()
        lines.append(
            "open-file identities observed: \(openFiles.observedIdentities.count)"
        )
        lines.append(
            "processes denying open-file inspection: \(openFiles.inaccessibleProcessCount)"
        )

        let smart = NVMeSMARTReader().read()
        lines.append(
            "NVMe SMART percentage used: \(renderScalar(smart.percentageUsed))"
        )
        lines.append("NVMe SMART bytes written: \(render(smart.bytesWritten))")
        let smcSession = SMCProbeSession()
        let smc = SMCReader().readSnapshot(session: smcSession)
        lines.append("SMC key inventory: \(renderStringList(smc.keyInventory))")
        var validSMCKeys = smc.fanSpeedsRPM.compactMap { reading in
            if case .known = reading.value { return reading.key }
            return nil
        }
        if case .known = smc.totalSystemPowerWatts {
            validSMCKeys.append("PSTR")
        }
        lines.append(
            "SMC probed valid keys: \(validSMCKeys.sorted().joined(separator: ", "))"
        )
        lines.append(
            "SMC session blacklist: \(smcSession.blacklistedKeys.joined(separator: ", "))"
        )
        lines.append(
            "SMC fan speed keys: \(smc.fanSpeedsRPM.map(\.key).joined(separator: ", "))"
        )
        lines.append("SMC PSTR: \(renderDouble(smc.totalSystemPowerWatts))")

        let ioReport = IOReportReader().channelInventory()
        switch ioReport {
        case .known:
            lines.append("IOReport private symbols resolved: yes")
        case let .notPublished(reason):
            lines.append("IOReport private symbols resolved: not published — \(reason)")
        case .notAttributable:
            lines.append("IOReport private symbols resolved: not attributable")
        }
        lines.append("IOReport channels: \(renderChannels(ioReport))")
        switch IOReportChannelMapLoader().loadBundled() {
        case let .known(map, source):
            lines.append(
                "IOReport channel map: v\(map.version), \(map.channels.count) labels [\(source.rawValue)]"
            )
        case let .notPublished(reason):
            lines.append("IOReport channel map: not published — \(reason)")
        case .notAttributable:
            lines.append("IOReport channel map: not attributable")
        }
        do {
            let sampler = try IOReportSampler()
            let power = try await sampler.samplePower()
            lines.append("IOReport energy sample: \(renderPower(power))")
        } catch {
            lines.append("IOReport energy sample: not published — \(error)")
        }
        lines.append(
            "IOHID temperatures: \(renderTemperatures(TemperatureSensorReader().read()))"
        )
        return lines
    }

    private static func exportDiagnostics(
        destinationPath: String,
        includePaths: Bool
    ) async throws {
        let destination = URL(fileURLWithPath: destinationPath)
            .standardizedFileURL
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw CLIError.destinationExists(destination.path)
        }

        try FileManager.default.createDirectory(
            at: destination,
            withIntermediateDirectories: false
        )
        let support = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/FATHOM")
        let readme = [
            "FATHOM diagnostics export",
            "generated: \(Date().formatted(.iso8601))",
            "paths included: \(includePaths ? "yes — explicit opt-in" : "no — SHA-256 tokens")"
        ]
        try Data((readme.joined(separator: "\n") + "\n").utf8).write(
            to: destination.appending(path: "README.txt"),
            options: .atomic
        )
        let report = try await doctorReport()
        try Data((report.joined(separator: "\n") + "\n").utf8).write(
            to: destination.appending(path: "doctor.txt"),
            options: .atomic
        )

        for name in ["reclaim-journal.jsonl", "cloud-eviction-journal.jsonl"] {
            let source = support.appending(path: name)
            let target = destination.appending(path: name)
            if FileManager.default.fileExists(atPath: source.path) {
                let data = try Data(contentsOf: source)
                let redacted = try DiagnosticsRedactor.redactJSONLines(
                    data,
                    includePaths: includePaths
                )
                try redacted.write(to: target, options: .atomic)
            } else {
                try Data("not published — no journal exists\n".utf8)
                    .write(to: target, options: .atomic)
            }
        }

        let channelMap = IOReportChannelMapLoader().loadBundled()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(channelMap).write(
            to: destination.appending(path: "active-channel-map.json"),
            options: .atomic
        )

        try Data(
            "not published — FATHOM has no persisted os_log archive to export\n".utf8
        ).write(
            to: destination.appending(path: "recent-os-log.txt"),
            options: .atomic
        )

        print("exported diagnostics: \(destination.path)")
        print(includePaths
            ? "paths: included by explicit opt-in"
            : "paths: redacted with stable SHA-256 tokens")
    }

    // MARK: - capture-fixtures
    //
    // RELEASE-GATES.md gate 2 is the only one-shot gate in the project: the
    // reference Mac mini session is the single moment anyone can record what
    // its hardware actually returns. Until this command existed no layer of
    // FATHOM could hand anyone a payload — `NVMeSMARTReader.read()` throws away
    // 495 of the log page's 512 bytes, `SMCReader.readNumericKey` decodes to a
    // Double and drops the wire bytes, and both IOReport plists and the IOHID
    // plist were decoded and freed inside their readers without ever touching
    // disk. `dump-channels` prints a derived TSV, not a payload.
    //
    // Exit codes, deliberately only two, and documented in `printUsage()`:
    //
    //   0  the capture ran and `capture-manifest.json` was written. A payload
    //      this Mac does not publish is an *outcome*, not a failure
    //      (RELEASE-GATES.md), so it does not change the status — the manifest
    //      and the printed summary say how many gaps there were.
    //   1  the capture could not run at all: the destination exists, the
    //      directory could not be created, a file could not be written, or an
    //      option was not understood. Thrown, and handled by `main()`.
    //
    // No third code. `scripts/reference-pass.sh` spends 3 on "missing
    // prerequisite", and a status that means one thing to the script and
    // another to the CLI is a status nobody can act on. A caller that wants to
    // know whether anything was missed reads `summary.notPublished` out of the
    // manifest, which is the same number this command prints on its last line.
    private static func captureFixtures(
        destinationPath: String,
        includeUnparsedSMCBytes: Bool
    ) async throws {
        let destination = URL(fileURLWithPath: destinationPath)
            .standardizedFileURL
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw CLIError.destinationExists(destination.path)
        }
        try FileManager.default.createDirectory(
            at: destination,
            withIntermediateDirectories: false
        )

        var records: [CaptureRecord] = []

        // The NVMe log page first: it is the payload with the narrowest window
        // — it needs the read-only IONVMeSMART user client, which is the thing
        // most likely to be denied — and the one gate 2 names first.
        records.append(
            try write(
                outcome: outcome(of: NVMeSMARTReader().readRawLogPage()),
                named: "nvme-smart-log-page.bin",
                in: destination,
                note: "NVMe SMART / Health Information log page 0x02, \(FATHOM_NVME_SMART_LOG_PAGE_LENGTH) bytes, exactly as the controller returned it. Log page 0x02 is counters; the controller serial number lives in Identify Controller, which FATHOM never reads."
            )
        )

        records.append(
            try write(
                outcome: encoded(SMCReader().readKeyInventory()),
                named: "smc-key-inventory.json",
                in: destination,
                note: "Every four-character key AppleSMC enumerated on this Mac, in the order it enumerated them."
            )
        )

        let smc = captureSMCValues(
            includeUnparsedBytes: includeUnparsedSMCBytes
        )
        records.append(
            try write(
                outcome: smc.outcome,
                named: "smc-key-values.json",
                in: destination,
                note: smc.note
            )
        )

        records.append(
            try write(
                outcome: outcome(
                    of: IOReportReader().channelInventoryPayload()
                ),
                named: "ioreport-channel-inventory.plist",
                in: destination,
                note: "The binary property list the C bridge builds from libIOReport's channel enumeration. It is raw down to the bridge's own flattening (Sources/CFathomHardware/FathomHardware.c), not down to libIOReport's dictionaries — a fixture of it tests the Swift decoder against real values and says nothing about the flattening."
            )
        )

        let ioReport = captureIOReport(sampleSeconds: ioReportSampleSeconds)
        records.append(
            try write(
                outcome: ioReport.subscribedChannels,
                named: "ioreport-subscribed-channels.plist",
                in: destination,
                note: "The channel set IOReportCreateSubscription actually granted this process, which is what records the channels this Mac agreed to publish. Requested groups: \(ioReportRequestedGroups.joined(separator: ", "))."
            )
        )
        records.append(
            try write(
                outcome: ioReport.delta,
                named: "ioreport-delta-sample.plist",
                in: destination,
                note: "A delta over \(String(format: "%.3f", ioReport.elapsedSeconds)) seconds. The interval travels with the payload in this manifest because IOReportSampler.watts() divides by it — a delta fixture without its interval cannot be replayed, only guessed at."
            )
        )

        records.append(
            try write(
                outcome: captureIOHIDTemperatures(),
                named: "iohid-temperature-sensors.plist",
                in: destination,
                note: "IOHIDEventSystem temperature events (usage page 0xff00, usage 5, event type 15), serialized by the C bridge."
            )
        )

        let manifest = CaptureManifest(
            capturedAt: Date().formatted(.iso8601),
            commit: ProcessInfo.processInfo
                .environment["FATHOM_REFERENCE_COMMIT"] ?? "not published — FATHOM_REFERENCE_COMMIT was not set",
            destinationToken: DiagnosticsRedactor.pathToken(destination.path),
            machine: captureMachineIdentity(),
            ioReportRequestedGroups: ioReportRequestedGroups,
            ioReportSampleElapsedSeconds: ioReport.elapsedSeconds,
            nvmeLogPageLength: Int(FATHOM_NVME_SMART_LOG_PAGE_LENGTH),
            smcByteHandling: smc.byteHandling,
            payloads: records,
            summary: CaptureSummary(
                captured: records.filter { $0.state == "captured" }.count,
                notPublished: records.filter {
                    $0.state == "not published"
                }.count,
                notAttributable: records.filter {
                    $0.state == "not attributable"
                }.count
            )
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(
            to: destination.appending(path: "capture-manifest.json"),
            options: .atomic
        )

        print("capture-fixtures: \(destination.path)")
        print(
            "capture-fixtures: \(manifest.summary.captured) captured, \(manifest.summary.notPublished) not published, \(manifest.summary.notAttributable) not attributable"
        )
    }

    /// The interval the IOReport delta is taken over.
    ///
    /// One second rather than `IOReportSampler`'s 200 ms default: the energy
    /// counters are integers, and over 200 ms the small channels can move by
    /// single digits or not at all, which produces a fixture whose watts
    /// conversion is dominated by quantisation rather than by the hardware.
    private static let ioReportSampleSeconds = 1.0

    /// The five groups `fathom_ioreport_sampler_create` subscribes to
    /// (Sources/CFathomHardware/FathomHardware.c). Recorded beside the
    /// subscription payload because the payload says what was *granted* and
    /// only this says what was *asked for*; the difference is the measurement.
    private static let ioReportRequestedGroups = [
        "Energy Model",
        "CPU Stats",
        "GPU Stats",
        "AMC Stats",
        "NVMe"
    ]

    /// What a capture attempt produced.
    ///
    /// One case per `Measurement` state and no fourth. A payload this Mac will
    /// not publish is written as a reason file and never as an empty or
    /// substituted fixture: an invented fixture is worse than no fixture,
    /// because it passes and certifies nothing.
    private enum CaptureOutcome {
        case captured(Data, source: String)
        case notPublished(reason: String)
        case notAttributable(description: String)
    }

    private static func outcome(
        of measurement: FathomKit.Measurement<Data>
    ) -> CaptureOutcome {
        switch measurement {
        case let .known(data, source):
            return .captured(data, source: source.rawValue)
        case let .notPublished(reason):
            return .notPublished(reason: reason)
        case let .notAttributable(measured, explained):
            return .notAttributable(
                description: "measured \(measured.count) bytes, explained \(explained.count) bytes"
            )
        }
    }

    private static func encoded<T: Encodable>(
        _ measurement: FathomKit.Measurement<T>
    ) -> CaptureOutcome {
        switch measurement {
        case let .known(value, source):
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                return .captured(
                    try encoder.encode(value),
                    source: source.rawValue
                )
            } catch {
                return .notPublished(
                    reason: "the reading could not be encoded: \(error)"
                )
            }
        case let .notPublished(reason):
            return .notPublished(reason: reason)
        case .notAttributable:
            return .notAttributable(
                description: "the reading is not attributable"
            )
        }
    }

    /// Writes one payload, or the reason there is not one, and returns the row
    /// the manifest records it under.
    private static func write(
        outcome: CaptureOutcome,
        named name: String,
        in directory: URL,
        note: String
    ) throws -> CaptureRecord {
        switch outcome {
        case let .captured(data, source):
            try data.write(
                to: directory.appending(path: name),
                options: .atomic
            )
            let digest = SHA256.hash(data: data).map {
                String(format: "%02x", $0)
            }.joined()
            print("captured \(name): \(data.count) bytes")
            return CaptureRecord(
                name: name,
                state: "captured",
                source: source,
                reason: nil,
                byteCount: data.count,
                sha256: digest,
                note: note
            )
        case let .notPublished(reason):
            try Data((reason + "\n").utf8).write(
                to: directory.appending(path: "\(name).notpublished.txt"),
                options: .atomic
            )
            print("not published \(name): \(reason)")
            return CaptureRecord(
                name: name,
                state: "not published",
                source: nil,
                reason: reason,
                byteCount: nil,
                sha256: nil,
                note: note
            )
        case let .notAttributable(description):
            try Data((description + "\n").utf8).write(
                to: directory.appending(path: "\(name).notattributable.txt"),
                options: .atomic
            )
            print("not attributable \(name): \(description)")
            return CaptureRecord(
                name: name,
                state: "not attributable",
                source: nil,
                reason: description,
                byteCount: nil,
                sha256: nil,
                note: note
            )
        }
    }

    /// The nine four-character type codes `fathom_smc_decode_numeric`
    /// understands. Everything else is free-form: AppleSMC publishes character
    /// arrays and vendor-defined structures whose contents this project has
    /// never enumerated on a reference machine.
    private static let decodableSMCTypes: Set<String> = [
        "ui8 ", "ui16", "ui32",
        "si8 ", "si16", "si32",
        "sp78", "fpe2", "flt "
    ]

    /// Reads every enumerated SMC key's wire bytes for the fixture.
    ///
    /// **These fixtures are committed to a public repository, so the default
    /// withholds any value the shipping decoder cannot read.** The nine types
    /// above are fixed-width numbers and cannot carry a serial; the rest are
    /// undocumented byte runs, and AppleSMC is known to publish character-array
    /// keys. Withholding by default costs the fixture nothing — the replay test
    /// drives `SMCReader.decodeNumeric`, which refuses every other type anyway
    /// — and publishing by default would stake a machine's identity on nobody
    /// having enumerated the key space first. The key, its declared type and
    /// its declared size are always recorded, so what was withheld is visible
    /// rather than absent. `--include-unparsed-smc-bytes` opts out, for a
    /// capture that is not going to be committed.
    private static func captureSMCValues(
        includeUnparsedBytes: Bool
    ) -> (outcome: CaptureOutcome, note: String, byteHandling: String) {
        let handling = includeUnparsedBytes
            ? "every enumerated key's bytes, including types the shipping decoder cannot read — --include-unparsed-smc-bytes was given"
            : "bytes recorded only for the types fathom_smc_decode_numeric reads; every other key keeps its name, type and size and withholds its bytes"
        // Per-key progress on stderr, not stdout: individual SMC keys are known
        // to stall, `fathom_smc_read_key` opens and closes a fresh AppleSMC
        // connection per key, and a silent hang at key 37 of 1,200 is
        // indistinguishable from a slow machine. stderr so the captured stdout
        // log stays the record of what was captured.
        let inventory = SMCReader().readRawInventory { read, total, key in
            FileHandle.standardError.write(
                Data("smc key \(read + 1)/\(total): \(key)\n".utf8)
            )
        }
        switch inventory {
        case let .known(raw, source):
            var values: [CapturedSMCValue] = []
            var withheld = 0
            for value in raw.values {
                let readable = decodableSMCTypes.contains(value.dataType)
                if includeUnparsedBytes || readable {
                    values.append(
                        CapturedSMCValue(
                            key: value.key,
                            dataType: value.dataType,
                            dataSize: value.dataSize,
                            bytes: value.bytes.base64EncodedString(),
                            withheld: nil
                        )
                    )
                } else {
                    withheld += 1
                    values.append(
                        CapturedSMCValue(
                            key: value.key,
                            dataType: value.dataType,
                            dataSize: value.dataSize,
                            bytes: nil,
                            withheld: "type \(value.dataType) is not one the shipping decoder reads; bytes withheld from a fixture bound for a public repository"
                        )
                    )
                }
            }
            let file = CapturedSMCInventory(
                byteHandling: handling,
                values: values.sorted { $0.key < $1.key },
                refusedKeys: raw.refusedKeys.sorted { $0.key < $1.key },
                readKeyCount: values.count,
                withheldByteCount: withheld,
                refusedKeyCount: raw.refusedKeys.count
            )
            let note = "\(values.count) keys read, \(withheld) with bytes withheld, \(raw.refusedKeys.count) refused by AppleSMC. A refused key is kept with its IOReturn rather than dropped: gate 2 asks what this Mac will not publish, and a shorter list with no explanation answers a different question."
            return (
                encoded(FathomKit.Measurement.known(file, source: source)),
                note,
                handling
            )
        case let .notPublished(reason):
            return (
                .notPublished(reason: reason),
                "AppleSMC published no readable key inventory, so no key values could be read.",
                handling
            )
        case .notAttributable:
            return (
                .notAttributable(
                    description: "the AppleSMC key inventory is not attributable"
                ),
                "The AppleSMC key inventory is not attributable, so the values below it cannot be either.",
                handling
            )
        }
    }

    /// Captures the IOReport subscription and one delta from a single sampler.
    ///
    /// This drives the C entry points directly rather than `IOReportSampler`,
    /// because the actor exposes neither its handle nor its payloads — the
    /// subscription copy has had zero Swift callers since it was written. The
    /// bytes are produced by the same `fathom_ioreport_sampler_*` functions the
    /// shipping reader uses, so the fixture is the same payload; what this path
    /// does not share is the actor's decode, which is precisely the code the
    /// fixture exists to test. Worth moving into `IOReportSampler` when that
    /// file is next open.
    private static func captureIOReport(
        sampleSeconds: Double
    ) -> (
        subscribedChannels: CaptureOutcome,
        delta: CaptureOutcome,
        elapsedSeconds: Double
    ) {
        var sampler: fathom_ioreport_sampler?
        var errorCode: Int32 = 0
        guard fathom_ioreport_sampler_create(
            &sampler,
            &errorCode
        ) == 0, let sampler else {
            let reason = "IOReport would not open a subscription (bridge error \(errorCode))"
            return (
                .notPublished(reason: reason),
                .notPublished(reason: reason),
                0
            )
        }
        defer { fathom_ioreport_sampler_destroy(sampler) }

        // The three `source` strings below name the API the bytes came from,
        // the way `DataSource` does for a rendered value. Two of them are
        // `DataSource` raw values; the subscription has no case because nothing
        // renders it, so it is named after the call that produces it.
        let subscribed = copyIOReportPayload(
            source: "libIOReport.IOReportCreateSubscription",
            failureReason: { "IOReport did not publish its granted channel set (bridge error \($0))" }
        ) { bytes, length, code in
            fathom_ioreport_sampler_copy_subscribed_channels(
                sampler,
                bytes,
                length,
                code
            )
        }

        guard fathom_ioreport_sampler_prime(sampler, &errorCode) == 0 else {
            return (
                subscribed,
                .notPublished(
                    reason: "IOReport would not take a baseline sample (bridge error \(errorCode))"
                ),
                0
            )
        }
        let clock = ContinuousClock()
        let start = clock.now
        // A blocking sleep rather than `Task.sleep`: this is the only work in
        // flight, and the elapsed figure recorded beside the payload has to be
        // the interval the counters actually spanned.
        Thread.sleep(forTimeInterval: sampleSeconds)
        let delta = copyIOReportPayload(
            source: DataSource.ioReportSampleDelta.rawValue,
            failureReason: { "IOReport did not publish a delta (bridge error \($0))" }
        ) { bytes, length, code in
            fathom_ioreport_sampler_copy_delta(sampler, bytes, length, code)
        }
        let components = start.duration(to: clock.now).components
        let elapsed = Double(components.seconds) +
            Double(components.attoseconds) / 1e18
        return (subscribed, delta, elapsed)
    }

    private static func captureIOHIDTemperatures() -> CaptureOutcome {
        copyIOReportPayload(
            source: DataSource.ioHIDTemperatureEvent.rawValue,
            failureReason: { "IOHIDEventSystem published no temperature events (bridge error \($0))" }
        ) { bytes, length, code in
            fathom_iohid_copy_temperature_sensors(bytes, length, code)
        }
    }

    /// Shared shape for the three bridge calls that hand back a malloc'd
    /// property list: call, guard the range, copy, free.
    private static func copyIOReportPayload(
        source: String,
        failureReason: (Int32) -> String,
        copy: (
            UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>,
            UnsafeMutablePointer<UInt64>,
            UnsafeMutablePointer<Int32>
        ) -> Int32
    ) -> CaptureOutcome {
        var bytes: UnsafeMutablePointer<UInt8>?
        var length: UInt64 = 0
        var errorCode: Int32 = 0
        guard copy(&bytes, &length, &errorCode) == 0, let bytes else {
            return .notPublished(reason: failureReason(errorCode))
        }
        defer { fathom_hardware_free(bytes) }
        guard length <= UInt64(Int.max) else {
            return .notPublished(
                reason: "the payload exceeds the process range"
            )
        }
        return .captured(
            Data(bytes: bytes, count: Int(length)),
            source: source
        )
    }

    /// Which Mac this is. Every figure in gate 2 is a figure about one machine,
    /// and a fixture with no machine beside it is a fixture nobody can check.
    private static func captureMachineIdentity() -> CaptureMachineIdentity {
        var name = utsname()
        let architecture = uname(&name) == 0
            ? withUnsafeBytes(of: &name.machine) { raw in
                String(
                    decoding: raw.prefix { $0 != 0 }.map { UInt8($0) },
                    as: UTF8.self
                )
            }
            : "not published"
        return CaptureMachineIdentity(
            hardwareModel: sysctlString("hw.model"),
            chipBrand: sysctlString("machdep.cpu.brand_string"),
            architecture: architecture,
            appleSilicon: sysctlFlag("hw.optional.arm64"),
            rosettaTranslated: sysctlFlag("sysctl.proc_translated"),
            kernelOSVersion: sysctlString("kern.osversion"),
            operatingSystemVersion: ProcessInfo.processInfo
                .operatingSystemVersionString
        )
    }

    private static func recipe(arguments: [String]) throws {
        guard arguments.first == "test", arguments.count >= 2 else {
            throw CLIError.invalidRecipeCommand
        }
        var home = FileManager.default.homeDirectoryForCurrentUser
        var index = 2
        while index < arguments.count {
            guard arguments[index] == "--home",
                  index + 1 < arguments.count else {
                throw CLIError.invalidOptions(command: "recipe test")
            }
            home = URL(fileURLWithPath: arguments[index + 1])
                .standardizedFileURL
            index += 2
        }
        let catalogURL = URL(fileURLWithPath: arguments[1])
            .standardizedFileURL
        let payload = try Data(contentsOf: catalogURL)
        let catalogPayload: Data
        if (try JSONSerialization.jsonObject(with: payload)) is [String: Any] {
            let object = try JSONSerialization.jsonObject(with: payload)
            catalogPayload = try JSONSerialization.data(withJSONObject: [object])
        } else {
            catalogPayload = payload
        }
        let catalog = try ReclaimRecipeCatalog.decode(
            catalogPayload,
            currentAppVersion: "1.0.0"
        )
        for recipe in catalog.recipes {
            let match = try catalog.match(recipe, home: home)
            print(
                "PASS \(recipe.identifier): \(match.paths.count) matches; cap \(recipe.maximumMatches); cost: \(recipe.regenerationCost)"
            )
        }
        print("recipe test: PASS")
    }

    private static func lineCount(at url: URL) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return "0"
        }
        defer { try? handle.close() }
        var count = 0
        while true {
            guard let data = try? handle.read(upToCount: 64 * 1_024),
                  !data.isEmpty else { break }
            count += data.reduce(into: 0) { partial, byte in
                if byte == 0x0A { partial += 1 }
            }
        }
        return String(count)
    }

    private static func dumpChannels() {
        switch IOReportReader().channelInventory() {
        case let .known(channels, source):
            print("source\t\(source.rawValue)")
            print("group\tsubgroup\tchannel\tunit")
            for channel in channels.sorted(by: {
                ($0.group, $0.subgroup, $0.channel) <
                    ($1.group, $1.subgroup, $1.channel)
            }) {
                print(
                    "\(channel.group)\t\(channel.subgroup)\t\(channel.channel)\t\(channel.unit)"
                )
            }
        case let .notPublished(reason):
            print("not published — \(reason)")
        case let .notAttributable(measured, explained):
            print(
                "not attributable — measured \(measured.count), explained \(explained.count)"
            )
        }
    }

    private static func requireVolumeURL(
        _ volumeURL: URL?,
        for url: URL
    ) throws -> URL {
        guard let volumeURL else {
            throw CLIError.volumeNotPublished(url.path)
        }
        return volumeURL
    }

    private static func render(
        _ measurement: FathomKit.Measurement<UInt64>
    ) -> String {
        switch measurement {
        case let .known(value, source):
            return "\(value) bytes [\(source.rawValue)]"
        case let .notPublished(reason):
            return "not published — \(reason)"
        case let .notAttributable(measured, explained):
            return "not attributable — measured \(measured) bytes, explained \(explained) bytes"
        }
    }

    private static func renderSnapshots(
        _ measurement: FathomKit.Measurement<[LocalSnapshot]>
    ) -> String {
        switch measurement {
        case let .known(snapshots, source):
            return "\(snapshots.count) [\(source.rawValue)]"
        case let .notPublished(reason):
            return "not published — \(reason)"
        case let .notAttributable(measured, explained):
            return "not attributable — measured \(measured.count), explained \(explained.count)"
        }
    }

    private static func renderScalar(
        _ measurement: FathomKit.Measurement<UInt64>
    ) -> String {
        switch measurement {
        case let .known(value, source):
            return "\(value) [\(source.rawValue)]"
        case let .notPublished(reason):
            return "not published — \(reason)"
        case let .notAttributable(measured, explained):
            return "not attributable — measured \(measured), explained \(explained)"
        }
    }

    private static func renderBoolean(
        _ measurement: FathomKit.Measurement<Bool>
    ) -> String {
        switch measurement {
        case let .known(value, source):
            return "\(value ? "granted" : "not granted") [\(source.rawValue)]"
        case let .notPublished(reason):
            return "not published — \(reason)"
        case let .notAttributable(measured, explained):
            return "not attributable — measured \(measured), explained \(explained)"
        }
    }

    private static func renderStrings(
        _ measurement: FathomKit.Measurement<[String]>
    ) -> String {
        switch measurement {
        case let .known(values, source):
            return "\(values.count) [\(source.rawValue)]"
        case let .notPublished(reason):
            return "not published — \(reason)"
        case let .notAttributable(measured, explained):
            return "not attributable — measured \(measured.count), explained \(explained.count)"
        }
    }

    private static func renderStringList(
        _ measurement: FathomKit.Measurement<[String]>
    ) -> String {
        switch measurement {
        case let .known(values, source):
            return "\(values.joined(separator: ", ")) [\(source.rawValue)]"
        case let .notPublished(reason):
            return "not published — \(reason)"
        case let .notAttributable(measured, explained):
            return "not attributable — measured \(measured.joined(separator: ", ")); explained \(explained.joined(separator: ", "))"
        }
    }

    private static func renderDouble(
        _ measurement: FathomKit.Measurement<Double>
    ) -> String {
        switch measurement {
        case let .known(value, source):
            return "\(value) [\(source.rawValue)]"
        case let .notPublished(reason):
            return "not published — \(reason)"
        case let .notAttributable(measured, explained):
            return "not attributable — measured \(measured), explained \(explained)"
        }
    }

    private static func renderChannels(
        _ measurement: FathomKit.Measurement<[IOReportChannel]>
    ) -> String {
        switch measurement {
        case let .known(channels, source):
            return "\(channels.count) [\(source.rawValue)]"
        case let .notPublished(reason):
            return "not published — \(reason)"
        case let .notAttributable(measured, explained):
            return "not attributable — measured \(measured.count), explained \(explained.count)"
        }
    }

    private static func renderPower(
        _ measurement: FathomKit.Measurement<[IOReportPowerReading]>
    ) -> String {
        switch measurement {
        case let .known(readings, source):
            let published = readings.filter {
                if case .known = $0.watts { return true }
                return false
            }
            return "\(published.count)/\(readings.count) values [\(source.rawValue)]"
        case let .notPublished(reason):
            return "not published — \(reason)"
        case let .notAttributable(measured, explained):
            return "not attributable — measured \(measured.count), explained \(explained.count)"
        }
    }

    private static func renderTemperatures(
        _ measurement:
            FathomKit.Measurement<[TemperatureSensorReading]>
    ) -> String {
        switch measurement {
        case let .known(readings, source):
            return "\(readings.count) [\(source.rawValue)]"
        case let .notPublished(reason):
            return "not published — \(reason)"
        case let .notAttributable(measured, explained):
            return "not attributable — measured \(measured.count), explained \(explained.count)"
        }
    }

    private static func renderCompleteness(
        _ measurement: FathomKit.Measurement<Set<FileIdentity>>
    ) -> String {
        switch measurement {
        case let .known(identities, source):
            return "complete, \(identities.count) identities [\(source.rawValue)]"
        case let .notPublished(reason):
            return "not published — \(reason)"
        case let .notAttributable(measured, explained):
            return "not attributable — measured \(measured.count), explained \(explained.count)"
        }
    }

    private static func format(
        duration: Duration
    ) -> String {
        String(format: "%.3f seconds", durationSeconds(duration))
    }

    private static func durationSeconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) +
            Double(components.attoseconds) / 1e18
    }

    private static func peakResidentBytes() -> UInt64 {
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else {
            return 0
        }
        return UInt64(max(usage.ru_maxrss, 0))
    }

    private static func sysctlString(_ name: String) -> String {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else {
            return "not published"
        }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &bytes, &size, nil, 0) == 0 else {
            return "not published"
        }
        let utf8 = bytes.prefix { $0 != 0 }.map {
            UInt8(bitPattern: $0)
        }
        return String(decoding: utf8, as: UTF8.self)
    }

    /// A sysctl that answers yes, no, or nothing at all.
    ///
    /// The third case is the common one and the reason this is not a `Bool`:
    /// `hw.optional.arm64` and `sysctl.proc_translated` are unknown OIDs on an
    /// Intel Mac, and reading an absent OID as `false` would report a
    /// non-translated Intel host and an Apple silicon host that Rosetta is not
    /// translating with the same word.
    private static func sysctlFlag(_ name: String) -> String {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else {
            return "not published"
        }
        return value != 0 ? "yes" : "no"
    }

    private static func printUsage() {
        print(
            """
            Usage:
              fathom explain <path> [--whole-volume]
              fathom scan <path>
              fathom benchmark <path> [--enforce-reference-gates]
              fathom doctor
              fathom dump-channels
              fathom export-diagnostics <destination> [--include-paths]
              fathom capture-fixtures <destination> [--include-unparsed-smc-bytes]
              fathom recipe test <recipe-or-catalog.json> [--home <fixture-root>]

            capture-fixtures records the raw hardware payloads RELEASE-GATES.md
            gate 2 asks for — the NVMe SMART log page, the SMC key inventory and
            values, the IOReport subscription and one delta, and the IOHID
            temperature events — beside capture-manifest.json, which names this
            machine and states what was captured and what this Mac does not
            publish. A payload that is not published is written as a
            <name>.notpublished.txt reason file; it is never written as an empty
            or substituted fixture.

            SMC bytes are withheld by default for any key whose declared type
            the shipping decoder cannot read, because these fixtures are
            committed to a public repository. The key, its type and its size are
            still recorded. --include-unparsed-smc-bytes opts out.

            Exit codes:
              0  every subcommand that ran to completion, capture-fixtures
                 included. A not-published payload is an outcome, not a failure:
                 read summary.notPublished out of capture-manifest.json, which
                 is the number printed on the last line.
              1  the command could not run — an unknown command, an option that
                 was not understood, a destination that already exists, or a
                 read or write that failed.
            """
        )
    }
}

private enum CLIError: Error, CustomStringConvertible {
    case missingPath(command: String)
    case unknownCommand(String)
    case volumeNotPublished(String)
    case pathNotFoundAfterScan(String)
    case invalidOptions(command: String)
    case destinationExists(String)
    case invalidRecipeCommand
    case referenceGateFailed(String)

    var description: String {
        switch self {
        case let .missingPath(command):
            return "\(command) requires a path"
        case let .unknownCommand(command):
            return "unknown command \(command)"
        case let .volumeNotPublished(path):
            return "macOS did not publish the containing volume for \(path)"
        case let .pathNotFoundAfterScan(path):
            return "the scan did not return \(path)"
        case let .invalidOptions(command):
            return "\(command) received an unsupported option"
        case let .destinationExists(path):
            return "refusing to overwrite existing destination \(path)"
        case .invalidRecipeCommand:
            return "usage: fathom recipe test <recipe-or-catalog.json> [--home <fixture-root>]"
        case let .referenceGateFailed(reason):
            return "reference gate failed: \(reason)"
        }
    }
}

// MARK: - capture-fixtures manifest
//
// The manifest is the part of the capture that survives being read a year
// later. It records the machine, what was captured, and — with equal weight —
// what this Mac did not publish and the reason it gave. Nothing is omitted for
// being absent: an omitted row and an unattempted row look identical, and gate
// 2 is the one gate nobody gets to run twice.

private struct CaptureRecord: Encodable {
    let name: String
    /// `captured`, `not published`, or `not attributable` — one per
    /// `Measurement` state, never collapsed into a boolean.
    let state: String
    let source: String?
    let reason: String?
    let byteCount: Int?
    let sha256: String?
    let note: String

    private enum CodingKeys: String, CodingKey {
        case name, state, source, reason, byteCount, sha256, note
    }

    // Written out rather than synthesized because the synthesized encoder uses
    // `encodeIfPresent` and drops a nil field entirely. In a record whose whole
    // job is to distinguish "captured" from "this Mac does not publish it",
    // a missing `reason` key and a `reason` of null read the same to anyone
    // grepping the manifest, and only one of them is true.
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(state, forKey: .state)
        try container.encode(source, forKey: .source)
        try container.encode(reason, forKey: .reason)
        try container.encode(byteCount, forKey: .byteCount)
        try container.encode(sha256, forKey: .sha256)
        try container.encode(note, forKey: .note)
    }
}

private struct CaptureSummary: Encodable {
    let captured: Int
    let notPublished: Int
    let notAttributable: Int
}

private struct CaptureMachineIdentity: Encodable {
    let hardwareModel: String
    let chipBrand: String
    let architecture: String
    /// `yes`, `no` or `not published` — see `sysctlFlag`.
    let appleSilicon: String
    let rosettaTranslated: String
    let kernelOSVersion: String
    let operatingSystemVersion: String
}

private struct CaptureManifest: Encodable {
    let capturedAt: String
    let commit: String
    /// The destination as a stable SHA-256 token rather than a path. The
    /// manifest is committed; a path under someone's home directory carries
    /// their account name, and `export-diagnostics` already hashes paths by
    /// default for exactly this reason.
    let destinationToken: String
    let machine: CaptureMachineIdentity
    let ioReportRequestedGroups: [String]
    let ioReportSampleElapsedSeconds: Double
    let nvmeLogPageLength: Int
    let smcByteHandling: String
    let payloads: [CaptureRecord]
    let summary: CaptureSummary
}

private struct CapturedSMCValue: Encodable {
    let key: String
    let dataType: String
    let dataSize: UInt32
    /// Base64, or null when the bytes were withheld. Withheld is not the same
    /// as absent, so `withheld` carries the reason and both keys are always
    /// written — see `CaptureRecord.encode(to:)`.
    let bytes: String?
    let withheld: String?

    private enum CodingKeys: String, CodingKey {
        case key, dataType, dataSize, bytes, withheld
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(key, forKey: .key)
        try container.encode(dataType, forKey: .dataType)
        try container.encode(dataSize, forKey: .dataSize)
        try container.encode(bytes, forKey: .bytes)
        try container.encode(withheld, forKey: .withheld)
    }
}

private struct CapturedSMCInventory: Encodable {
    let byteHandling: String
    let values: [CapturedSMCValue]
    let refusedKeys: [SMCRefusedKey]
    let readKeyCount: Int
    let withheldByteCount: Int
    let refusedKeyCount: Int
}
