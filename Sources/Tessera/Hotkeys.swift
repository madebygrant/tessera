import Carbon
import TesseraCore

// Carbon hotkeys need no Accessibility or Input Monitoring permission.
@MainActor
final class Hotkeys {
    private static var handlers: [UInt32: @MainActor () -> Void] = [:]
    private static var nextID: UInt32 = 1
    private static var installed = false
    private var registered: [(ref: EventHotKeyRef, id: UInt32)] = []

    init() { Self.installHandler() }

    @discardableResult
    func bind(_ modifiers: [String], _ key: String, _ action: @escaping @MainActor () -> Void) -> Bool {
        guard let code = KeyNames.code(key), let mods = try? KeyNames.modifiers(modifiers) else { return false }
        var flags: UInt32 = 0
        if mods.contains(.cmd) { flags |= UInt32(cmdKey) }
        if mods.contains(.alt) { flags |= UInt32(optionKey) }
        if mods.contains(.ctrl) { flags |= UInt32(controlKey) }
        if mods.contains(.shift) { flags |= UInt32(shiftKey) }

        let id = Self.nextID
        Self.nextID += 1
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: 0x7473_7261, id: id) // "tsra"
        let status = RegisterEventHotKey(code, flags, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else {
            HUD.show("couldn't bind \(modifiers.joined(separator: "+"))+\(key); another app may own it")
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
            MainActor.assumeIsolated { Hotkeys.handlers[id]?() }
            return noErr
        }, 1, &spec, nil, nil)
    }
}
