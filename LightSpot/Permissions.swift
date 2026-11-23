import AppKit
import ApplicationServices
import Observation
import ServiceManagement

enum Preferences {
    private static let onboardingKey = "hasCompletedOnboarding"

    static var hasCompletedOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: onboardingKey) }
        set { UserDefaults.standard.set(newValue, forKey: onboardingKey) }
    }
}

enum Permissions {
    static var isAccessibilityTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system "would like to control this computer" prompt (once per app),
    /// which also adds LightSpot to the Accessibility list.
    static func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary // kAXTrustedCheckOptionPrompt
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    static func openKeyboardShortcutsSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension?Shortcuts")!
        NSWorkspace.shared.open(url)
    }
}

/// Live app state for the SwiftUI windows: permission, login item and shortcut.
/// Polls while a window is visible, since macOS doesn't reliably notify on Accessibility changes.
@Observable
final class AppState {
    private(set) var isAccessibilityTrusted = Permissions.isAccessibilityTrusted
    private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled
    private(set) var shortcut = SpotlightTrigger.currentShortcut()
    var loginItemError: String?

    @ObservationIgnored private var timer: Timer?

    var shortcutDisplay: String { SpotlightTrigger.displayString(for: shortcut) }

    var isInApplicationsFolder: Bool {
        let path = Bundle.main.bundleURL.path
        return path.hasPrefix("/Applications/") || path.hasPrefix(NSHomeDirectory() + "/Applications/")
    }

    func startMonitoring() {
        refresh()
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        let trusted = Permissions.isAccessibilityTrusted
        if trusted != isAccessibilityTrusted { isAccessibilityTrusted = trusted }
        let login = SMAppService.mainApp.status == .enabled
        if login != launchAtLogin { launchAtLogin = login }
        let current = SpotlightTrigger.currentShortcut()
        if current != shortcut { shortcut = current }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginItemError = nil
        } catch {
            loginItemError = error.localizedDescription
        }
        refresh()
    }
}
