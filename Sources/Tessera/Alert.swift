import AppKit
import TesseraCore
import os

let log = Logger(subsystem: "local.tessera", category: "app")

// Errors stack under the menu bar icon, each with a way out, and go after 10s
// or on Dismiss. Clicks land without taking focus from the app in front.
@MainActor
enum Toasts {
    // The status item's frame on screen; toasts hang below it.
    static var anchor: (() -> NSRect?)?
    private static var panels: [NSPanel] = []
    private static let width: CGFloat = 360
    private static let maxShown = 4

    static func show(_ notice: Notice, seconds: Double = 10) {
        log.error("\(notice.title, privacy: .public): \(notice.detail, privacy: .public) \(notice.code ?? "", privacy: .public)")
        let panel = makePanel(notice)
        panels.insert(panel, at: 0)
        while panels.count > maxShown { close(panels.removeLast()) }
        layout()
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.18; panel.animator().alphaValue = 1 }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            dismiss(panel)
        }
    }

    private static func dismiss(_ panel: NSPanel) {
        guard let i = panels.firstIndex(of: panel) else { return }
        panels.remove(at: i)
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.18; panel.animator().alphaValue = 0 }, completionHandler: {
            MainActor.assumeIsolated { close(panel) }
        })
        layout()
    }

    private static func close(_ panel: NSPanel) { panel.orderOut(nil) }

    private static func layout() {
        let anchorFrame = anchor?()
        let screen = NSScreen.screens.first { s in anchorFrame.map { s.frame.contains(NSPoint(x: $0.midX, y: $0.midY)) } ?? false }
            ?? NSScreen.main ?? NSScreen.screens.first
        guard let visible = screen?.visibleFrame else { return }
        let right = anchorFrame.map { min($0.midX + width / 2, visible.maxX - 10) } ?? visible.maxX - 10
        var top = visible.maxY - 8
        for panel in panels {
            let size = panel.frame.size
            panel.setFrameOrigin(NSPoint(x: max(visible.minX + 10, right - width), y: top - size.height))
            top -= size.height + 10
        }
    }

    private static func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = .labelColor, mono: Bool = false) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = mono ? .monospacedSystemFont(ofSize: size, weight: weight) : .systemFont(ofSize: size, weight: weight)
        field.textColor = color
        field.preferredMaxLayoutWidth = width - 14 * 2 - 32 - 12
        return field
    }

    private static func makePanel(_ notice: Notice) -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: width, height: 80),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.appearance = NSAppearance(named: .darkAqua)

        let card = NSVisualEffectView()
        card.material = .hudWindow
        card.blendingMode = .behindWindow
        card.state = .active
        card.wantsLayer = true
        card.layer?.cornerRadius = 14
        card.layer?.masksToBounds = true
        card.layer?.borderWidth = 1
        card.layer?.borderColor = (notice.code != nil ? NSColor.systemOrange.withAlphaComponent(0.55) : NSColor.white.withAlphaComponent(0.1)).cgColor

        let icon = NSImageView()
        if notice.code != nil || notice.action == .openAccessibilitySettings {
            icon.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Problem")
            icon.contentTintColor = .systemOrange
            icon.symbolConfiguration = .init(pointSize: 22, weight: .regular)
        } else {
            icon.image = NSApp.applicationIconImage
        }
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 32).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 32).isActive = true

        let text = NSStackView()
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 4
        text.addArrangedSubview(label(notice.title, size: 13, weight: .semibold))
        if !notice.detail.isEmpty { text.addArrangedSubview(label(notice.detail, size: 12, color: .secondaryLabelColor)) }
        if let code = notice.code {
            text.addArrangedSubview(label(code, size: 12, color: NSColor(red: 1, green: 0.85, blue: 0.63, alpha: 1), mono: true))
        }

        let buttons = NSStackView()
        buttons.spacing = 8
        if let action = notice.action {
            let title = action == .openConfig ? "Open Config" : "Open System Settings"
            buttons.addArrangedSubview(ToastButton(title: title) { perform(action); dismiss(panel) })
        }
        buttons.addArrangedSubview(ToastButton(title: "Dismiss") { dismiss(panel) })
        if let last = text.arrangedSubviews.last { text.setCustomSpacing(10, after: last) }
        text.addArrangedSubview(buttons)

        let row = NSStackView(views: [icon, text])
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 12
        row.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        row.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            row.topAnchor.constraint(equalTo: card.topAnchor),
            row.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            card.widthAnchor.constraint(equalToConstant: width),
        ])
        panel.contentView = card
        panel.setContentSize(card.fittingSize)
        return panel
    }

    private static func perform(_ action: Notice.Action) {
        switch action {
        case .openConfig:
            NSWorkspace.shared.open(ConfigFile.url)
        case .openAccessibilitySettings:
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}

private final class ToastButton: NSButton {
    private var handler: (@MainActor () -> Void)?

    convenience init(title: String, handler: @escaping @MainActor () -> Void) {
        self.init(frame: .zero)
        self.title = title
        self.handler = handler
        bezelStyle = .rounded
        controlSize = .small
        target = self
        action = #selector(fire)
    }

    @objc private func fire() { MainActor.assumeIsolated { handler?() } }
}
