import SwiftUI

@main
struct FathomApp: App {
    init() {
        FathomFontRegistrar.registerBundledFonts()
    }

    var body: some Scene {
        WindowGroup {
            // One view, with nothing attached to it here. Everything the
            // window needs is applied inside `FathomWindow`, and that is not a
            // style preference — see the comment on it.
            FathomWindow()
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

/// The window's contents, and everything attached to them.
///
/// **This exists to keep one string stable.** SwiftUI names a window's saved
/// frame after the full generic type of whatever `WindowGroup` is handed,
/// modifiers included. With the environment objects applied at the scene, the
/// name was 1,900 characters of `ModifiedContent<ModifiedContent<…>>` — and
/// every one of those names is a different window as far as macOS is
/// concerned.
///
/// So adding a model reset the window. The development machine had five of
/// these saved side by side, one per historical shape of that chain, each
/// holding a position nothing would read again:
///
/// ```
/// …FathomRootView, _EnvironmentKeyWritingModifier<StorageAppModel>>, _FlexFrameLayout>-1-AppWindow-1
/// …+ HardwareAppModel>>, _FlexFrameLayout>-1-AppWindow-1
/// …+ nine models, _FlexFrameLayout, _TaskModifier2, _TaskModifier2, SheetPresentationModifier…
/// …+ SubscriptionView…
/// …+ MachineIdentityAppModel…                                        ← the one in use
/// ```
///
/// Every one recorded `1200 760`, because each was new and fell back to
/// `defaultSize`. The window had never been resized by anyone; it had been
/// forgotten five times. Two of them also recorded a screen that no longer
/// exists at that size, which is how a restored window ends up somewhere the
/// user did not leave it.
///
/// A shipping consequence, not just a development one: adding an environment
/// object in an update throws away every user's window position.
///
/// `WindowGroup` now gets `FathomWindow` and nothing else, so the name is
/// `FATHOM.FathomWindow` however much moves around inside this body.
struct FathomWindow: View {
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

    var body: some View {
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
}
