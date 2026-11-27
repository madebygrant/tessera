import AppKit
import TesseraCore

// One click-through panel per screen, dimmed, with the overlay's elements laid
// on it. Elements arrive in top-left global coordinates, as AX uses.
@MainActor
enum OverlayWindows {
    // One per display, kept between shows: rebuilding windows on every redraw
    // flickers while you cycle with the overlay up.
    private static var panels: [UInt32: NSPanel] = [:]
    // The Triad gold. Text on it is dark: white on gold is too faint to read.
    private static let accent = NSColor(srgbRed: 0xE3 / 255, green: 0xA8 / 255, blue: 0x3B / 255, alpha: 1)
    private static let onAccent = NSColor(srgbRed: 0x14 / 255, green: 0x14 / 255, blue: 0x14 / 255, alpha: 1)
    private static let muted = NSColor(srgbRed: 0xA9 / 255, green: 0xB1 / 255, blue: 0xBF / 255, alpha: 1)
    private static let soft = NSColor(srgbRed: 0xC3 / 255, green: 0xC9 / 255, blue: 0xD4 / 255, alpha: 1)
    private static let cardFill = NSColor(srgbRed: 20 / 255, green: 25 / 255, blue: 35 / 255, alpha: 0.62)

    static func hide() {
        for p in panels.values { p.orderOut(nil) }
    }

    static func show(_ elements: [OverlayElement]) {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        var shown: Set<UInt32> = []
        for screen in NSScreen.screens {
            let f = screen.frame
            let axFrame = CGRect(x: f.minX, y: primaryHeight - f.maxY, width: f.width, height: f.height)
            let mine = elements.filter { owner(of: $0, screens: NSScreen.screens, primaryHeight: primaryHeight) == screen }
            guard !mine.isEmpty else { continue }
            let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
            let panel = panels[id] ?? makePanel()
            panels[id] = panel
            panel.contentView = content(mine, size: f.size, origin: axFrame.origin)
            panel.setFrame(f, display: true)
            panel.orderFrontRegardless()
            shown.insert(id)
        }
        for (id, panel) in panels where !shown.contains(id) { panel.orderOut(nil) }
    }

