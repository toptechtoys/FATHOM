import FathomKit
import SwiftUI

struct OnboardingView: View {
    @ObservedObject var model: OnboardingAppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Set up FATHOM").font(.fathomDisplay(30))
            Text("The monitors and developer-folder scan work without special access. Add only the capabilities you want.")
                .foregroundStyle(.secondary)

            onboardingRow(
                title: "Full Disk Access",
                detail: "Adds protected Mail, Messages, Safari, backups, and Time Machine data. FATHOM checks access by opening a protected database without reading it.",
                state: booleanLabel(model.fullDiskAccess),
                button: "Open Privacy Settings",
                action: model.openFullDiskAccessSettings
            )
            onboardingRow(
                title: "Menu bar visibility",
                detail: "Tahoe may hide FATHOM under Menu Bar → Allow in the Menu Bar. macOS provides no API to verify this state.",
                state: "not published",
                button: "Open Menu Bar Settings",
                action: model.openMenuBarSettings
            )
            onboardingRow(
                title: "Start the menu bar agent at login",
                detail: "Cost before enabling: starts FATHOM Bar now and at login. Its measured release idle cost is not published on this hardware yet.",
                state: measurementLabel(model.agentStatus),
                button: agentEnabled ? "Disable agent" : "Enable agent",
                action: { model.setAgentEnabled(!agentEnabled) }
            )

            if let error = model.actionError {
                Text("Agent change failed: \(error)")
                    .font(.fathomSystem(12))
                    .foregroundStyle(.secondary)
                Button("Open Login Items") { model.openLoginItemSettings() }
            }

            HStack {
                Button("Check again") { model.refresh() }
                Spacer()
                Button("Continue") { model.finish() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 620)
        .accessibilityElement(children: .contain)
    }

    private var agentEnabled: Bool {
        if case let .known(value, _) = model.agentStatus {
            return value == "Enabled" || value == "Needs approval in System Settings"
        }
        return false
    }

    private func onboardingRow(
        title: String,
        detail: String,
        state: String,
        button: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Text(state).font(.fathomSystem(11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Text(detail).font(.fathomSystem(12.5)).foregroundStyle(.secondary)
            Button(button, action: action)
        }
        .padding(14)
        .background(.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
    }

    private func booleanLabel(_ measurement: FathomKit.Measurement<Bool>) -> String {
        switch measurement {
        case let .known(value, _): value ? "Granted" : "Not granted"
        case .notPublished: "not published"
        case .notAttributable: "not attributable"
        }
    }

    private func measurementLabel(_ measurement: FathomKit.Measurement<String>) -> String {
        switch measurement {
        case let .known(value, _): value
        case .notPublished: "not published"
        case .notAttributable: "not attributable"
        }
    }
}
