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
              fathom recipe test <recipe-or-catalog.json> [--home <fixture-root>]
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