    private static func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.overlayWindow)))
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        return panel
    }

    private static func content(_ elements: [OverlayElement], size: CGSize, origin: CGPoint) -> NSView {
        let k = max(1, min(1.6, size.height / 900))
        let root = FlippedView(frame: NSRect(origin: .zero, size: size))
        root.wantsLayer = true
        for element in elements { place(element, in: root, origin: origin, k: k) }
        return root
    }

    #if DEBUG
    // For `Tessera --snapshot-overlay`: draws elements for a screen of `size`
    // at the origin into a PNG, without showing anything.
    static func snapshot(_ elements: [OverlayElement], size: CGSize) -> Data? {
        let root = content(elements, size: size, origin: .zero)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = root
        root.layoutSubtreeIfNeeded()
        guard let rep = root.bitmapImageRepForCachingDisplay(in: root.bounds) else { return nil }
        root.cacheDisplay(in: root.bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }
    #endif

    private static func rect(of element: OverlayElement) -> CGRect {
        switch element {
        case let .scrim(r), let .anchor(r, _), let .appList(r, _, _, _, _), let .profiles(r, _, _),
             let .slot(r, _, _), let .focused(r, _), let .slotHint(r, _, _):
            r
        }
    }

    private static func owner(of element: OverlayElement, screens: [NSScreen], primaryHeight: CGFloat) -> NSScreen? {
        let r = rect(of: element)
        let mid = NSPoint(x: r.midX, y: primaryHeight - r.midY)
        return screens.first { $0.frame.contains(mid) } ?? screens.first
    }

    // MARK: Elements

    private static func place(_ element: OverlayElement, in root: NSView, origin: CGPoint, k: CGFloat) {
        let local = rect(of: element).offsetBy(dx: -origin.x, dy: -origin.y)
        switch element {
        case .scrim:
            let scrim = NSView(frame: local)
            scrim.wantsLayer = true
            scrim.layer?.backgroundColor = NSColor(white: 0.03, alpha: 0.5).cgColor
            root.addSubview(scrim)

        case let .anchor(_, name):
            let card = self.card(local.insetBy(dx: 16, dy: 16), border: NSColor(white: 1, alpha: 0.22), width: 1.5)
            root.addSubview(card)
            center(stack([
                label("ANCHOR", 12 * k, .semibold, muted, kern: 1.6),
                label(name, 36 * k, .semibold, .white),
                label("Stays here while you switch", 14 * k, .regular, soft),
            ], spacing: 10 * k, alignment: .centerX), in: card)

        case let .appList(_, rows, cycleKeys, maximizeKeys, maximized):
            let card = self.card(local.insetBy(dx: 16, dy: 16), border: accent, width: 3)
            root.addSubview(card)
            let width = min(460 * k, card.frame.width - 48)
            var items: [NSView] = [label("SWITCHER", 12 * k, .semibold, muted, kern: 1.6)]
            for row in rows { items.append(appRow(row, width: width, k: k)) }
            let rule = NSView()
            rule.wantsLayer = true
            rule.layer?.backgroundColor = NSColor(white: 1, alpha: 0.14).cgColor
            rule.translatesAutoresizingMaskIntoConstraints = false
            rule.heightAnchor.constraint(equalToConstant: 1).isActive = true
            rule.widthAnchor.constraint(equalToConstant: width - 28).isActive = true
            items.append(rule)
            items.append(stack([
                hint(cycleKeys, "cycle", k: k),
                hint(maximizeKeys, maximized ? "restore" : "fill the screen", k: k),
            ], spacing: 28 * k, orientation: .horizontal))
            let list = stack(items, spacing: 6 * k, alignment: .leading)
            list.setCustomSpacing(12 * k, after: rule)
            center(list, in: card)

        case let .profiles(screen, chips, shared):
            var parts: [NSView] = chips.map { chip in
                let row = stack([keycap(chip.key, k: k, onFill: chip.active),
                                 label(chip.name, 14 * k, chip.active ? .semibold : .regular, chip.active ? onAccent : soft, truncates: true)],
                                spacing: 8 * k, orientation: .horizontal)
                return pad(row, h: 14 * k, height: 40 * k, fill: chip.active ? accent : nil, radius: 11 * k)
            }
            if !shared.isEmpty { parts.append(pad(label("with \(shared)", 12 * k, .regular, muted), h: 8 * k, height: 40 * k)) }
            bottomPill(stack(parts, spacing: 6 * k, orientation: .horizontal), in: root,
                       area: screen.offsetBy(dx: -origin.x, dy: -origin.y), k: k)

        case let .slot(_, key, name):
            let card = self.card(local.insetBy(dx: 16, dy: 16), border: NSColor(white: 1, alpha: 0.35), width: 2, dashed: true)
            root.addSubview(card)
            let compact = card.frame.height < 260 * k
            let size = (compact ? 52 : 88) * k
            center(stack([bigKeycap(key, size: size), label(name, (compact ? 17 : 24) * k, .semibold, .white)],
                         spacing: 14 * k, alignment: .centerX), in: card)

        case let .focused(_, app):
            let frame = NSView(frame: local)
            frame.wantsLayer = true
            frame.layer?.borderColor = accent.cgColor
            frame.layer?.borderWidth = 3
            frame.layer?.cornerRadius = 12
            frame.layer?.backgroundColor = NSColor(white: 1, alpha: 0.06).cgColor
            root.addSubview(frame)
            let tag = pad(label("Focused: \(app)", 13 * k, .semibold, onAccent, truncates: true), h: 10 * k, height: 26 * k, fill: accent, radius: 13 * k)
            tag.widthAnchor.constraint(lessThanOrEqualToConstant: max(60, local.width - 24)).isActive = true
            frame.addSubview(tag)
            NSLayoutConstraint.activate([
                tag.leadingAnchor.constraint(equalTo: frame.leadingAnchor, constant: 12),
                tag.topAnchor.constraint(equalTo: frame.topAnchor, constant: 12),
            ])

        case let .slotHint(screen, modifiers, app):
            let what = label(app.map { "\($0)'s window" } ?? "the focused window", 14 * k, .semibold, .white, truncates: true)
            let line = stack([keycap(modifiers, k: k), label("+ a number sends", 14 * k, .regular, soft), what,
                              label("to that slot", 14 * k, .regular, soft)], spacing: 8 * k, orientation: .horizontal)
            bottomPill(pad(line, h: 10 * k, height: 40 * k), in: root, area: screen.offsetBy(dx: -origin.x, dy: -origin.y), k: k)
        }
    }

    private static func appRow(_ row: OverlayElement.AppRow, width: CGFloat, k: CGFloat) -> NSView {
        let showing = row.state == .showing
        let keys = stack(row.keys.map { keycap($0, k: k) }, spacing: 4 * k, orientation: .horizontal)
        let name = label(row.name, 22 * k, showing ? .semibold : .medium, .white, truncates: true)
        var parts: [NSView] = [keys, name, NSView()]
        switch row.state {
        case .showing: parts.append(pad(label("Showing", 12 * k, .semibold, onAccent), h: 8 * k, height: 22 * k, fill: accent, radius: 11 * k))
        case .notRunning: parts.append(label("opens on switch", 12 * k, .regular, muted))
        case .ready: break
        }
        let line = stack(parts, spacing: 14 * k, orientation: .horizontal)
        line.distribution = .fill
        parts[2].setContentHuggingPriority(.init(1), for: .horizontal)
        let box = pad(line, h: 14 * k, height: 60 * k, fill: showing ? accent.withAlphaComponent(0.22) : nil, radius: 12 * k)
        box.widthAnchor.constraint(equalToConstant: width).isActive = true
        return box
    }

    private static func hint(_ keys: [String], _ text: String, k: CGFloat) -> NSView {
        stack(keys.map { keycap($0, k: k) } + [label(text, 14 * k, .regular, soft)], spacing: 6 * k, orientation: .horizontal)
    }

    // MARK: Building blocks

    private static func card(_ frame: CGRect, border: NSColor, width: CGFloat, dashed: Bool = false) -> NSView {
        let view = NSView(frame: frame)
        view.wantsLayer = true
        view.layer?.backgroundColor = cardFill.cgColor
        view.layer?.cornerRadius = 20
        if dashed {
            let outline = CAShapeLayer()
            outline.path = CGPath(roundedRect: CGRect(origin: .zero, size: frame.size).insetBy(dx: width / 2, dy: width / 2),
                                  cornerWidth: 20, cornerHeight: 20, transform: nil)
            outline.fillColor = nil
            outline.strokeColor = border.cgColor
            outline.lineWidth = width
            outline.lineDashPattern = [10, 8]
            view.layer?.addSublayer(outline)
        } else {
            view.layer?.borderColor = border.cgColor
            view.layer?.borderWidth = width
        }
        return view
    }

    // `truncates`: names that can be long give way first when space runs out,
    // instead of Auto Layout breaking a constraint of its choosing.
    private static func label(_ text: String, _ size: CGFloat, _ weight: NSFont.Weight, _ color: NSColor,
                              kern: CGFloat = 0, truncates: Bool = false) -> NSTextField {
        let field = NSTextField(labelWithAttributedString: NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .kern: kern,
        ]))
        field.translatesAutoresizingMaskIntoConstraints = false
        if truncates {
            field.lineBreakMode = .byTruncatingTail
            field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        return field
    }

    private static func keycap(_ text: String, k: CGFloat, onFill: Bool = false) -> NSView {
        let ink = onFill ? onAccent : NSColor.white
        let cap = pad(label(text, 13 * k, .semibold, ink), h: 6 * k, height: 24 * k, fill: ink.withAlphaComponent(0.12), radius: 6 * k)
        cap.layer?.borderColor = ink.withAlphaComponent(0.2).cgColor
        cap.layer?.borderWidth = 1
        cap.widthAnchor.constraint(greaterThanOrEqualToConstant: 24 * k).isActive = true
        return cap
    }

    private static func bigKeycap(_ text: String, size: CGFloat) -> NSView {
        let cap = NSView()
        cap.wantsLayer = true
        cap.layer?.backgroundColor = NSColor(white: 1, alpha: 0.1).cgColor
        cap.layer?.borderColor = NSColor(white: 1, alpha: 0.28).cgColor
        cap.layer?.borderWidth = 1.5
        cap.layer?.cornerRadius = size * 0.23
        cap.translatesAutoresizingMaskIntoConstraints = false
        let text = label(text, size * 0.55, .bold, .white)
        cap.addSubview(text)
        NSLayoutConstraint.activate([
            cap.widthAnchor.constraint(equalToConstant: size), cap.heightAnchor.constraint(equalToConstant: size),
            text.centerXAnchor.constraint(equalTo: cap.centerXAnchor), text.centerYAnchor.constraint(equalTo: cap.centerYAnchor),
        ])
        return cap
    }

    // `content` centred in a box of fixed height, with side padding and an optional fill.
    private static func pad(_ content: NSView, h: CGFloat, height: CGFloat, fill: NSColor? = nil, radius: CGFloat = 0) -> NSView {
        let box = NSView()
        box.wantsLayer = true
        box.layer?.backgroundColor = fill?.cgColor
        box.layer?.cornerRadius = radius
        box.translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(content)
        NSLayoutConstraint.activate([
            box.heightAnchor.constraint(equalToConstant: height),
            content.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: h),
            content.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -h),
            content.centerYAnchor.constraint(equalTo: box.centerYAnchor),
        ])
        return box
    }

    private static func stack(_ views: [NSView], spacing: CGFloat, orientation: NSUserInterfaceLayoutOrientation = .vertical,
                              alignment: NSLayoutConstraint.Attribute? = nil) -> NSStackView {
        let s = NSStackView(views: views)
        s.orientation = orientation
        s.spacing = spacing
        s.alignment = alignment ?? (orientation == .horizontal ? .centerY : .leading)
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }

    private static func center(_ content: NSView, in container: NSView) {
        container.addSubview(content)
        NSLayoutConstraint.activate([
            content.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            content.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
    }

    private static func bottomPill(_ content: NSView, in root: NSView, area: CGRect, k: CGFloat) {
        let pill = NSView()
        pill.wantsLayer = true
        pill.layer?.backgroundColor = NSColor(srgbRed: 16 / 255, green: 20 / 255, blue: 28 / 255, alpha: 0.88).cgColor
        pill.layer?.borderColor = NSColor(white: 1, alpha: 0.12).cgColor
        pill.layer?.borderWidth = 1
        pill.layer?.cornerRadius = 16 * k
        pill.translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        pill.addSubview(content)
        root.addSubview(pill)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 6 * k),
            content.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -6 * k),
            content.topAnchor.constraint(equalTo: pill.topAnchor, constant: 6 * k),
            content.bottomAnchor.constraint(equalTo: pill.bottomAnchor, constant: -6 * k),
            pill.centerXAnchor.constraint(equalTo: root.leadingAnchor, constant: area.midX),
            pill.widthAnchor.constraint(lessThanOrEqualToConstant: area.width - 32),
            pill.bottomAnchor.constraint(equalTo: root.topAnchor, constant: area.maxY - 36 * k),
        ])
    }
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
