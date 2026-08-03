import CFathomHardware
import Foundation

public struct GPUSnapshot: Sendable, Equatable {
    public let deviceUtilizationPercent: Measurement<Double>
    public let rendererUtilizationPercent: Measurement<Double>
    public let tilerUtilizationPercent: Measurement<Double>
    public let coreCount: Measurement<UInt64>

    public init(
        deviceUtilizationPercent: Measurement<Double>,
        rendererUtilizationPercent: Measurement<Double>,
        tilerUtilizationPercent: Measurement<Double>,
        coreCount: Measurement<UInt64>
    ) {
        self.deviceUtilizationPercent = deviceUtilizationPercent
        self.rendererUtilizationPercent = rendererUtilizationPercent
        self.tilerUtilizationPercent = tilerUtilizationPercent
        self.coreCount = coreCount
    }
}

public struct GPUReader: Sendable {
    public init() {}

    public func read() -> GPUSnapshot {
        var raw = fathom_gpu_counters()
        var errorCode: Int32 = 0
        guard fathom_gpu_read_counters(&raw, &errorCode) == 0 else {
            return Self.notPublished(
                reason: "IOAccelerator counters unavailable (IOReturn \(errorCode))"
            )
        }
        func utilization(
            _ mask: UInt32,
            _ value: Double,
            _ label: String
        ) -> Measurement<Double> {
            guard raw.published_fields & mask != 0 else {
                return .notPublished(
                    reason: "IOAccelerator did not publish \(label)"
                )
            }
            guard value.isFinite, (0...100).contains(value) else {
                return .notPublished(
                    reason: "IOAccelerator published an invalid \(label)"
                )
            }
            return .known(
                value,
                source: .ioAcceleratorPerformanceStatistics
            )
        }
        let coreMask = UInt32(FATHOM_GPU_CORE_COUNT)
        return GPUSnapshot(
            deviceUtilizationPercent: utilization(
                UInt32(FATHOM_GPU_DEVICE_UTILIZATION),
                raw.device_utilization_percent,
                "Device Utilization %"
            ),
            rendererUtilizationPercent: utilization(
                UInt32(FATHOM_GPU_RENDERER_UTILIZATION),
                raw.renderer_utilization_percent,
                "Renderer Utilization %"
            ),
            tilerUtilizationPercent: utilization(
                UInt32(FATHOM_GPU_TILER_UTILIZATION),
                raw.tiler_utilization_percent,
                "Tiler Utilization %"
            ),
            coreCount: raw.published_fields & coreMask != 0
                ? .known(raw.core_count, source: .ioRegistryGPUCoreCount)
                : .notPublished(
                    reason: "IORegistry did not publish gpu-core-count"
                )
        )
    }

    private static func notPublished(reason: String) -> GPUSnapshot {
        GPUSnapshot(
            deviceUtilizationPercent: .notPublished(reason: reason),
            rendererUtilizationPercent: .notPublished(reason: reason),
            tilerUtilizationPercent: .notPublished(reason: reason),
            coreCount: .notPublished(reason: reason)
        )
    }
}
