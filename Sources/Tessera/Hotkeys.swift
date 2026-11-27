import Carbon
import TesseraCore

// Carbon hotkeys need no Accessibility or Input Monitoring permission.
@MainActor
final class Hotkeys {
    private static var handlers: [UInt32: @MainActor () -> Void] = [:]
    private static var nextID: UInt32 = 1
    private static var installed = false
    // While Tessera's own menu is open its items handle the same chords, and
    // both firing would toggle Fill the Screen on and straight back off.
    static var paused = false
    private var registered: [(ref: EventHotKeyRef, id: UInt32)] = []

    init() { Self.installHandler() }

    // Replaces every binding. Returns what won't work, one line each, for the
    // caller to show: keys this layout puts on one physical key, clashes with
    // macOS shortcuts, and combos another app already holds.
    func bindAll(_ bindings: [Binding]) -> [String] {
        unbindAll()
        var problems: [String] = []
        var taken: [String: (combo: String, purpose: String)] = [:]
        for b in bindings {
            guard let code = KeyLayout.code(b.key), let mods = try? KeyNames.modifiers(b.modifiers) else { continue }
            let combo = KeyNames.glyphs(b.modifiers) + KeyNames.label(b.key)
            let flags = Self.carbonFlags(mods)
            let physical = "\(code)/\(flags)"
            if let other = taken[physical] {
                problems.append("\(combo) (\(b.purpose)) is the same key as \(other.combo) (\(other.purpose)) on this layout")
                continue
            }
            taken[physical] = (combo, b.purpose)
            if let system = SystemShortcuts.clash(code: code, modifiers: mods) {
                problems.append("\(combo) (\(b.purpose)) is also macOS's \"\(system)\"")
            }
            if !register(code, flags, b.action) {
                problems.append("\(combo) (\(b.purpose)) is taken by another app")
            }
        }
        return problems
    }

    private static func carbonFlags(_ mods: Set<Modifier>) -> UInt32 {
        var flags: UInt32 = 0
        if mods.contains(.cmd) { flags |= UInt32(cmdKey) }
        if mods.contains(.alt) { flags |= UInt32(optionKey) }
        if mods.contains(.ctrl) { flags |= UInt32(controlKey) }
        if mods.contains(.shift) { flags |= UInt32(shiftKey) }
        return flags
    }

    private func register(_ code: UInt32, _ flags: UInt32, _ action: @escaping @MainActor () -> Void) -> Bool {
        let id = Self.nextID
        Self.nextID += 1
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: 0x7473_7261, id: id) // "tsra"
        guard RegisterEventHotKey(code, flags, hotKeyID, GetApplicationEventTarget(), 0, &ref) == noErr, let ref else {
            return false
        }
        Self.handlers[id] = action
        registered.append((ref, id))
        return true
    }

    func unbindAll() {
        for (ref, id) in registered {
            UnregisterEventHotKey(ref)
            Self.handlers[id] = nil
        }
        registered = []
    }

    private static func installHandler() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID
            )
            let id = hotKeyID.id
            MainActor.assumeIsolated {
                if !Hotkeys.paused { Hotkeys.handlers[id]?() }
            }
            return noErr
        }, 1, &spec, nil, nil)
    }
}
