import CoreGraphics

public enum OverlayLayer: Sendable {
    case switcher, slotMove
}

public struct OverlayRun: Sendable, Equatable {
    public enum Tone: Sendable { case normal, dim, accent }
    public let text: String
    public let size: Double
    public let tone: Tone
    public let bold: Bool
}

public struct OverlayBox: Sendable, Equatable {
    public enum Placement: Sendable, Equatable {
        case fill(CGRect)
        // A pill sized to its text, along the bottom of this screen area.
        case legend(CGRect)
    }
    public let placement: Placement
    public let lines: [[OverlayRun]]
    public let leftAligned: Bool
    public let highlight: Bool
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
        guard layer != held else { return }
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
        let boxes = layer == .switcher ? switcherBoxes() : slotMoveBoxes()
        guard !boxes.isEmpty else { return }
        visible = true
        engine.platform.showOverlay(boxes)
    }

    // Sizes suit a laptop-height slot; a tall 4K slot gets up to 1.8x.
    private func scale(_ frame: CGRect) -> Double { max(1, min(1.8, frame.height / 900)) }

    private func run(_ text: String, _ size: Double, _ tone: OverlayRun.Tone = .normal, bold: Bool = false) -> OverlayRun {
        OverlayRun(text: text, size: size, tone: tone, bold: bold)
    }

    func switcherBoxes() -> [OverlayBox] {
        let config = engine.config
        guard let profile = engine.profile, let block = engine.switcher.block else { return [] }
        let switcher = engine.switcher!
        let mods = KeyNames.glyphs(config.keys.switcher)
        var boxes: [OverlayBox] = []

        let anchorFrame = engine.frame(ofSlot: block.anchorSlot)
        let otherFrame = engine.frame(ofSlot: block.otherSlot)
        // A full-screen profile shares one frame; the list box alone says it all.
        if anchorFrame != otherFrame {
            let k = scale(anchorFrame)
            boxes.append(OverlayBox(placement: .fill(anchorFrame), lines: [
                [run(prettyName(block.anchor), 30 * k, bold: true)],
                [run("anchor", 15 * k, .dim)],
            ], leftAligned: false, highlight: false))
        }

        // No cycled apps: the switcher keys do nothing, so don't list them.
        if !block.apps.isEmpty {
            let k = scale(otherFrame)
            var lines = block.apps.enumerated().map { i, ref in
                let on = i == switcher.index
                return [run("\(mods)\(i + 1)    ", 22 * k, .dim), run(prettyName(ref), 22 * k, on ? .accent : .normal, bold: on)]
            }
            let maximize = KeyNames.label(config.keys.maximize)
            lines.append([run("", 14 * k)])
            lines.append([run("\(mods)← →  cycle      \(mods)\(maximize)  " + (switcher.maximized ? "restore" : "maximize"), 14 * k, .dim)])
            boxes.append(OverlayBox(placement: .fill(otherFrame), lines: lines, leftAligned: true, highlight: true))
        }

        if let screen = engine.usableScreen(ofSlot: block.anchorSlot) {
            let k = scale(screen)
            var legend: [OverlayRun] = []
            let byKey = config.profiles.sorted { ($0.value.key.lowercased(), $0.key) < ($1.value.key.lowercased(), $1.key) }
            for (name, p) in byKey {
                if !legend.isEmpty { legend.append(run("     ", 15 * k)) }
                let on = name == profile
                let chord = KeyNames.glyphs(p.modifier ?? config.keys.profile ?? []) + KeyNames.label(p.key)
                legend.append(run("\(chord)  ", 15 * k, .dim))
                legend.append(run(prettyName(name), 15 * k, on ? .accent : .normal, bold: on))
            }
            boxes.append(OverlayBox(placement: .legend(screen), lines: [legend], leftAligned: false, highlight: false))
        }
        return boxes
    }

    func slotMoveBoxes() -> [OverlayBox] {
        let config = engine.config
        guard let name = engine.profile, let order = config.profiles[name]?.slotOrder,
              let mods = config.keys.slotMove.map(KeyNames.glyphs)
        else { return [] }
        return order.enumerated().map { i, slot in
            let frame = engine.frame(ofSlot: slot)
            let k = scale(frame)
            return OverlayBox(placement: .fill(frame), lines: [
                [run("\(mods)\(i + 1)", 34 * k, bold: true)],
                [run(prettyName(slot), 16 * k, .dim)],
                [run("send the focused window here", 13 * k, .dim)],
            ], leftAligned: false, highlight: false)
        }
    }
}
