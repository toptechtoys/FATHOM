import AppKit
import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case menuBar = "Menu Bar"
    case home = "Home"
    case deepScan = "Deep Scan"
    case storage = "Storage"
    case explore = "Explore"
    case reclaim = "Reclaim"
    case timeline = "Timeline"
    case attribution = "Attribution"
    case digest = "Weekly digest"
    case applications = "Applications"
    case cloud = "Cloud"
    case maintenance = "Maintenance"
    case cpu = "CPU"
    case memory = "Memory"
    case gpu = "GPU"
    case network = "Network"
    case bluetooth = "Bluetooth"
    case sensors = "Sensors & Power"
    case endurance = "Endurance"
    case ssdHealth = "SSD Health"

    var id: String { rawValue }

    /// File stem of the bundled stroke icon in `Resources/NavIcons`.
    ///
    /// Twenty custom icons, 20x20 viewBox, 1.65 stroke. SF Symbols cannot
    /// carry this set: several of these sections have no symbol that means
    /// the right thing, and the ones that do are drawn on a different grid.
    var icon: String {
        switch self {
        case .menuBar: "menubar"
        case .home: "home"
        case .deepScan: "scan"
        case .storage: "storage"
        case .explore: "explore"
        case .reclaim: "reclaim"
        case .timeline: "timeline"
        case .attribution: "attrib"
        case .digest: "digest"
        case .applications: "apps"
        case .cloud: "cloud"
        case .maintenance: "maint"
        case .cpu: "cpu"
        case .memory: "mem"
        case .gpu: "gpu"
        case .network: "network"
        case .bluetooth: "bt"
        case .sensors: "sensors"
        case .endurance: "endurance"
        case .ssdHealth: "ssd"
        }
    }

    /// The four rail groups, in order. The first is unlabelled; the dividers
    /// carry the grouping, not text headings.
    static let railGroups: [[AppSection]] = [
        [.menuBar, .digest],
        [.home, .deepScan],
        [.cpu, .gpu, .memory, .sensors, .network, .bluetooth],
        [
            .storage, .timeline, .explore, .reclaim, .endurance,
            .attribution, .applications, .cloud, .maintenance, .ssdHealth,
        ],
    ]

    /// Rail order, flattened. Arrow-key navigation walks this, not
    /// `allCases`, so moving through the app matches what the eye sees.
    static let railOrder: [AppSection] = railGroups.flatMap { $0 }

    var world: FathomColorWorld {
        switch self {
        case .menuBar:
            .menuBar
        case .home:
            .home
        case .deepScan:
            .deepScan
        case .storage:
            .storage
        case .explore:
            .explore
        case .reclaim:
            .reclaim
        case .timeline:
            .timeline
        case .attribution:
            .attribution
        case .digest:
            .digest
        case .applications:
            .applications
        case .cloud:
            .cloud
        case .maintenance:
            .maintenance
        case .cpu:
            .cpu
        case .memory:
            .memory
        case .gpu:
            .gpu
        case .network:
            .network
        case .bluetooth:
            .bluetooth
        case .sensors:
            .sensors
        case .endurance:
            .endurance
        case .ssdHealth:
            .ssdHealth
        }
    }
}

