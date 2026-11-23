import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: StatusItemController?
    private let updater = Updater()
    private lazy var windows = WindowManager(updater: updater)

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = StatusItemController(
            updater: updater,
            onOpenSearch: { [weak self] in self?.openSearch() },
            onShowSettings: { [weak self] in self?.windows.showSettings() }
        )

        if !Preferences.hasCompletedOnboarding {
            windows.showOnboarding()
        }
    }

    /// Opening the app again (Finder, Spotlight, Launchpad) while it's running shows Settings.
    /// This is the way back in if the menu bar icon has been hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        windows.showSettings()
        return true
    }

    /// `lightspot://open` opens the search bar, for Shortcuts and scripts.
    /// `lightspot://settings` opens Settings.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "lightspot" {
            switch url.host() {
            case "settings": windows.showSettings()
            default: openSearch(delay: 0.1)
            }
        }
    }

    func openSearch(delay: TimeInterval = 0.1) {
        switch SpotlightTrigger.check() {
        case .ready:
            // Let the menu bar finish its click tracking before sending the shortcut.
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                FocusHandoff.shared.perform { SpotlightTrigger.open() }
            }
        case .needsAccessibility:
            windows.showOnboarding(startingAt: .accessibility)
        case .shortcutDisabled:
            windows.showShortcutDisabledAlert()
        }
    }
}
