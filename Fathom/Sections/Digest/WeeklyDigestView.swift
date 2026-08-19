import FathomKit
import SwiftUI

struct WeeklyDigestView: View {
    @EnvironmentObject private var storage: StorageAppModel
    @EnvironmentObject private var history: HistoryAppModel
    @StateObject private var notifications = DigestNotificationModel()
    @AppStorage("alerts.directory20GB") private var directoryAlert = false

    var body: some View {
        Group {
            switch storage.state {
            case .idle:
                FathomPoster(
                    title: "Weekly digest",
                    message: "One summary a week, and it is allowed to say nothing.",
                    symbol: "doc.text",
                    world: .digest,
                    shape: AnyShape(RoundedRectangle(cornerRadius: 30)),
                    isScanning: false,
                    action: storage.scanSelectedVolume
                )
            case .scanning:
                ProgressView("Recording evidence for the digest…")
            case let .failed(reason):
                Text("not published — \(reason)")
            case let .result(presentation):
                digestContent(presentation)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func digestContent(_ presentation: StoragePresentation) -> some View {
        switch history.state {
        case .idle:
            ProgressView().onAppear { history.load(from: presentation) }
        case .loading:
            ProgressView("Building the digest from completed scans…")
        case let .failed(reason):
            Text(reason)
        case let .result(_, digest):
            VStack(alignment: .leading, spacing: 20) {
                Text("Weekly digest").font(.fathomDisplay(34))
                HardwareResultCard(label: "CHANGE IN FREE SPACE") {
                    digestMeasurement(digest.changeInFreeBytes)
                }
                Toggle(
                    "Send one weekly digest",
                    isOn: Binding(
                        get: { notifications.isEnabled },
                        set: { notifications.setEnabled($0, change: digest.changeInFreeBytes) }
                    )
                )
                .disabled(notifications.isWorking)
                notificationState
                unavailableConsequence(
                    "Snapshot share consequence alert",
                    reason: "Snapshot-attributable bytes are not published on this configuration"
                )
                unavailableConsequence(
                    "Endurance forecast moved by over a year",
                    reason: "Apple does not publish a defensible calendar endurance forecast"
                )
                Toggle(
                    "A directory gained over 20 GB in a day",
                    isOn: Binding(
                        get: { directoryAlert },
                        set: { enabled in
                            notifications.setDirectoryAlert(
                                enabled,
                                presentation: presentation
                            ) { resolved in
                                directoryAlert = resolved
                            }
                        }
                    )
                )
                .disabled(notifications.isWorking)
                directoryAlertState
                Text("Cost before enabling: macOS asks for notification permission. Consequence alerts are individually opt-in. A quiet week is always silent; no finding is invented to justify a notification.")
                    .font(.fathomSystem(12.5))
                    .foregroundStyle(.white.opacity(0.82))
            }
            .frame(maxWidth: 720, alignment: .leading)
            .padding(34)
            .onAppear {
                notifications.refresh(change: digest.changeInFreeBytes)
                notifications.refreshDirectoryAlert(presentation: presentation)
            }
        }
    }

    @ViewBuilder
    private var notificationState: some View {
        switch notifications.state {
        case let .known(value, source):
            Text(value).font(.fathomSystem(12)).help(source.rawValue)
                .accessibilityLabel("\(value), source \(source.rawValue)")
        case let .notPublished(reason):
            Text("not published — \(reason)")
                .font(.fathomSystem(12))
                .foregroundStyle(.white.opacity(0.82))
        case .notAttributable:
            Text("not attributable").font(.fathomSystem(12))
        }
    }

    @ViewBuilder
    private var directoryAlertState: some View {
        switch notifications.directoryAlertState {
        case let .known(value, source):
            Text(value).font(.fathomSystem(12)).help(source.rawValue)
                .accessibilityLabel("\(value), source \(source.rawValue)")
        case let .notPublished(reason):
            Text("not published — \(reason)")
                .font(.fathomSystem(12))
                .foregroundStyle(.white.opacity(0.82))
        case .notAttributable:
            Text("not attributable").font(.fathomSystem(12))
        }
    }

    private func unavailableConsequence(
        _ title: String,
        reason: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(title, isOn: .constant(false)).disabled(true)
            Text("not published — \(reason)")
                .font(.fathomSystem(12))
                .foregroundStyle(.white.opacity(0.82))
        }
    }

    @ViewBuilder
    private func digestMeasurement(
        _ measurement: FathomKit.Measurement<Int64>
    ) -> some View {
        switch measurement {
        case let .known(delta, source):
            let magnitude = UInt64(delta.magnitude)
            let phrase = delta < 0
                ? "Disk is \(hardwareByteString(magnitude)) fuller"
                : "Disk has \(hardwareByteString(magnitude)) more free"
            Text(phrase)
                .font(.fathomData(20, weight: .semibold))
                .help(source.rawValue)
                .accessibilityLabel("\(phrase), source \(source.rawValue)")
        case let .notPublished(reason):
            Text("not published")
                .foregroundStyle(.white.opacity(0.82))
                .help(reason)
                .accessibilityLabel("Not published. \(reason)")
        case .notAttributable:
            Text("not attributable")
        }
    }
}
