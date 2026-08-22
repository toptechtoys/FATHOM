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
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .onKeyPress(action: navigate)
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
    /// both ends. A modified press is ignored so the app never eats a system
    /// or text-editing shortcut.
    private func navigate(_ press: KeyPress) -> KeyPress.Result {
        guard press.modifiers.isEmpty else { return .ignored }
        let step: Int
        switch press.key {
        case .downArrow, .rightArrow: step = 1
        case .upArrow, .leftArrow: step = -1
        default: return .ignored
        }
        let order = AppSection.railOrder
        guard let index = order.firstIndex(of: selection) else { return .ignored }
        selection = order[(index + step + order.count) % order.count]
        return .handled
    }

    @ViewBuilder
    private var content: some View {
        switch selection {
        case .menuBar:
            MenuBarSettingsView()
        case .home:
            HomeView(
                openStorage: { selection = .storage },
                openSSDHealth: { selection = .ssdHealth }
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
