import AppKit
import Dispatch
import FathomKit

/// AppKit plumbing only.
///
/// Everything this used to decide for itself — what a failed read renders as,
/// how long a reading may be reused, which memory pressure bit wins, whether a
/// self-measurement may be published and what the menu says about it — now
/// lives in FathomKit, where a test can reach it. This target has no test
/// scheme (`project.yml` declares `testTargets: []` for both), so anything
/// making a claim from in here is a claim nothing checks.
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
    private var pressure: FathomBarMemoryPressure?
    private var latestPresentation: FathomBarPresentation?
    private var idleCostItem: NSMenuItem?
    /// The item count the menu bar was drawing when the interval being
    /// measured began. A cost measured across a configuration change belongs to
    /// neither count, and `MeasuredIdleCost.publication` withholds it.
    private var itemCountAtPreviousSample: Int?

    override init() {
        super.init()
        statusItem.autosaveName = "com.exhibinaut.fathom.bar"
        // The not-yet-sampled title is the same not-published state every other
        // reading has, so it is spelled once, in FathomKit, beside the label
        // that explains it. That label is not applied until the first draw —
        // see the note in the handoff; the UI owner has the accessibility pass.
        statusItem.button?.title = FathomBarPresentation.notYetSampled.title
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
        let cost = NSMenuItem(
            title: MeasuredIdleCost.menuTitle(for: MeasuredIdleCost.load()),
            action: nil,
            keyEquivalent: ""
        )
        menu.addItem(cost)
        idleCostItem = cost
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
                await publishOwnCost(itemCount: presentation.itemCount)
                do {
                    try await Task.sleep(
                        for: .seconds(FathomBarSamplingPlan.intervalSeconds),
                        tolerance: .seconds(
                            FathomBarSamplingPlan.toleranceSeconds
                        )
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
    ///
    /// The count that travels with it is the count of what was drawn, not the
    /// count `FathomBarConfiguration.load()` answers at this instant: those are
    /// the same number until the user changes the configuration, and on that
    /// tick they are the two ends of the interval being reported.
    private func publishOwnCost(itemCount: Int) async {
        let measurement = await idleSampler.sample()
        let publication = MeasuredIdleCost.publication(
            cost: measurement,
            itemCountAtStartOfInterval: itemCountAtPreviousSample ?? itemCount,
            itemCountNow: itemCount,
            now: Date()
        )
        itemCountAtPreviousSample = itemCount
        guard case let .published(cost) = publication else { return }
        cost.write(
            to: UserDefaults(suiteName: FathomBarConfiguration.suiteName)
                ?? .standard
        )
        idleCostItem?.title = MeasuredIdleCost.menuTitle(
            for: MeasuredIdleCost.load()
        )
    }

    private func observeMemoryPressure() {
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.normal, .warning, .critical],
            queue: .main
        )
        source.setEventHandler { [weak self, weak source] in
            guard let self, let event = source?.data else { return }
            pressure = FathomBarMemoryPressure.from(events: event)
            updateButton()
        }
        source.resume()
        pressureSource = source
    }

    private func updateButton() {
        guard let button = statusItem.button else { return }
        let content = (latestPresentation ?? .notYetSampled)
            .buttonContent(pressure: pressure)
        guard let pressureLine = content.pressureLine else {
            button.attributedTitle = NSAttributedString(
                string: content.title,
                attributes: [
                    .font: NSFont.monospacedDigitSystemFont(
                        ofSize: NSFont.systemFontSize,
                        weight: .medium
                    )
                ]
            )
            button.setAccessibilityLabel(content.accessibilityLabel)
            return
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.minimumLineHeight = 8
        paragraph.maximumLineHeight = 9
        let attributed = NSMutableAttributedString(
            string: content.title + "\n",
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
                string: pressureLine,
                attributes: [
                    .font: NSFont.systemFont(ofSize: 7, weight: .bold),
                    .foregroundColor: NSColor.labelColor,
                    .paragraphStyle: paragraph
                ]
            )
        )
        button.attributedTitle = attributed
        button.setAccessibilityLabel(content.accessibilityLabel)
    }
}
