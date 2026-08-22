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
                FathomEmptySection(
                    title: "Weekly digest",
                    subtitle: "No digest yet",
                    headline: "One notification a week, and it is allowed to say nothing.",
                    detail: "The digest is assembled from completed scans, so the first one arrives after the first scan. If the week was quiet it says so in one line and stops. It never invents a finding to justify arriving.",
                    actionTitle: "Run the first Deep Scan",
                    actionCost: "Reads every volume once. Changes nothing.",
                    action: storage.scanSelectedVolume
                )
            case .scanning:
                FathomEmptySection(
                    title: "Weekly digest",
                    subtitle: "Recording",
                    headline: "Recording the evidence a digest is built from.",
                    detail: storage.scanProgressMessage,
                    actionTitle: "Scanning…",
                    isBusy: true,
                    action: {}
                )
            case let .failed(reason):
                FathomEmptySection(
                    title: "Weekly digest",
                    subtitle: "The pass did not complete",
                    headline: "There is nothing to summarise yet.",
                    detail: reason,
                    actionTitle: "Try again",
                    action: storage.reset
                )
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
            FathomEmptySection(
                title: "Weekly digest",
                subtitle: "History could not be read",
                headline: "There is nothing to summarise yet.",
                detail: reason
            )
        case let .result(_, digest):
            content(presentation, digest: digest)
        }
    }

    private func content(
        _ presentation: StoragePresentation,
        digest: WeeklyDigestPresentation
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                FathomSectionHeader(
                    title: "Weekly digest",
                    subtitle: notifications.isEnabled
                        ? "Delivery on"
                        : "Delivery off",
                    isLive: false
                )

                FathomReadoutGrid {
                    FathomMeasurementReadout(
                        label: "Change in free space",
                        measurement: digest.changeInFreeBytes,
                        note: window(digest),
                        format: signedBytes
                    )
                }
                .padding(.bottom, 22)

                FathomPanel(label: "This week's preview") {
                    card(digest)
                }

                FathomPanel(label: "Delivery") {
                    VStack(spacing: 3) {
                        toggleRow(
                            "Send one weekly digest",
                            detail: state(notifications.state),
                            isOn: Binding(
                                get: { notifications.isEnabled },
                                set: {
                                    notifications.setEnabled(
                                        $0,
                                        change: digest.changeInFreeBytes
                                    )
                                }
                            )
                        )
                        toggleRow(
                            "A directory gained over 20 GB in a day",
                            detail: state(notifications.directoryAlertState),
                            isOn: Binding(
                                get: { directoryAlert },
                                set: { enabled in
                                    notifications.setDirectoryAlert(
                                        enabled,
                                        presentation: presentation
                                    ) { directoryAlert = $0 }
                                }
                            )
                        )
                    }
                }

                FathomPanel(label: "Alerts we cannot offer") {
                    VStack(spacing: 3) {
                        FathomDataRow.simple(
                            "Snapshot share consequence alert",
                            value: "not offered",
                            valueColor: .white.opacity(
                                FathomSurface.minimumTextOpacity
                            ),
                            annotation: "Snapshot-attributable bytes are not published on this configuration."
                        )
                        FathomDataRow.simple(
                            "Endurance forecast moved by over a year",
                            value: "not offered",
                            valueColor: .white.opacity(
                                FathomSurface.minimumTextOpacity
                            ),
                            annotation: "Apple does not publish a defensible calendar endurance forecast."
                        )
                    }
                }

                FathomNote(
                    headline: "A quiet week is always silent.",
                    detail: "Enabling delivery asks macOS for notification permission, and each consequence alert is opted into separately. No finding is invented to justify a notification, and every number in the digest links to the evidence that produced it."
                )
            }
            .padding(EdgeInsets(top: 22, leading: 28, bottom: 40, trailing: 28))
            .onAppear {
                notifications.refresh(change: digest.changeInFreeBytes)
                notifications.refreshDirectoryAlert(presentation: presentation)
            }
        }
    }

    /// The digest as it will actually arrive.
    ///
    /// Where the change is not published the card says so rather than being
    /// hidden — a preview that only appears when there is news would make the
    /// silent week look like a bug.
    @ViewBuilder
    private func card(_ digest: WeeklyDigestPresentation) -> some View {
        switch digest.changeInFreeBytes {
        case let .known(delta, _):
            FathomDigestCard(
                headline: headline(delta),
                dateline: window(digest),
                lines: [
                    FathomDigestCard.Line(
                        name: "Change in free space",
                        value: signedBytes(delta),
                        direction: delta < 0 ? .grew : .shrank
                    ),
                ],
                summary: "Every number here links to the screen that produced it. If nothing changed, this is the whole message."
            )
        case let .notPublished(reason):
            FathomPanelUnavailable(reason: reason)
        case let .notAttributable(measured, explained):
            FathomPanelUnavailable(
                reason: "\(signedBytes(measured)) measured, \(signedBytes(explained)) explained. The rest cannot be attributed to anything we watched.",
                isAttributionGap: true
            )
        }
    }

    private func toggleRow(
        _ title: String,
        detail: String,
        isOn: Binding<Bool>
    ) -> some View {
        FathomDataRow(
            leading: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.fathomSystem(13, weight: .semibold))
                    Text(detail)
                        .font(.fathomSystem(11.5))
                        .foregroundStyle(
                            .white.opacity(FathomSurface.minimumTextOpacity)
                        )
                        .fixedSize(horizontal: false, vertical: true)
                }
            },
            trailing: {
                Toggle("", isOn: isOn)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .disabled(notifications.isWorking)
            }
        )
        .accessibilityElement(children: .contain)
    }

    private func state(
        _ measurement: FathomKit.Measurement<String>
    ) -> String {
        switch measurement {
        case let .known(value, _): value
        case let .notPublished(reason): reason
        case .notAttributable: "Delivery state is not attributable."
        }
    }

    private func headline(_ delta: Int64) -> String {
        let magnitude = UInt64(delta.magnitude)
            .formatted(.byteCount(style: .file))
        return delta < 0 ? "\(magnitude) fuller" : "\(magnitude) more free"
    }

    private func window(_ digest: WeeklyDigestPresentation) -> String {
        guard let start = digest.start, let end = digest.end else {
            return "The window is not published yet"
        }
        let format = Date.FormatStyle(date: .abbreviated, time: .omitted)
        return "\(start.formatted(format)) to \(end.formatted(format))"
    }

    private func signedBytes(_ delta: Int64) -> String {
        let magnitude = UInt64(delta.magnitude)
            .formatted(.byteCount(style: .file))
        return delta < 0 ? "−\(magnitude)" : "+\(magnitude)"
    }
}
