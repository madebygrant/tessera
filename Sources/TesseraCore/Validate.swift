extension Config {
    // Checked at load, or a typo surfaces on a keypress halfway through a profile switch.
    public func validate() throws {
        _ = try nonEmptyModifiers(keys.switcher, "keys.switcher")
        try key(keys.maximize, "keys.maximize")
        if let mods = keys.profile { _ = try nonEmptyModifiers(mods, "keys.profile") }
        if let mods = keys.slotMove { _ = try nonEmptyModifiers(mods, "keys.slotMove") }
        if let delay = overlay?.delay, delay < 0 {
            throw ConfigError("overlay.delay can't be negative")
        }
        if isOn(slotMove) && keys.slotMove == nil {
            throw ConfigError("slotMove is on but keys.slotMove is missing")
        }

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
            if let list = p.slots, let dup = list.first(where: { s in list.filter { $0 == s }.count > 1 }) {
                throw ConfigError("\(at) slots lists '\(dup)' twice")
            }
            if isOn(slotMove) && p.slotOrder.count > 9 {
                throw ConfigError("\(at) has \(p.slotOrder.count) slots for slot move; number keys stop at 9")
            }
            for ref in p.screens ?? [] where screens[ref] == nil {
                throw ConfigError("\(at) screens names unknown screen '\(ref)'")
            }
        }
        try checkCollisions()
    }

    // Two bindings on one combo: the second fails to register, and the key
    // silently does the first one's job.
    private func checkCollisions() throws {
        var combos: [String: String] = [:]
        func claim(_ mods: [String], _ key: String, _ what: String) throws {
            let set = (try? KeyNames.modifiers(mods)) ?? []
            let combo = Modifier.allCases.filter(set.contains).map(\.rawValue).joined(separator: "+") + "+" + key.lowercased()
            if let other = combos[combo] {
                throw ConfigError("\(combo) is bound twice: \(other) and \(what)")
            }
            combos[combo] = what
        }
        let sw = keys.switcher
        for i in 0..<maxSwitcherApps { try claim(sw, "\(i + 1)", "switcher app \(i + 1)") }
        try claim(sw, "left", "switcher left")
        try claim(sw, "right", "switcher right")
        try claim(sw, keys.maximize, "maximize")
        for (name, p) in profiles.sorted(by: { $0.key < $1.key }) {
            try claim(p.modifier ?? keys.profile ?? [], p.key, "profile '\(name)'")
        }
        if isOn(slotMove), let mods = keys.slotMove {
            for i in 0..<maxSlotMoveKeys { try claim(mods, "\(i + 1)", "slot move \(i + 1)") }
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
