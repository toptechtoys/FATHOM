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

    var symbol: String {
        switch self {
        case .menuBar:
            "menubar.rectangle"
        case .home:
            "house"
        case .deepScan:
            "magnifyingglass"
        case .storage:
            "externaldrive.fill"
        case .explore:
            "square.grid.2x2.fill"
        case .reclaim:
            "trash"
        case .timeline:
            "clock"
        case .attribution:
            "point.topleft.down.to.point.bottomright.curvepath"
        case .digest:
            "doc.text"
        case .applications:
            "square.grid.2x2"
        case .cloud:
            "icloud"
        case .maintenance:
            "wrench.and.screwdriver"
        case .cpu:
            "cpu"
        case .memory:
            "memorychip"
        case .gpu:
            "display"
        case .network:
            "network"
        case .bluetooth:
            "wave.3.right"
        case .sensors:
            "thermometer.medium"
        case .endurance:
            "shield.lefthalf.filled"
        case .ssdHealth:
            "waveform.path.ecg"
        }
    }

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
        GeometryReader { geometry in
            ZStack {
                FathomWorldBackground(world: selection.world)

                HStack(spacing: 0) {
                    FathomSidebar(
                        selection: $selection,
                        compact: geometry.size.width <= 1_080
                    )
                    content
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .animation(reduceMotion ? nil : .fathomWorld, value: selection)
        .onReceive(
            NotificationCenter.default.publisher(for: .fathomShowCommandPalette)
        ) { _ in
            showsCommandPalette = true
        }
        .sheet(isPresented: $showsCommandPalette) {
            CommandPaletteView(selection: $selection)
        }
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
