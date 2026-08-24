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

    /// Sixty seconds of history per sparkline, recorded on the same tick that
    /// publishes the snapshot.
    ///
    /// A tick where macOS published nothing is recorded as a gap rather than
    /// skipped, so the chart keeps its time base and draws the hole. See
    /// `SampleHistory`.
    @Published private(set) var cpuHistory = SampleHistory<Double>()
    @Published private(set) var gpuHistory = SampleHistory<Double>()
    @Published private(set) var memoryHistory = SampleHistory<Double>()
    @Published private(set) var networkHistory = SampleHistory<Double>()

    private var samplingTask: Task<Void, Never>?
    private var pressureSource: DispatchSourceMemoryPressure?
    private var observerCount = 0
    private var bluetoothObserverCount = 0
    /// The last paired-device reading that came back. The sampling loop
    /// publishes this rather than taking a fresh one, because taking one can
    /// block — see `refreshBluetoothIfIdle`.
    private var latestBluetooth = SystemMonitorModel.bluetoothNotSampled
    private var bluetoothReadInFlight = false
    private var bluetoothReadGeneration = 0

    /// How long the section waits before saying macOS has not answered.
    ///
    /// Four ticks of the loop: long enough that a slow first read still lands
    /// as a reading, short enough that a stalled one is a sentence on screen
    /// rather than a frozen window.
    private static let bluetoothDeadline = Duration.seconds(4)

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
                let bluetooth = self?.currentBluetooth()
                    ?? Self.bluetoothNotSampled
                let presentation = SystemPresentation(
                    cpu: await cpu,
                    memory: await memory,
                    gpu: await gpu,
                    network: await network,
                    bluetooth: bluetooth,
                    channelMap: channelMap,
                    sampledAt: Date()
                )
                self?.record(presentation)
                self?.state = .result(presentation)
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    break
                }
            }
        }
    }

    /// One tick, one entry in every buffer. Recording only the ticks that
    /// produced a reading would compress the gaps out of the chart.
    private func record(_ presentation: SystemPresentation) {
        cpuHistory.record(presentation.cpu.aggregateBusy.map { $0 * 100 })
        gpuHistory.record(presentation.gpu.deviceUtilizationPercent)
        memoryHistory.record(presentation.memory.usedFraction.map { $0 * 100 })
        networkHistory.record(presentation.network.totalThroughput)
    }

    func stop() {
        observerCount = max(0, observerCount - 1)
        guard observerCount == 0 else { return }
        samplingTask?.cancel()
        samplingTask = nil
        pressureSource?.cancel()
        pressureSource = nil
    }

    /// Paired-device enumeration is TCC-gated and costs something, so it
    /// happens only while the Bluetooth section is on screen. Every other
    /// section would otherwise pay for a reading it never displays.
    func beginBluetoothObservation() {
        bluetoothObserverCount += 1
        guard bluetoothObserverCount == 1 else { return }
        // Neither of these blocks. This method used to call the reader inline,
        // on the main actor, from `onAppear` — which is how opening this
        // section froze the entire app.
        refreshBluetoothIfIdle()
        publishBluetooth()
    }

    func endBluetoothObservation() {
        bluetoothObserverCount = max(0, bluetoothObserverCount - 1)
    }

    /// What the loop publishes: the last reading that came back, never a fresh
    /// call. Asks for a new one when nothing is outstanding.
    private func currentBluetooth() -> BluetoothSnapshot {
        guard bluetoothObserverCount > 0 else { return Self.bluetoothNotSampled }
        refreshBluetoothIfIdle()
        return latestBluetooth
    }

    /// Starts one paired-device read off the main actor, and a deadline.
    ///
    /// A blocked `IOBluetooth` call cannot be cancelled, so the deadline does
    /// not stop the read — it stops the *waiting*. The section says macOS has
    /// not answered, the app keeps sampling, and if the read ever returns,
    /// `receiveBluetooth` publishes what it actually said.
    private func refreshBluetoothIfIdle() {
        guard !bluetoothReadInFlight else { return }
        bluetoothReadInFlight = true
        bluetoothReadGeneration += 1
        let generation = bluetoothReadGeneration
        if latestBluetooth == Self.bluetoothNotSampled {
            latestBluetooth = Self.bluetoothRequested
        }

        Task.detached(priority: .utility) { [weak self] in
            let snapshot = BluetoothReader().read()
            await self?.receiveBluetooth(snapshot, generation: generation)
        }

        Task { [weak self] in
            try? await Task.sleep(for: Self.bluetoothDeadline)
            self?.bluetoothDeadlineElapsed(generation: generation)
        }
    }

    private func receiveBluetooth(
        _ snapshot: BluetoothSnapshot,
        generation: Int
    ) {
        guard generation == bluetoothReadGeneration else { return }
        bluetoothReadInFlight = false
        latestBluetooth = snapshot
        publishBluetooth()
    }

    private func bluetoothDeadlineElapsed(generation: Int) {
        guard generation == bluetoothReadGeneration,
              bluetoothReadInFlight else { return }
        // The in-flight flag stays set on purpose. The read is still parked
        // somewhere inside IOBluetooth and nothing can recall it; starting a
        // second one on the next tick would stack threads behind the same
        // stall, one per second, for as long as the section is open.
        latestBluetooth = Self.bluetoothDidNotAnswer
        publishBluetooth()
    }

    private func publishBluetooth() {
        guard case let .result(presentation) = state else { return }
        state = .result(presentation.replacingBluetooth(with: latestBluetooth))
    }

    private static let bluetoothNotSampled = BluetoothSnapshot(
        devices: .notPublished(
            reason: "Paired devices are read only while the Bluetooth section is open"
        )
    )

    private static let bluetoothRequested = BluetoothSnapshot(
        devices: .notPublished(
            reason: "Paired devices have been requested; macOS has not answered yet"
        )
    )

    private static let bluetoothDidNotAnswer = BluetoothSnapshot(
        devices: .notPublished(
            reason: "macOS did not answer the paired-device request within four "
                + "seconds. The request is still outstanding; this row fills in "
                + "if it returns."
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
