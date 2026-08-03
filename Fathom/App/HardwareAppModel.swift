import Combine
import FathomKit
import Foundation

@MainActor
final class HardwareAppModel: ObservableObject {
    enum State {
        case idle
        case reading
        case result(NVMeSMARTSnapshot)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var sensorState: SensorState = .idle
    @Published private(set) var unsafeShutdowns30Days:
        FathomKit.Measurement<UnsafeShutdownWindow> = .notPublished(
            reason: "Thirty days of unsafe-shutdown history are required"
        )
    private var sensorTask: Task<Void, Never>?
    private let smcSession = SMCProbeSession()

    enum SensorState {
        case idle
        case reading
        case result(SensorPresentation)
    }

    func readSSD() {
        guard case .idle = state else {
            return
        }
        state = .reading
        Task {
            let snapshot = await Task.detached(
                priority: .userInitiated
            ) {
                NVMeSMARTReader().read()
            }.value
            let historyURL = FileManager.default.homeDirectoryForCurrentUser
                .appending(path: "Library/Application Support/FATHOM")
                .appending(path: "unsafe-shutdown-history.json")
            unsafeShutdowns30Days = await UnsafeShutdownHistoryStore(
                url: historyURL
            ).record(snapshot.unsafeShutdowns)
            state = .result(snapshot)
        }
    }

    func reset() {
        state = .idle
    }

    func startSensors() {
        guard sensorTask == nil else { return }
        sensorState = .reading
        let smcSession = smcSession
        sensorTask = Task { [weak self] in
            let inventory = await Task.detached(priority: .utility) {
                SMCReader().readKeyInventory()
            }.value
            let channelMap = IOReportChannelMapLoader().loadBundled()
            let ioReport: IOReportSampler?
            let ioReportFailure: String?
            do {
                ioReport = try IOReportSampler()
                ioReportFailure = nil
            } catch {
                ioReport = nil
                ioReportFailure = String(describing: error)
            }

            while !Task.isCancelled {
                async let temperatures = Task.detached(priority: .utility) {
                    TemperatureSensorReader().read()
                }.value
                async let smc = Task.detached(priority: .utility) {
                    SMCReader().readSnapshot(
                        keyInventory: inventory,
                        session: smcSession
                    )
                }.value
                let power: FathomKit.Measurement<[IOReportPowerReading]>
                if let ioReport {
                    do {
                        power = try await ioReport.samplePower()
                    } catch {
                        power = .notPublished(
                            reason: "IOReport sampling failed: \(error)"
                        )
                    }
                } else {
                    power = .notPublished(
                        reason: "IOReport subscription is not published. \(ioReportFailure ?? "No reason supplied")"
                    )
                }
                guard !Task.isCancelled else { break }
                self?.sensorState = .result(
                    SensorPresentation(
                        temperatures: await temperatures,
                        smc: await smc,
                        componentPower: power,
                        channelMap: channelMap,
                        sampledAt: Date()
                    )
                )
                do {
                    try await Task.sleep(for: .seconds(2))
                } catch {
                    break
                }
            }
        }
    }

    func stopSensors() {
        sensorTask?.cancel()
        sensorTask = nil
    }
}

struct SensorPresentation: Sendable {
    let temperatures:
        FathomKit.Measurement<[TemperatureSensorReading]>
    let smc: SMCSnapshot
    let componentPower:
        FathomKit.Measurement<[IOReportPowerReading]>
    let channelMap: FathomKit.Measurement<IOReportChannelMap>
    let sampledAt: Date
}
