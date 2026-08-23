import AppKit
import Dispatch
import FathomKit

@MainActor
final class FathomBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(
        withLength: NSStatusItem.variableLength
    )
    private let sampler = FathomBarSampler()
    /// Measures what this process costs, on the loop that costs it.
    private let idleSampler = ProcessCPUSampler()
    private var samplingTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var sleeping = false
    private var pressureSource: DispatchSourceMemoryPressure?
    private var pressureLabel: String?
    private var latestPresentation: FathomBarPresentation?

    override init() {
        super.init()
        statusItem.autosaveName = "com.exhibinaut.fathom.bar"
        statusItem.button?.title = "FATHOM —"
        statusItem.button?.font = .monospacedDigitSystemFont(
            ofSize: NSFont.systemFontSize,
            weight: .medium
        )
        statusItem.button?.toolTip = "FATHOM measurements"
        statusItem.menu = makeMenu()
        observeVisibilityAndSleep()
        observeMemoryPressure()
        reconcileSampling()
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "Values are traceable in FATHOM", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Idle cost: not published", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        let quit = NSMenuItem(
            title: "Quit FATHOM Bar",
            action: #selector(quitApplication),
            keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(quit)
        return menu
    }

    @objc private func quitApplication() {
        NSApplication.shared.terminate(nil)
    }

    private func observeVisibilityAndSleep() {
        if let window = statusItem.button?.window {
            observers.append(
                NotificationCenter.default.addObserver(
                    forName: NSWindow.didChangeOcclusionStateNotification,
                    object: window,
                    queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated { self?.reconcileSampling() }
                }
            )
        }
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(
            workspace.addObserver(
                forName: NSWorkspace.willSleepNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.sleeping = true
                    self?.reconcileSampling()
                }
            }
        )
        observers.append(
            workspace.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.sleeping = false
                    self?.reconcileSampling()
                }
            }
        )
    }

    private func reconcileSampling() {
        let visible = statusItem.button?.window?.occlusionState
            .contains(.visible) == true
        if visible && !sleeping {
            startSampling()
        } else {
            samplingTask?.cancel()
            samplingTask = nil
        }
    }

    private func startSampling() {
        guard samplingTask == nil else { return }
        samplingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let presentation = await sampler.sample()
                latestPresentation = presentation
                updateButton()
                await publishOwnCost()
                do {
                    try await Task.sleep(
                        for: .seconds(5),
                        tolerance: .milliseconds(500)
                    )
                } catch {
                    return
                }
            }
        }
    }

    /// Publishes what this widget costs, measured on the loop that costs it.
    ///
    /// The measurement is taken across the same interval the widget actually
    /// runs on, so it includes the sample, the button update and the sleep —
    /// which is the figure a user cares about, not the cost of the read alone.
    private func publishOwnCost() async {
        guard case let .known(percent, _) = await idleSampler.sample() else {
            return
        }
        let defaults = UserDefaults(
            suiteName: FathomBarConfiguration.suiteName
        ) ?? .standard
        defaults.set(percent, forKey: FathomBarConfiguration.measuredIdleCPUKey)
        defaults.set(
            Date().timeIntervalSinceReferenceDate,
            forKey: FathomBarConfiguration.measuredIdleAtKey
        )
        defaults.set(
            FathomBarConfiguration.load().enabledItemCount,
            forKey: FathomBarConfiguration.measuredIdleItemCountKey
        )
    }

    private func observeMemoryPressure() {
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.normal, .warning, .critical],
            queue: .main
        )
        source.setEventHandler { [weak self, weak source] in
            guard let self, let event = source?.data else { return }
            if event.contains(.critical) {
                pressureLabel = "MEMORY CRITICAL"
            } else if event.contains(.warning) {
                pressureLabel = "MEMORY WARNING"
            } else {
                pressureLabel = nil
            }
            updateButton()
        }
        source.resume()
        pressureSource = source
    }

    private func updateButton() {
        guard let button = statusItem.button else { return }
        let title = latestPresentation?.title ?? "FATHOM —"
        let accessibility = latestPresentation?.accessibilityLabel
            ?? "FATHOM measurements not yet published"
        guard let pressureLabel else {
            button.attributedTitle = NSAttributedString(
                string: title,
                attributes: [
                    .font: NSFont.monospacedDigitSystemFont(
                        ofSize: NSFont.systemFontSize,
                        weight: .medium
                    )
                ]
            )
            button.setAccessibilityLabel(accessibility)
            return
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.minimumLineHeight = 8
        paragraph.maximumLineHeight = 9
        let attributed = NSMutableAttributedString(
            string: title + "\n",
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(
                    ofSize: 8.5,
                    weight: .medium
                ),
                .paragraphStyle: paragraph
            ]
        )
        attributed.append(
            NSAttributedString(
                string: pressureLabel,
                attributes: [
                    .font: NSFont.systemFont(ofSize: 7, weight: .bold),
                    .foregroundColor: NSColor.labelColor,
                    .paragraphStyle: paragraph
                ]
            )
        )
        button.attributedTitle = attributed
        button.setAccessibilityLabel(
            accessibility + ", " + pressureLabel.lowercased()
        )
    }
}
