import AppKit
import Carbon
import TesseraCore

// Letters go through the active layout, so "f" is the key labelled F on
// Dvorak or AZERTY. Digits keep their US positions: AZERTY's number row types
// digits only with shift, and ⌃⌥1 should still be the key marked 1.
enum KeyLayout {
    static func code(_ key: String) -> UInt32? {
        let k = key.lowercased()
        if k.count == 1, k.first?.isLetter == true, let code = letterCodes()[k] { return code }
        return KeyNames.code(k)
    }

    static var name: String {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(source, kTISPropertyLocalizedName)
        else { return "unknown" }
        return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
    }

    // Letter -> key code for the current layout, from what each key types unshifted.
    static func letterCodes() -> [String: UInt32] {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return [:] }
        let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        var map: [String: UInt32] = [:]
        data.withUnsafeBytes { raw in
            guard let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return }
            for code in 0..<128 {
                var dead: UInt32 = 0
                var length = 0
                var chars = [UniChar](repeating: 0, count: 4)
                let status = UCKeyTranslate(
                    layout, UInt16(code), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                    OptionBits(kUCKeyTranslateNoDeadKeysBit), &dead, chars.count, &length, &chars
                )
                guard status == noErr, length == 1 else { continue }
                let s = String(utf16CodeUnits: chars, count: length).lowercased()
                if s.first?.isLetter == true, map[s] == nil { map[s] = UInt32(code) }
            }
        }
        return map
    }
}

// macOS's own shortcuts (System Settings > Keyboard > Keyboard Shortcuts).
// Whichever registers first wins, so a clash leaves one of them dead.
enum SystemShortcuts {
    private static let names: [Int: String] = [
        7: "Move focus to the menu bar", 8: "Move focus to the Dock", 9: "Move focus to active or next window",
        10: "Move focus to the window toolbar", 11: "Move focus to the floating window",
        12: "Turn keyboard access on or off", 27: "Move focus to next window", 52: "Turn Dock hiding on/off",
        28: "Save picture of screen as a file", 29: "Copy picture of screen to the clipboard",
        30: "Save picture of selected area as a file", 31: "Copy picture of selected area to the clipboard",
        32: "Mission Control", 33: "Application windows", 36: "Show Desktop",
        60: "Select the previous input source", 61: "Select next source in Input menu",
        64: "Show Spotlight search", 65: "Show Finder search window",
        79: "Move left a space", 81: "Move right a space", 184: "Screenshot and recording options",
        118: "Switch to Desktop 1", 119: "Switch to Desktop 2", 120: "Switch to Desktop 3",
        121: "Switch to Desktop 4", 122: "Switch to Desktop 5", 123: "Switch to Desktop 6",
        124: "Switch to Desktop 7", 125: "Switch to Desktop 8", 126: "Switch to Desktop 9",
    ]

    // Shortcuts the user never changed are missing from the plist, so their
    // defaults are listed here: id -> (key code, modifiers, on by default).
    private static let defaults: [Int: (UInt32, Set<Modifier>, Bool)] = [
        32: (126, [.ctrl], true), 33: (125, [.ctrl], true), 79: (123, [.ctrl], true), 81: (124, [.ctrl], true),
        64: (49, [.cmd], true), 65: (49, [.cmd, .alt], true), 60: (49, [.ctrl], true), 61: (49, [.ctrl, .alt], true),
        36: (103, [], true), 52: (2, [.cmd, .alt], true), 27: (50, [.cmd], true),
        12: (122, [.ctrl], true), 7: (120, [.ctrl], true), 8: (99, [.ctrl], true), 9: (118, [.ctrl], true),
        10: (96, [.ctrl], true), 11: (97, [.ctrl], true),
        28: (20, [.cmd, .shift], true), 29: (20, [.ctrl, .cmd, .shift], true),
        30: (21, [.cmd, .shift], true), 31: (21, [.ctrl, .cmd, .shift], true), 184: (23, [.cmd, .shift], true),
        118: (18, [.ctrl], false), 119: (19, [.ctrl], false), 120: (20, [.ctrl], false), 121: (21, [.ctrl], false),
    ]

    private static func flags(_ mods: Set<Modifier>) -> Int {
        var f = 0
        if mods.contains(.shift) { f |= 1 << 17 }
        if mods.contains(.ctrl) { f |= 1 << 18 }
        if mods.contains(.alt) { f |= 1 << 19 }
        if mods.contains(.cmd) { f |= 1 << 20 }
        return f
    }

    // The name of an enabled macOS shortcut on this combo, if any.
    static func clash(code: UInt32, modifiers: Set<Modifier>) -> String? {
        let saved = UserDefaults(suiteName: "com.apple.symbolichotkeys")?
            .dictionary(forKey: "AppleSymbolicHotKeys") ?? [:]
        var live: [Int: (UInt32, Int)] = [:]
        for (id, (code, mods, on)) in defaults where on { live[id] = (code, flags(mods)) }
        for (key, value) in saved {
            guard let id = Int(key), let entry = value as? [String: Any] else { continue }
            live[id] = nil
            guard (entry["enabled"] as? Bool) == true,
                  let params = (entry["value"] as? [String: Any])?["parameters"] as? [Int], params.count == 3
            else { continue }
            // Masked to the four modifiers; arrow keys also carry fn and keypad bits.
            live[id] = (UInt32(params[1]), params[2] & 0x1E0000)
        }
        let want = flags(modifiers)
        guard let id = live.first(where: { $0.value.0 == code && $0.value.1 == want })?.key else { return nil }
        return names[id] ?? "macOS shortcut #\(id)"
    }
}
