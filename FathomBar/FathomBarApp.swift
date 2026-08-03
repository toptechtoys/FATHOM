import AppKit

@main
final class FathomBarApp: NSObject, NSApplicationDelegate {
    private var controller: FathomBarController?

    static func main() {
        let application = NSApplication.shared
        let delegate = FathomBarApp()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
    }

    func applicationDidFinishLaunching(
        _ notification: Notification
    ) {
        controller = FathomBarController()
    }
}
