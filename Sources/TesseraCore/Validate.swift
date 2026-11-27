extension Config {
    // Checked at load, or a typo surfaces on a keypress halfway through a profile switch.
    public func validate() throws {
        _ = try nonEmptyModifiers(keys.switcher, "keys.switcher")
        try key(keys.maximize, "keys.maximize")
        if let mods = keys.profile { _ = try nonEmptyModifiers(mods, "keys.profile") }
        if let mods = keys.slotMove { _ = try nonEmptyModifiers(mods, "keys.slotMove") }

        guard profiles[defaultProfile] != nil else {
            throw ConfigError("defaultProfile '\(defaultProfile)' is not a profile")
        }
        for (ref, slot) in slots {
            for (field, v) in [("x", slot.x), ("y", slot.y), ("w", slot.w), ("h", slot.h)] {
                if let v, !(0...1).contains(v) {
                    throw ConfigError("slot '\(ref)' \(field) = \(v) is outside 0..1")
                }
            }
        }

        for (name, p) in profiles.sorted(by: { $0.key < $1.key }) {
            let at = "profile '\(name)'"
            try key(p.key, "\(at) key")
            guard let mods = p.modifier ?? keys.profile else {
                throw ConfigError("\(at) has no modifier and keys.profile is missing")
            }
            _ = try nonEmptyModifiers(mods, "\(at) modifier")

            let sw = p.switcher
            try app(sw.anchor, "\(at) switcher.anchor")
            try slot(sw.anchorSlot, "\(at) switcher.anchorSlot")
            try slot(sw.otherSlot, "\(at) switcher.otherSlot")
            try slot(sw.fullSlot, "\(at) switcher.fullSlot")
            for ref in sw.apps { try app(ref, "\(at) switcher.apps") }
            if sw.apps.count > 9 {
                throw ConfigError("\(at) switcher.apps has \(sw.apps.count) apps; number keys stop at 9")
            }
            if let start = sw.start, !sw.apps.contains(start) {
                throw ConfigError("\(at) starts on '\(start)', which is not in its switcher apps")
            }
            for item in p.place ?? [] {
                try app(item.app, "\(at) place")
                try slot(item.slot, "\(at) place")
            }
            for s in p.slots ?? [] { try slot(s, "\(at) slots") }
            for ref in p.screens ?? [] where screens[ref] == nil {
                throw ConfigError("\(at) screens names unknown screen '\(ref)'")
            }
        }
    }

    private func app(_ ref: String, _ field: String) throws {
        guard apps[ref] != nil else { throw ConfigError("\(field) names unknown app '\(ref)'") }
    }

    private func slot(_ ref: String, _ field: String) throws {
        guard slots[ref] != nil else { throw ConfigError("\(field) names unknown slot '\(ref)'") }
    }

    private func key(_ name: String, _ field: String) throws {
        guard KeyNames.code(name) != nil else { throw ConfigError("\(field) '\(name)' is not a key Tessera knows") }
    }

    // An empty list would bind the bare key and take over typing.
    private func nonEmptyModifiers(_ names: [String], _ field: String) throws -> Set<Modifier> {
        let set: Set<Modifier>
        do { set = try KeyNames.modifiers(names) } catch let e as ConfigError {
            throw ConfigError("\(field): \(e.description)")
        }
        guard !set.isEmpty else { throw ConfigError("\(field) needs at least one modifier") }
        return set
    }
}
