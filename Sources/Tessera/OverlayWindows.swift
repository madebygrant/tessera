import AppKit
import TesseraCore

@MainActor
enum OverlayWindows {
    private static var panels: [NSPanel] = []
    private static let accent = NSColor(red: 0.38, green: 0.78, blue: 1.0, alpha: 1)
    private static let dim = NSColor(white: 1, alpha: 0.7)

    static func show(_ boxes: [OverlayBox]) {
        hide()
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        panels = boxes.map { panel(for: $0, primaryHeight: primaryHeight) }
        for p in panels { p.orderFrontRegardless() }
    }

    static func hide() {
        for p in panels { p.orderOut(nil) }
        panels = []
    }

    private static func text(_ box: OverlayBox) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = box.leftAligned ? .left : .center
        paragraph.lineSpacing = 4
        let out = NSMutableAttributedString()
        for (i, line) in box.lines.enumerated() {
            if i > 0 { out.append(NSAttributedString(string: "\n")) }
            for run in line {
                let size = CGFloat(run.size)
                let color: NSColor = switch run.tone {
                case .normal: .white
                case .dim: dim
                case .accent: accent
                }
                out.append(NSAttributedString(string: run.text, attributes: [
                    .font: run.bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size),
                    .foregroundColor: color,
                ]))
            }
        }
        out.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: out.length))
        return out
    }

    private static func panel(for box: OverlayBox, primaryHeight: CGFloat) -> NSPanel {
        let body = text(box)
        func measure(_ width: CGFloat) -> CGSize {
            body.boundingRect(
                with: CGSize(width: width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading]
            ).size
        }

        // Top-left coordinates, as the core works in. Measured at the width the
        // text gets, so wrapped lines are counted.
        let frame: CGRect
        let size: CGSize
        switch box.placement {
        case let .fill(r):
            frame = r
            size = measure(max(r.width - 32, 1))
        case let .legend(screen):
            size = measure(screen.width - 32 - 48)
            frame = CGRect(x: screen.midX - (size.width + 48) / 2, y: screen.maxY - size.height - 24 - 40,
                           width: size.width + 48, height: size.height + 24)
        }
        let cocoa = NSRect(x: frame.minX, y: primaryHeight - frame.maxY, width: frame.width, height: frame.height)

        let panel = NSPanel(contentRect: cocoa, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.overlayWindow)))
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false

        let content = NSView(frame: NSRect(origin: .zero, size: cocoa.size))
        let card = NSView(frame: content.bounds.insetBy(dx: 8, dy: 8))
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor(white: 0.05, alpha: 0.55).cgColor
        card.layer?.borderColor = (box.highlight ? accent : dim).cgColor
        card.layer?.borderWidth = box.highlight ? 4 : 2
        card.layer?.cornerRadius = 14
        content.addSubview(card)

        // Sized to the text and centred, so left-aligned lines stay a centred block.
        let label = NSTextField(labelWithAttributedString: body)
        label.maximumNumberOfLines = 0
        let w = min(size.width + 4, cocoa.width)
        label.frame = NSRect(x: (cocoa.width - w) / 2, y: (cocoa.height - size.height) / 2, width: w, height: size.height + 4)
        content.addSubview(label)
        panel.contentView = content
        return panel
    }
}
