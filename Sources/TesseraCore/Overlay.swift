import CoreGraphics

public enum OverlayLayer: Sendable {
    case switcher, slotMove
}

// What the overlay shows, in top-left screen coordinates. The app decides how
// each piece looks; the core decides what's there.
public enum OverlayElement: Sendable, Equatable {
    public struct AppRow: Sendable, Equatable {
        public enum State: Sendable, Equatable { case showing, ready, notRunning }
        public let keys: [String]
        public let name: String
        public let state: State
        public init(keys: [String], name: String, state: State) {
            self.keys = keys
            self.name = name
            self.state = state
        }
    }

    public struct ProfileChip: Sendable, Equatable {
        // Just the key when the profile uses the shared layer, else its full chord.
        public let key: String
        public let name: String
        public let active: Bool
        public init(key: String, name: String, active: Bool) {
            self.key = key
            self.name = name
            self.active = active
        }
    }

    // Dims one whole screen.
    case scrim(CGRect)
    case anchor(CGRect, name: String)
    case appList(CGRect, rows: [AppRow], cycleKeys: [String], maximizeKeys: [String], maximized: Bool)
    // Along the bottom of this screen area.
    case profiles(CGRect, chips: [ProfileChip], sharedModifiers: String)
    case slot(CGRect, key: String, name: String)
    case focused(CGRect, app: String)
    // Along the bottom of this screen area: what the layer's keys do to `app`.
    case slotHint(CGRect, modifiers: String, app: String?)
}

// heliumDev -> Helium Dev
func prettyName(_ ref: String) -> String {
    var out = ""
    var previous: Character?
    for c in ref {
        if c.isUppercase, let p = previous, p.isLowercase || p.isNumber { out.append(" ") }
        out.append(c)
        previous = c
    }
    return out.prefix(1).uppercased() + out.dropFirst()
}

// Hold a key layer's modifiers alone for `delay` and the overlay shows what
// that layer's keys do. Release hides it; a key press first makes it a chord.
@MainActor
final class Overlay {
    private unowned let engine: Engine
    private let delay: Double
    private(set) var held: OverlayLayer?
    private var showTimer: Cancellable?
    private var redrawTimer: Cancellable?
    private var previewTimer: Cancellable?
    private(set) var visible = false

    init(engine: Engine, delay: Double) {
        self.engine = engine
        self.delay = delay
    }

    func stop() {
        showTimer?.cancel()
        showTimer = nil
        held = nil
        hide()
    }

    func modifiersChanged(_ mods: Set<Modifier>) {
        let layer = layer(for: mods)
        guard layer != held || previewTimer != nil else { return }
        held = layer
        showTimer?.cancel()
        showTimer = nil
        hide()
        guard let layer else { return }
        showTimer = engine.scheduler.after(delay) { [weak self] in
            self?.showTimer = nil
            self?.draw(layer)
        }
    }

    // Called from the tap and from every hotkey: under Secure Keyboard Entry
    // the tap sees no keys, but the hotkeys still fire.
    func keyDown() {
        showTimer?.cancel()
        showTimer = nil
        // Already showing: redraw once the key's action has run, so it shows the
        // new index. Key repeat pushes it back rather than stacking redraws.
        guard visible, let layer = held else { return }
        redrawTimer?.cancel()
        redrawTimer = engine.scheduler.after(0.15) { [weak self] in
            self?.redrawTimer = nil
            if self?.held == layer { self?.draw(layer) }
        }
    }

    // From the menu, with no keys held: shows the switcher layer for a few
    // seconds, or until a modifier changes.
    func preview() {
        let elements = switcherElements()
        guard !elements.isEmpty else { return }
        visible = true
        engine.platform.showOverlay(elements)
        previewTimer?.cancel()
        previewTimer = engine.scheduler.after(4) { [weak self] in
            self?.previewTimer = nil
            self?.hide()
        }
    }

