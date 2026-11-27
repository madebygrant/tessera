public enum Modifier: String, CaseIterable, Sendable {
    case ctrl, alt, shift, cmd

    var glyph: String {
        switch self {
        case .ctrl: "⌃"
        case .alt: "⌥"
        case .shift: "⇧"
        case .cmd: "⌘"
        }
    }
}

public enum KeyNames {
    private static let aliases: [String: Modifier] = [
        "ctrl": .ctrl, "control": .ctrl, "⌃": .ctrl,
        "alt": .alt, "option": .alt, "opt": .alt, "⌥": .alt,
        "shift": .shift, "⇧": .shift,
        "cmd": .cmd, "command": .cmd, "⌘": .cmd,
    ]

    public static func modifiers(_ names: [String]) throws -> Set<Modifier> {
        var set: Set<Modifier> = []
        for name in names {
            guard let m = aliases[name.lowercased()] else {
                throw ConfigError("unknown modifier '\(name)'")
            }
            set.insert(m)
        }
        return set
    }

    // Virtual key codes for the US ANSI layout. Carbon hotkeys bind physical
    // keys, so on another layout a letter binds whatever sits in that position.
    private static let codes: [String: UInt32] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
        "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
        "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26,
        "-": 27, "8": 28, "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35,
        "return": 36, "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43,
        "/": 44, "n": 45, "m": 46, ".": 47, "tab": 48, "space": 49, "`": 50,
        "delete": 51, "escape": 53,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97, "f7": 98,
        "f8": 100, "f9": 101, "f10": 109, "f11": 103, "f12": 111,
        "left": 123, "right": 124, "down": 125, "up": 126,
    ]

    public static func code(_ key: String) -> UInt32? {
        codes[key.lowercased()]
    }

    // In the order macOS menus print them: ⌃⌥⇧⌘.
    static func glyphs(_ names: [String]) -> String {
        let set = (try? modifiers(names)) ?? []
        return Modifier.allCases.filter(set.contains).map(\.glyph).joined()
    }

    static func label(_ key: String) -> String {
        let names = ["left": "←", "right": "→", "up": "↑", "down": "↓", "space": "Space"]
        return names[key.lowercased()] ?? key.uppercased()
    }
}
