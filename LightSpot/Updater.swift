import AppKit
import Observation
import Sparkle

/// Software updates through Sparkle.
///
/// Release builds read the appcast attached to the latest GitHub release (`SUFeedURL` in Info.plist)
/// and only install updates signed with the maintainer's EdDSA key (`SUPublicEDKey`).
/// Debug builds never start the updater, so a build from source isn't replaced by the official one.
@Observable
final class Updater: NSObject, SPUStandardUserDriverDelegate {
    #if DEBUG
    static let isEnabled = false
    #else
    static let isEnabled = true
    #endif

    private(set) var canCheckForUpdates = false
    /// A scheduled check found an update and Sparkle showed it behind other windows.
    /// The menu then says "Update Available…" until the user looks at it.
    private(set) var isUpdateWaiting = false

    var automaticallyChecksForUpdates = false {
        didSet {
            guard let updater, updater.automaticallyChecksForUpdates != automaticallyChecksForUpdates else { return }
            updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        }
    }

    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    private var updater: SPUUpdater? { controller?.updater }

    override init() {
        super.init()
        guard Self.isEnabled else { return }

        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)
        self.controller = controller
        let updater = controller.updater
        canCheckForUpdates = updater.canCheckForUpdates
        automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates

        observations = [
            updater.observe(\.canCheckForUpdates, options: [.new]) { [weak self] updater, _ in
                MainActor.assumeIsolated { self?.canCheckForUpdates = updater.canCheckForUpdates }
            },
            // Changes when the user answers Sparkle's own "check automatically?" prompt.
            updater.observe(\.automaticallyChecksForUpdates, options: [.new]) { [weak self] updater, _ in
                MainActor.assumeIsolated {
                    guard let self, self.automaticallyChecksForUpdates != updater.automaticallyChecksForUpdates else { return }
                    self.automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
                }
            },
        ]
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }

    /// "Check for Updates…" for the status item menu, or nil in builds without updates.
    func makeMenuItem() -> NSMenuItem? {
        guard let controller else { return nil }
        let title = isUpdateWaiting ? "Update Available…" : "Check for Updates…"
        // SPUStandardUpdaterController validates this item itself (disabled while a check is running).
        let item = NSMenuItem(title: title, action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)), keyEquivalent: "")
        item.target = controller
        return item
    }

    // MARK: SPUStandardUserDriverDelegate
    // LightSpot has no Dock icon, so Sparkle's gentle reminders keep a scheduled update alert
    // from jumping in front of whatever the user is doing.

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        if !state.userInitiated { isUpdateWaiting = true }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        isUpdateWaiting = false
    }

    func standardUserDriverWillFinishUpdateSession() {
        isUpdateWaiting = false
    }
}