    private func layer(for mods: Set<Modifier>) -> OverlayLayer? {
        let config = engine.config
        if mods == (try? KeyNames.modifiers(config.keys.switcher)) { return .switcher }
        if config.isOn(config.slotMove), let slotMods = config.keys.slotMove,
           mods == (try? KeyNames.modifiers(slotMods)) {
            return .slotMove
        }
        return nil
    }

    private func hide() {
        redrawTimer?.cancel()
        redrawTimer = nil
        previewTimer?.cancel()
        previewTimer = nil
        guard visible else { return }
        visible = false
        engine.platform.hideOverlay()
    }

    func draw(_ layer: OverlayLayer) {
        // A missed release would otherwise leave it up with no keys held.
        guard self.layer(for: engine.platform.heldModifiers) == layer else {
            held = nil
            return hide()
        }
        let elements = layer == .switcher ? switcherElements() : slotMoveElements()
        guard !elements.isEmpty else { return }
        visible = true
        engine.platform.showOverlay(elements)
    }

    private var scrims: [OverlayElement] { engine.platform.screens.map { .scrim($0.frame) } }

    func switcherElements() -> [OverlayElement] {
        let config = engine.config
        guard let profile = engine.profile, let block = engine.switcher.block else { return [] }
        let switcher = engine.switcher!
        let mods = KeyNames.glyphs(config.keys.switcher)
        var out = scrims

        let anchorFrame = engine.frame(ofSlot: block.anchorSlot)
        let otherFrame = engine.frame(ofSlot: block.otherSlot)
        // A full-screen profile shares one frame; the list alone says it all.
        if anchorFrame != otherFrame {
            out.append(.anchor(anchorFrame, name: prettyName(block.anchor)))
        }
        // No cycled apps: the switcher keys do nothing, so don't list them.
        if !block.apps.isEmpty {
            let rows = block.apps.enumerated().map { i, ref in
                let running = config.apps[ref].map { !engine.platform.processes(named: $0.app).isEmpty } ?? false
                let state: OverlayElement.AppRow.State = i == switcher.index ? .showing : (running ? .ready : .notRunning)
                return OverlayElement.AppRow(keys: [mods, "\(i + 1)"], name: prettyName(ref), state: state)
            }
            out.append(.appList(otherFrame, rows: rows, cycleKeys: [mods, "←", "→"],
                                maximizeKeys: [mods, KeyNames.label(config.keys.maximize)], maximized: switcher.maximized))
        }
        if let screen = engine.usableScreen(ofSlot: block.anchorSlot) {
            let shared = KeyNames.glyphs(config.keys.profile ?? [])
            let byKey = config.profiles.sorted { ($0.value.key.lowercased(), $0.key) < ($1.value.key.lowercased(), $1.key) }
            let chips = byKey.map { name, p in
                let own = p.modifier.map(KeyNames.glyphs)
                let key = (own != nil && own != shared ? own! : "") + KeyNames.label(p.key)
                return OverlayElement.ProfileChip(key: key, name: prettyName(name), active: name == profile)
            }
            out.append(.profiles(screen, chips: chips, sharedModifiers: shared))
        }
        return out
    }

    func slotMoveElements() -> [OverlayElement] {
        let config = engine.config
        guard let name = engine.profile, let order = config.profiles[name]?.slotOrder, !order.isEmpty,
              let mods = config.keys.slotMove.map(KeyNames.glyphs)
        else { return [] }
        var out = scrims
        out += order.enumerated().map { i, slot in .slot(engine.frame(ofSlot: slot), key: "\(i + 1)", name: prettyName(slot)) }

        let front = engine.platform.frontmostWindowSummary()
        let appName = front?.app
        if let front { out.append(.focused(front.frame, app: front.app)) }
        if let screen = engine.usableScreen(ofSlot: order[0]) {
            out.append(.slotHint(screen, modifiers: mods, app: appName))
        }
        return out
    }
}
