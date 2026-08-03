import Combine
import Dispatch
import FathomKit
import Foundation

@MainActor
final class SystemMonitorModel: ObservableObject {
    enum State {
        case idle
        case reading
        case result(SystemPresentation)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var memoryPressure:
        FathomKit.Measurement<String> = .notPublished(
            reason: "No memory-pressure event has been observed"
        )

    private var samplingTask: Task<Void, Never>?
    private var pressureSource: DispatchSourceMemoryPressure?
    private var observerCount = 0
    private var bluetoothObserverCount = 0

    /// Five sections share this one loop, and SwiftUI presents the incoming
    /// section before the outgoing one disappears. Observers are counted rather
    /// than toggled so the section being left cannot cancel the loop belonging
    /// to the section being entered.
    func start() {
        observerCount += 1
        guard samplingTask == nil else { return }
        state = .reading
        startMemoryPressureSource()
        samplingTask = Task { [weak self] in
            let cpuSampler = CPUSampler()
            let networkSampler = NetworkSampler()
            let channelMap = IOReportChannelMapLoader().loadBundled()
            _ = await cpuSampler.sample()
            _ = await networkSampler.sample()
            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch {
                return
            }
            while !Task.isCancelled {
                async let cpu = cpuSampler.sample()
                async let memory = Task.detached(priority: .utility) {
                    MemoryReader().read()
                }.value
                async let gpu = Task.detached(priority: .utility) {
                    GPUReader().read()
                }.value
                async let network = networkSampler.sample()
                let bluetooth = self?.sampleBluetooth()
                    ?? Self.bluetoothNotSampled
                self?.state = .result(
                    SystemPresentation(
                        cpu: await cpu,
                        memory: await memory,
                        gpu: await gpu,
                        network: await network,
                        bluetooth: bluetooth,
                        channelMap: channelMap,
                        sampledAt: Date()
                    )
                )
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    break
                }
            }
        }
    }

    func stop() {
        observerCount = max(0, observerCount - 1)
        guard observerCount == 0 else { return }
        samplingTask?.cancel()
        samplingTask = nil
        pressureSource?.cancel()
        pressureSource = nil
    }

    /// Paired-device enumeration is TCC-gated and runs on the main actor, so it
    /// happens only while the Bluetooth section is on screen. Every other
    /// section would otherwise pay for a reading it never displays.
    func beginBluetoothObservation() {
        bluetoothObserverCount += 1
        // Publish a real reading immediately rather than letting the section
        // show "not read while closed" for up to a sampling interval.
        guard bluetoothObserverCount == 1,
              case let .result(presentation) = state else { return }
        state = .result(
            presentation.replacingBluetooth(with: BluetoothReader().read())
        )
    }

    func endBluetoothObservation() {
        bluetoothObserverCount = max(0, bluetoothObserverCount - 1)
    }

    private func sampleBluetooth() -> BluetoothSnapshot {
        guard bluetoothObserverCount > 0 else {
            return Self.bluetoothNotSampled
        }
        return BluetoothReader().read()
    }

    private static let bluetoothNotSampled = BluetoothSnapshot(
        devices: .notPublished(
            reason: "Paired devices are read only while the Bluetooth section is open"
        )
    )

    private func startMemoryPressureSource() {
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.normal, .warning, .critical],
            queue: .main
        )
        source.setEventHandler { [weak self, weak source] in
            guard let event = source?.data else { return }
            let value: String
            if event.contains(.critical) {
                value = "Critical"
            } else if event.contains(.warning) {
                value = "Warning"
            } else {
                value = "Normal"
            }
            self?.memoryPressure = .known(
                value,
                source: .dispatchMemoryPressure
            )
        }
        source.resume()
        pressureSource = source
    }
}

struct SystemPresentation: Sendable {
    let cpu: CPULoadSnapshot
    let memory: MemorySnapshot
    let gpu: GPUSnapshot
    let network: NetworkSnapshot
    let bluetooth: BluetoothSnapshot
    let channelMap: FathomKit.Measurement<IOReportChannelMap>
    let sampledAt: Date

    func replacingBluetooth(
        with snapshot: BluetoothSnapshot
    ) -> SystemPresentation {
        SystemPresentation(
            cpu: cpu,
            memory: memory,
            gpu: gpu,
            network: network,
            bluetooth: snapshot,
            channelMap: channelMap,
            sampledAt: sampledAt
        )
    }
}
