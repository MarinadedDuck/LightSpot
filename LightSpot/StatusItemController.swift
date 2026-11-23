import AppKit

/// The menu bar magnifying glass.
/// Left-click opens the search bar. Right-click (or Control-click) shows a menu.
final class StatusItemController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let updater: Updater
    private let onOpenSearch: () -> Void
    private let onShowSettings: () -> Void

    init(updater: Updater, onOpenSearch: @escaping () -> Void, onShowSettings: @escaping () -> Void) {
        self.updater = updater
        self.onOpenSearch = onOpenSearch
        self.onShowSettings = onShowSettings
        super.init()

        statusItem.autosaveName = "LightSpotStatusItem"
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "Search")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "Search (LightSpot)"
            button.target = self
            button.action = #selector(clicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    @objc private func clicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showMenu()
        } else {
            onOpenSearch()
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.addItem(item("Open Search", #selector(openSearchFromMenu)))
        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(showSettings), key: ","))
        if let updateItem = updater.makeMenuItem() { menu.addItem(updateItem) }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit LightSpot", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil // keep left-click as a direct action
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func openSearchFromMenu() {
        // The menu needs a moment longer than a plain click to close.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [onOpenSearch] in onOpenSearch() }
    }

    @objc private func showSettings() { onShowSettings() }
}
