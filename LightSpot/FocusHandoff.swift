import AppKit
import os

let log = Logger(subsystem: "io.github.marinadedduck.LightSpot", category: "focus")

/// Makes sure the Spotlight shortcut reaches the system, not the frontmost app.
///
/// Apps such as Screen Sharing, remote desktop clients and virtual machines capture
/// system shortcuts like ⌘Space while they're frontmost and forward them to the remote
/// machine. So before sending the shortcut, LightSpot briefly makes itself the active app.
///
/// The search bar is a non-activating panel, so LightSpot stays frontmost while it's open.
/// Once the panel closes (or never appears), LightSpot hands focus back to the previous app,
/// unless the user has moved on to another app, e.g. by opening a search result.
@MainActor
final class FocusHandoff {
    static let shared = FocusHandoff()

    private var previousApp: NSRunningApplication?
    private var timer: Timer?
    private var startedAt = Date()
    private var panelSeen = false
    private var generation = 0

    /// Siri AI's bundle ID; it hosts the search bar on macOS 27.
    private let searchHostBundleIDs: Set<String> = ["com.apple.campo", "com.apple.Spotlight"]
    private var ownPID: pid_t { ProcessInfo.processInfo.processIdentifier }

    /// Runs `action` (which sends the shortcut) once LightSpot is the active app.
    func perform(_ action: @escaping @MainActor () -> Void) {
        // A click while a handoff is already in progress (e.g. clicking the icon again to
        // close search) just toggles search; keep watching so focus still goes back.
        if timer != nil, previousApp != nil, NSApp.isActive {
            log.notice("click during search: toggling")
            action()
            return
        }
        stop()
        let front = NSWorkspace.shared.frontmostApplication
        log.notice("click: frontmost=\(front?.bundleIdentifier ?? "nil", privacy: .public) isActive=\(NSApp.isActive)")
        guard let front, front.processIdentifier != ownPID, !NSApp.isActive else {
            action() // LightSpot is already frontmost (e.g. "Try It Now").
            return
        }

        previousApp = front
        generation += 1
        let current = generation
        forceActivate()
        let started = Date()
        waitForActivation(deadline: started.addingTimeInterval(0.5)) { [weak self] in
            guard let self, self.generation == current else { return } // superseded by a newer click
            let nowFront = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "nil"
            log.notice("posting after \(Int(Date().timeIntervalSince(started) * 1000))ms: frontmost=\(nowFront, privacy: .public) isActive=\(NSApp.isActive)")
            action()
            if NSApp.isActive { self.startWatching() } else { self.stop() }
        }
    }

    /// Since macOS 14, `NSApp.activate()` is only a request, and the system refuses it for
    /// a menu bar app. With Accessibility permission, LightSpot can mark itself frontmost
    /// through the accessibility API instead, the way window managers and app switchers do.
    private func forceActivate() {
        NSApp.activate()
        let me = AXUIElementCreateApplication(ownPID)
        let result = AXUIElementSetAttributeValue(me, "AXFrontmost" as CFString, kCFBooleanTrue) // kAXFrontmostAttribute
        if result != .success {
            log.notice("AXFrontmost failed: \(result.rawValue)")
            NSRunningApplication.current.activate(options: [.activateAllWindows])
        }
    }

    /// Waits until the system agrees LightSpot is frontmost (or the deadline passes), then
    /// a little longer so the previous app has handled losing focus and released the keyboard.
    private func waitForActivation(deadline: Date, then run: @escaping @MainActor () -> Void) {
        let isFront = NSWorkspace.shared.frontmostApplication?.processIdentifier == ownPID
        if (NSApp.isActive && isFront) || Date() >= deadline {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: run)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self] in
            self?.waitForActivation(deadline: deadline, then: run)
        }
    }

    // MARK: Watching the search bar

    private func startWatching() {
        startedAt = Date()
        panelSeen = false
        timer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { _ in
            MainActor.assumeIsolated { FocusHandoff.shared.tick() }
        }
    }

    private func tick() {
        // The user switched to another app (or opened a search result): nothing to restore.
        if let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != ownPID,
           !searchHostBundleIDs.contains(front.bundleIdentifier ?? "") {
            log.notice("user moved to \(front.bundleIdentifier ?? "nil", privacy: .public); not restoring")
            stop()
            return
        }

        let visible = isSearchPanelVisible()
        if visible { panelSeen = true }

        let elapsed = Date().timeIntervalSince(startedAt)
        let dismissed = panelSeen && !visible
        let neverOpened = !panelSeen && elapsed > 1.5
        if dismissed || neverOpened || elapsed > 600 {
            log.notice("search ended: panelSeen=\(self.panelSeen) dismissed=\(dismissed) neverOpened=\(neverOpened)")
            restoreIfStranded()
        }
    }

    /// Hands focus back only if LightSpot is frontmost with nothing of its own on screen.
    private func restoreIfStranded() {
        let app = previousApp
        stop()
        let hasOwnWindow = NSApp.windows.contains { $0.isVisible && $0.canBecomeKey }
        if NSApp.isActive, !hasOwnWindow, let app, !app.isTerminated {
            app.activate()
        }
    }

    private func stop() {
        generation += 1
        timer?.invalidate()
        timer = nil
        previousApp = nil
    }

    /// True while the search bar window is on screen. Reads only window metadata
    /// (owner, layer, alpha), which doesn't need Screen Recording permission.
    private func isSearchPanelVisible() -> Bool {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return false }
        let hostPIDs = Set(NSWorkspace.shared.runningApplications
            .filter { searchHostBundleIDs.contains($0.bundleIdentifier ?? "") }
            .map(\.processIdentifier))
        return list.contains { w in
            guard let pid = w[kCGWindowOwnerPID as String] as? pid_t, hostPIDs.contains(pid),
                  let layer = w[kCGWindowLayer as String] as? Int, layer > 0,
                  let alpha = w[kCGWindowAlpha as String] as? Double, alpha > 0.01,
                  let bounds = w[kCGWindowBounds as String] as? [String: Any],
                  let height = bounds["Height"] as? Double, height > 60
            else { return false }
            return true
        }
    }
}
