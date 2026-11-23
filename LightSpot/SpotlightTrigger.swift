import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Opens the system search bar by pressing the user's "Show Spotlight search" shortcut.
enum SpotlightTrigger {
    enum Status { case ready, needsAccessibility, shortcutDisabled }

    struct Shortcut: Equatable {
        var keyCode: CGKeyCode
        var flags: CGEventFlags
        var isEnabled: Bool

        static let `default` = Shortcut(keyCode: CGKeyCode(kVK_Space), flags: .maskCommand, isEnabled: true)
    }

    static func check() -> Status {
        if !Permissions.isAccessibilityTrusted { return .needsAccessibility }
        if !currentShortcut().isEnabled { return .shortcutDisabled }
        return .ready
    }

    static func open() {
        post(currentShortcut())
    }

    // MARK: Reading the shortcut

    /// Reads symbolic hot key 64 ("Show Spotlight search") from the system preferences,
    /// so a remapped shortcut still works. Falls back to ⌘Space.
    static func currentShortcut() -> Shortcut {
        guard let hotkeys = UserDefaults(suiteName: "com.apple.symbolichotkeys")?
                .dictionary(forKey: "AppleSymbolicHotKeys"),
              let entry = hotkeys["64"] as? [String: Any]
        else { return .default }

        let enabled = (entry["enabled"] as? Bool) ?? true
        guard let value = entry["value"] as? [String: Any],
              let params = value["parameters"] as? [Int], params.count >= 3
        else { return Shortcut(keyCode: Shortcut.default.keyCode, flags: Shortcut.default.flags, isEnabled: enabled) }

        let mods = UInt64(params[2])
        var flags: CGEventFlags = []
        if mods & (1 << 17) != 0 { flags.insert(.maskShift) }
        if mods & (1 << 18) != 0 { flags.insert(.maskControl) }
        if mods & (1 << 19) != 0 { flags.insert(.maskAlternate) }
        if mods & (1 << 20) != 0 { flags.insert(.maskCommand) }
        return Shortcut(keyCode: CGKeyCode(params[1]), flags: flags, isEnabled: enabled)
    }

    /// A readable form of the shortcut, e.g. "⌘Space".
    static func displayString(for shortcut: Shortcut) -> String {
        var s = ""
        if shortcut.flags.contains(.maskControl) { s += "⌃" }
        if shortcut.flags.contains(.maskAlternate) { s += "⌥" }
        if shortcut.flags.contains(.maskShift) { s += "⇧" }
        if shortcut.flags.contains(.maskCommand) { s += "⌘" }
        return s + keyName(shortcut.keyCode)
    }

    private static func keyName(_ code: CGKeyCode) -> String {
        switch Int(code) {
        case kVK_Space: return "Space"
        case kVK_Return: return "Return"
        case kVK_Tab: return "Tab"
        case kVK_Escape: return "Esc"
        case kVK_F1...kVK_F20: break
        default: break
        }
        if let char = translate(code) { return char.uppercased() }
        return "Key \(code)"
    }

    private static func translate(_ code: CGKeyCode) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        var deadKeys: UInt32 = 0
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        let status = data.withUnsafeBytes { raw -> OSStatus in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return -1 }
            return UCKeyTranslate(layout, code, UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                                  OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, chars.count, &length, &chars)
        }
        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: chars, count: length)
    }

    // MARK: Posting the shortcut

    private static let modifierKeys: [(flag: CGEventFlags, key: Int)] = [
        (.maskCommand, kVK_Command), (.maskShift, kVK_Shift), (.maskAlternate, kVK_Option), (.maskControl, kVK_Control),
    ]

    /// Posts a complete key sequence: each modifier down, the key down and up, then each
    /// modifier up. Sending only a flagged key event (with no modifier key-up) leaves
    /// Siri AI thinking Command is still held, and every later press is ignored.
    private static func post(_ shortcut: Shortcut) {
        let source = CGEventSource(stateID: .hidSystemState)
        let mods = modifierKeys.filter { shortcut.flags.contains($0.flag) }
        var events: [CGEvent] = []
        var held: CGEventFlags = []

        func add(_ key: CGKeyCode, down: Bool) {
            guard let e = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down) else { return }
            e.flags = held
            events.append(e)
        }

        for m in mods { held.insert(m.flag); add(CGKeyCode(m.key), down: true) }
        add(shortcut.keyCode, down: true)
        add(shortcut.keyCode, down: false)
        for m in mods.reversed() { held.remove(m.flag); add(CGKeyCode(m.key), down: false) }

        for (i, event) in events.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(15 * i)) {
                event.post(tap: .cghidEventTap)
            }
        }
    }
}
