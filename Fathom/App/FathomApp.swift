import SwiftUI

@main
struct FathomApp: App {
    @StateObject private var model = StorageAppModel()
    @StateObject private var hardwareModel = HardwareAppModel()
    @StateObject private var systemModel = SystemMonitorModel()
    @StateObject private var reclaimModel = ReclaimAppModel()
    @StateObject private var historyModel = HistoryAppModel()
    @StateObject private var applicationsModel = ApplicationsAppModel()
    @StateObject private var cloudModel = CloudAppModel()
    @StateObject private var attributionModel = AttributionAppModel()
    @StateObject private var publicIPModel = PublicIPAppModel()
    @StateObject private var onboardingModel = OnboardingAppModel()
    @StateObject private var machineModel = MachineIdentityAppModel()

    init() {
        FathomFontRegistrar.registerBundledFonts()
    }

    var body: some Scene {
        WindowGroup {
            FathomRootView()
                .environmentObject(model)
                .environmentObject(hardwareModel)
                .environmentObject(systemModel)
                .environmentObject(reclaimModel)
                .environmentObject(historyModel)
                .environmentObject(applicationsModel)
                .environmentObject(cloudModel)
                .environmentObject(attributionModel)
                .environmentObject(publicIPModel)
                .environmentObject(machineModel)
                .frame(minWidth: 720, minHeight: 560)
                .task { attributionModel.restoreIfEnabled() }
                .task { publicIPModel.refresh() }
                .onReceive(
                    NotificationCenter.default.publisher(
                        for: .fathomStorageContinuityRescan
                    )
                ) { notification in
                    model.requestContinuityRescan(
                        reason: notification.object as? String ??
                            "FSEvents continuity requires a complete scan"
                    )
                }
                .sheet(isPresented: $onboardingModel.isPresented) {
                    OnboardingView(model: onboardingModel)
                        .interactiveDismissDisabled()
                }
        }
        .defaultSize(width: 1_200, height: 760)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Command Palette…") {
                    NotificationCenter.default.post(
                        name: .fathomShowCommandPalette,
                        object: nil
                    )
                }
                .keyboardShortcut("k", modifiers: .command)
            }
        }
    }
}