struct FathomRootView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selection = AppSection.home
    @State private var showsCommandPalette = false

    var body: some View {
        ZStack {
            FathomWorldBackground(world: selection.world)

            HStack(spacing: 0) {
                // The rail is 64pt at every width. There is no expanded state
                // to collapse into, so the old width breakpoint is gone.
                FathomRail(selection: $selection)
                VStack(spacing: 0) {
                    FathomStatusStrip()
                    content
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .background(FathomSurface.contentPlate)
                    // A section arriving rises and fades. Keying the transition
                    // on the selection makes it play on navigation and not on
                    // the 1 Hz tick inside a section.
                    .id(selection)
                    .transition(
                        .opacity.combined(with: .offset(y: 12))
                    )
            }
        }
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .animation(reduceMotion ? nil : .fathomWorld, value: selection)
        .modifier(ArrowSectionNavigation(step: step))
        .onReceive(
            NotificationCenter.default.publisher(for: .fathomShowCommandPalette)
        ) { _ in
            showsCommandPalette = true
        }
        .sheet(isPresented: $showsCommandPalette) {
            CommandPaletteView(selection: $selection)
        }
    }

    /// Arrow keys move between sections in all four directions, wrapping at
    /// both ends. Rail order, not `allCases`, so moving through the app
    /// matches what the eye sees.
    private func step(_ direction: Int) {
        let order = AppSection.railOrder
        guard let index = order.firstIndex(of: selection) else { return }
        selection = order[(index + direction + order.count) % order.count]
    }

    @ViewBuilder
    private var content: some View {
        switch selection {
        case .menuBar:
            MenuBarSettingsView()
        case .home:
            HomeView(
                openStorage: { selection = .storage },
                openSSDHealth: { selection = .ssdHealth },
                open: { selection = $0 }
            )
        case .deepScan:
            DeepScanView(openExplore: { selection = .explore })
        case .storage:
            StorageView(openExplore: { selection = .explore })
        case .explore:
            ExploreView()
        case .reclaim:
            ReclaimView()
        case .timeline:
            TimelineView()
        case .attribution:
            AttributionView()
        case .digest:
            WeeklyDigestView()
        case .applications:
            ApplicationsView()
        case .cloud:
            CloudView()
        case .maintenance:
            MaintenanceView(openReclaim: { selection = .reclaim })
        case .cpu:
            CPUView()
        case .memory:
            MemoryView()
        case .gpu:
            GPUView()
        case .network:
            NetworkView()
        case .bluetooth:
            BluetoothView()
        case .sensors:
            SensorsView()
        case .endurance:
            EnduranceView(openSSDHealth: { selection = .ssdHealth })
        case .ssdHealth:
            SSDHealthView(openEndurance: { selection = .endurance })
        }
    }
}

/// The prototype's `addEventListener('keydown', …)`, which is what this app's
/// arrow navigation was actually specified as.
///
/// **`.onKeyPress` was the wrong primitive.** It only fires on a *focused*
/// view, and this window has no focused view: `Full Keyboard Access` is off by
/// default on macOS, so Tab reaches no button in the rail and nothing ever
/// takes the focus `onKeyPress` waits for. An instrumented build settled it —
/// an `NSEvent` monitor counted the arrow presses arriving at the process
/// while `onKeyPress` was called **zero** times. Two attempts to fix it by
/// making the root view focusable changed nothing, because the problem was
/// never which view had focus.
///
/// A window-level monitor is what `build-prototype.py` specifies and what
/// works. Consuming the event is that listener's `preventDefault()`: without
/// it the arrow would also scroll the content column it just navigated away
/// from.
///
/// It declines everything that belongs to something else. Modified presses are
/// the system's or a menu's — `Command-K` opens the palette and must keep
/// doing so. A press while a field editor is first responder is typing, not
/// navigating, and the palette's search field is exactly that case. A press
/// belonging to a sheet stays with the sheet.
private struct ArrowSectionNavigation: ViewModifier {
    let step: (Int) -> Void

    @State private var monitor: Any?

    func body(content: Content) -> some View {
        content
            .onAppear {
                guard monitor == nil else { return }
                monitor = NSEvent.addLocalMonitorForEvents(
                    matching: .keyDown
                ) { event in
                    guard Self.belongsToNavigation(event) else { return event }
                    switch event.keyCode {
                    case Self.downArrow, Self.rightArrow: step(1)
                    case Self.upArrow, Self.leftArrow: step(-1)
                    default: return event
                    }
                    return nil
                }
            }
            .onDisappear {
                if let monitor { NSEvent.removeMonitor(monitor) }
                monitor = nil
            }
    }

    private static let leftArrow: UInt16 = 123
    private static let rightArrow: UInt16 = 124
    private static let downArrow: UInt16 = 125
    private static let upArrow: UInt16 = 126

    private static func belongsToNavigation(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
        guard modifiers.isDisjoint(with: [.command, .control, .option]) else {
            return false
        }
        guard event.window?.isSheet != true else { return false }
        if event.window?.firstResponder is NSText { return false }
        return true
    }
}
