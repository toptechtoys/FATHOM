import Combine
import FathomKit
import Foundation

@MainActor
final class PublicIPAppModel: ObservableObject {
    @Published private(set) var measurement: FathomKit.Measurement<PublicIPSnapshot> =
        .notPublished(reason: "Public IP lookup is disabled")
    @Published private(set) var isRefreshing = false
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
            if isEnabled {
                refresh()
            } else {
                measurement = .notPublished(reason: "Public IP lookup is disabled")
            }
        }
    }

    private static let enabledKey = "privacy.publicIP.enabled"
    private let service: PublicIPService

    init() {
        isEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        service = PublicIPService(
            cacheURL: base
                .appendingPathComponent("FATHOM", isDirectory: true)
                .appendingPathComponent("public-ip-cache.json")
        )
    }

    func refresh() {
        guard isEnabled, !isRefreshing else { return }
        isRefreshing = true
        Task {
            measurement = await service.read(enabled: true)
            isRefreshing = false
        }
    }
}
