import AppKit
import Combine
import FathomKit
import ServiceManagement

@MainActor
final class OnboardingAppModel: ObservableObject {
    @Published var isPresented: Bool
    @Published private(set) var fullDiskAccess: FathomKit.Measurement<Bool>
    @Published private(set) var agentStatus: FathomKit.Measurement<String>
    @Published private(set) var actionError: String?

    static let agentPlistName = "com.exhibinaut.fathom.bar.plist"
    private static let completedKey = "onboarding.completed"

    private var service: SMAppService {
        .agent(plistName: Self.agentPlistName)
    }

    init() {
        isPresented = !UserDefaults.standard.bool(forKey: Self.completedKey)
        fullDiskAccess = FullDiskAccessReader().read()
        agentStatus = .notPublished(reason: "Agent status has not been read")
        refresh()
    }

    func refresh() {
        fullDiskAccess = FullDiskAccessReader().read()
        agentStatus = .known(
            Self.statusLabel(service.status),
            source: .serviceManagementAgentStatus
        )
    }

    func setAgentEnabled(_ enabled: Bool) {
        actionError = nil
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            actionError = error.localizedDescription
        }
        refresh()
    }

    func openFullDiskAccessSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    func openMenuBarSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    func openLoginItemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    func finish() {
        UserDefaults.standard.set(true, forKey: Self.completedKey)
        isPresented = false
    }

    private static func statusLabel(_ status: SMAppService.Status) -> String {
        switch status {
        case .enabled: "Enabled"
        case .notRegistered: "Not registered"
        case .requiresApproval: "Needs approval in System Settings"
        case .notFound: "Agent not found in this app bundle"
        @unknown default: "A newer macOS status is not published"
        }
    }
}
