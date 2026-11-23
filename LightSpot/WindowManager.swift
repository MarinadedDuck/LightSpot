import AppKit
import SwiftUI

/// Owns the onboarding and settings windows. LightSpot has no Dock icon, so each window
/// activates the app when shown.
final class WindowManager: NSObject, NSWindowDelegate {
    let state = AppState()
    let updater: Updater
    private var onboardingWindow: NSWindow?
    private var settingsWindow: NSWindow?

    init(updater: Updater) {
        self.updater = updater
        super.init()
    }

    func showOnboarding(startingAt step: OnboardingStep = .welcome) {
        if let window = onboardingWindow {
            NotificationCenter.default.post(name: .onboardingJump, object: step)
            present(window)
            return
        }
        let view = OnboardingView(state: state, initialStep: step) { [weak self] in
            Preferences.hasCompletedOnboarding = true
            self?.onboardingWindow?.close()
        }
        let window = makeWindow(title: "Welcome to LightSpot", content: view)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        onboardingWindow = window
        present(window)
    }

    func showSettings() {
        if let window = settingsWindow {
            present(window)
            return
        }
        let view = SettingsView(state: state, updater: updater) { [weak self] in
            self?.settingsWindow?.close()
            self?.showOnboarding()
        }
        let window = makeWindow(title: "LightSpot Settings", content: view)
        settingsWindow = window
        present(window)
    }

    func showShortcutDisabledAlert() {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "The Spotlight keyboard shortcut is turned off"
        alert.informativeText = "LightSpot opens search by pressing your “Show Spotlight search” shortcut. Turn it back on in System Settings → Keyboard → Keyboard Shortcuts → Spotlight."
        alert.addButton(withTitle: "Open Keyboard Shortcuts")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            Permissions.openKeyboardShortcutsSettings()
        }
    }

    // MARK: Helpers

    private func makeWindow<V: View>(title: String, content: V) -> NSWindow {
        let hosting = NSHostingController(rootView: content)
        hosting.sizingOptions = [.preferredContentSize]
        let window = NSWindow(contentViewController: hosting)
        window.title = title
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        return window
    }

    private func present(_ window: NSWindow) {
        state.startMonitoring()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window === onboardingWindow {
            onboardingWindow = nil
            // Closing the welcome window counts as finishing it; it can be reopened from Settings.
            Preferences.hasCompletedOnboarding = true
        }
        if window === settingsWindow { settingsWindow = nil }
        if onboardingWindow == nil && settingsWindow == nil { state.stopMonitoring() }
    }
}

extension Notification.Name {
    static let onboardingJump = Notification.Name("LightSpotOnboardingJump")
}
